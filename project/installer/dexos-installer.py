#!/usr/bin/python3
import json
import os
import re
import subprocess
import threading
from pathlib import Path

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GLib

MIN_ROOT = 10 * 1024**3
MIN_ALONGSIDE = 12 * 1024**3
RED = '#7a3438'
DARK = '#211416'


def human_size(n):
    n = float(n or 0)
    for unit in ['B', 'KiB', 'MiB', 'GiB', 'TiB']:
        if n < 1024 or unit == 'TiB':
            return f'{n:.1f} {unit}'
        n /= 1024


def timezones():
    zones = []
    p = Path('/usr/share/zoneinfo/zone.tab')
    if p.is_file():
        for line in p.read_text(errors='ignore').splitlines():
            if line and not line.startswith('#'):
                parts = line.split('\t')
                if len(parts) >= 3:
                    zones.append(parts[2])
    return sorted(set(zones)) or ['UTC']


def backend_probe():
    try:
        raw = subprocess.check_output(
            ['doas', '/usr/local/libexec/dexos-installer-backend', '--probe'],
            text=True, stderr=subprocess.STDOUT, timeout=45,
        )
        for line in reversed(raw.splitlines()):
            try:
                msg = json.loads(line)
            except Exception:
                continue
            if msg.get('type') == 'probe':
                return msg.get('data') or {'disks': [], 'partitions': [], 'oses': []}
    except Exception:
        pass
    return {'disks': [], 'partitions': [], 'oses': []}


class Installer(Gtk.Assistant):
    def __init__(self):
        super().__init__()
        self.set_title('Instalador de DexOS')
        self.set_default_size(900, 680)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.connect('cancel', lambda *_: self.destroy())
        self.connect('close', lambda *_: self.destroy())
        self.connect('prepare', self.on_prepare)
        self.connect('apply', self.on_apply)
        self.proc = None
        self.installing = False
        self.probe = {'disks': [], 'partitions': [], 'oses': []}
        self.erase_items = []
        self.along_disk_items = []
        self.along_free_items = []
        self.along_efi_items = []
        self.manual_root_items = []
        self.manual_efi_items = []
        self.apply_css()
        self.build_pages()
        self.refresh_probe()

    def apply_css(self):
        css = Gtk.CssProvider()
        css.load_from_data(f'''
            assistant, window {{ background: {DARK}; }}
            .dex-title {{ font-size: 30px; font-weight: 700; color: #f0e5e5; }}
            .dex-subtitle {{ font-size: 15px; color: #d1a8aa; }}
            button.suggested-action {{ background-image: none; background-color: {RED}; color: white; }}
            progressbar progress {{ background-color: {RED}; }}
        '''.encode())
        Gtk.StyleContext.add_provider_for_screen(self.get_screen(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    def box(self):
        b = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        b.set_border_width(28)
        return b

    def add_page(self, widget, title, kind, complete=False):
        self.append_page(widget)
        self.set_page_title(widget, title)
        self.set_page_type(widget, kind)
        self.set_page_complete(widget, complete)
        return widget

    def heading(self, box_, title, subtitle=''):
        l = Gtk.Label(label=title)
        l.set_xalign(0)
        l.get_style_context().add_class('dex-title')
        box_.pack_start(l, False, False, 0)
        if subtitle:
            s = Gtk.Label(label=subtitle)
            s.set_xalign(0)
            s.set_line_wrap(True)
            s.get_style_context().add_class('dex-subtitle')
            box_.pack_start(s, False, False, 0)

    def combo_row(self, box_, label, combo):
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        l = Gtk.Label(label=label)
        l.set_xalign(0)
        l.set_size_request(190, -1)
        row.pack_start(l, False, False, 0)
        row.pack_start(combo, True, True, 0)
        box_.pack_start(row, False, False, 0)

    def build_pages(self):
        b = self.box()
        self.heading(b, 'Instalar DexOS', 'Instalación completa, junto a Windows o con particionado manual.')
        t = Gtk.Label(label='DexOS puede conservar un Windows existente y reutilizar su partición EFI. En modo manual sólo se formatea la partición raíz que selecciones. Antes de instalar puedes abrir GParted para crear o ajustar particiones.')
        t.set_xalign(0); t.set_line_wrap(True); b.pack_start(t, False, False, 18)
        self.add_page(b, 'Bienvenida', Gtk.AssistantPageType.INTRO, True)

        # Partitioning / installation mode.
        b = self.box()
        self.heading(b, 'Destino e instalación', 'El instalador analiza discos, espacio libre, particiones EFI y otros sistemas operativos.')
        self.detected = Gtk.Label(); self.detected.set_xalign(0); self.detected.set_line_wrap(True); b.pack_start(self.detected, False, False, 0)

        self.erase_radio = Gtk.RadioButton.new_with_label_from_widget(None, 'Borrar disco e instalar DexOS')
        self.along_radio = Gtk.RadioButton.new_with_label_from_widget(self.erase_radio, 'Instalar junto a Windows')
        self.manual_radio = Gtk.RadioButton.new_with_label_from_widget(self.erase_radio, 'Particionado manual / dualboot')
        for w in (self.erase_radio, self.along_radio, self.manual_radio):
            w.connect('toggled', self.mode_changed); b.pack_start(w, False, False, 0)

        self.mode_stack = Gtk.Stack(); self.mode_stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)

        # Erase panel.
        erase = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10); erase.set_border_width(10)
        self.erase_combo = Gtk.ComboBoxText(); self.erase_combo.connect('changed', self.selection_changed)
        self.combo_row(erase, 'Disco completo', self.erase_combo)
        warn = Gtk.Label(label='⚠ Se eliminarán todas las particiones del disco seleccionado.')
        warn.set_xalign(0); warn.set_line_wrap(True); erase.pack_start(warn, False, False, 0)
        self.mode_stack.add_named(erase, 'erase')

        # Alongside panel.
        along = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10); along.set_border_width(10)
        self.along_disk_combo = Gtk.ComboBoxText(); self.along_disk_combo.connect('changed', self.along_disk_changed)
        self.along_free_combo = Gtk.ComboBoxText(); self.along_free_combo.connect('changed', self.selection_changed)
        self.along_efi_combo = Gtk.ComboBoxText(); self.along_efi_combo.connect('changed', self.selection_changed)
        self.combo_row(along, 'Disco con Windows', self.along_disk_combo)
        self.combo_row(along, 'Espacio sin asignar', self.along_free_combo)
        self.combo_row(along, 'Partición EFI', self.along_efi_combo)
        self.along_hint = Gtk.Label(label='DexOS sólo usa espacio sin asignar; no reduce NTFS automáticamente. Si no hay al menos 12 GiB libres, usa GParted primero.')
        self.along_hint.set_xalign(0); self.along_hint.set_line_wrap(True); along.pack_start(self.along_hint, False, False, 0)
        self.mode_stack.add_named(along, 'alongside')

        # Manual panel.
        manual = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10); manual.set_border_width(10)
        self.manual_root_combo = Gtk.ComboBoxText(); self.manual_root_combo.connect('changed', self.selection_changed)
        self.manual_efi_combo = Gtk.ComboBoxText(); self.manual_efi_combo.connect('changed', self.selection_changed)
        self.combo_row(manual, 'Partición raíz /', self.manual_root_combo)
        self.combo_row(manual, 'Partición EFI /boot/efi', self.manual_efi_combo)
        mw = Gtk.Label(label='⚠ La partición raíz elegida se formateará en ext4. La partición EFI se conserva y DexOS crea EFI/DexOS sin borrar Microsoft u otros cargadores.')
        mw.set_xalign(0); mw.set_line_wrap(True); manual.pack_start(mw, False, False, 0)
        self.mode_stack.add_named(manual, 'manual')
        b.pack_start(self.mode_stack, True, True, 4)

        buttons = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        refresh = Gtk.Button(label='Actualizar detección'); refresh.connect('clicked', lambda *_: self.refresh_probe())
        gparted = Gtk.Button(label='Abrir GParted'); gparted.connect('clicked', self.open_gparted)
        buttons.pack_start(refresh, False, False, 0); buttons.pack_start(gparted, False, False, 0)
        b.pack_start(buttons, False, False, 0)
        self.partition_page = self.add_page(b, 'Destino', Gtk.AssistantPageType.CONTENT, False)
        self.erase_radio.set_active(True)

        # Timezone.
        b = self.box(); self.heading(b, 'Zona horaria', 'Se configura directamente con tzdata.')
        self.tz_combo = Gtk.ComboBoxText.new_with_entry(); self.tz_combo.set_entry_text_column(0)
        zones = timezones()
        for z in zones: self.tz_combo.append_text(z)
        default = 'America/Mexico_City' if 'America/Mexico_City' in zones else 'UTC'
        self.tz_combo.get_child().set_text(default); b.pack_start(self.tz_combo, False, False, 8)
        self.tz_page = self.add_page(b, 'Zona horaria', Gtk.AssistantPageType.CONTENT, True)

        # Account.
        b = self.box(); self.heading(b, 'Usuario', 'El usuario principal tendrá sudo; root mantiene una contraseña independiente.')
        grid = Gtk.Grid(column_spacing=12, row_spacing=12)
        self.hostname = Gtk.Entry(); self.hostname.set_text('dexos-pc')
        self.username = Gtk.Entry(); self.username.set_text('usuario')
        self.password = Gtk.Entry(); self.password.set_visibility(False)
        self.password2 = Gtk.Entry(); self.password2.set_visibility(False)
        self.root_password = Gtk.Entry(); self.root_password.set_visibility(False)
        self.root_password2 = Gtk.Entry(); self.root_password2.set_visibility(False)
        fields = [('Nombre del equipo', self.hostname), ('Usuario', self.username), ('Contraseña', self.password), ('Repetir contraseña', self.password2), ('Contraseña root', self.root_password), ('Repetir contraseña root', self.root_password2)]
        for r, (label, w) in enumerate(fields):
            l = Gtk.Label(label=label); l.set_xalign(1); grid.attach(l, 0, r, 1, 1); grid.attach(w, 1, r, 1, 1)
        b.pack_start(grid, False, False, 8)
        self.account_error = Gtk.Label(); self.account_error.set_xalign(0); b.pack_start(self.account_error, False, False, 0)
        self.account_page = self.add_page(b, 'Usuario', Gtk.AssistantPageType.CONTENT, False)
        for e in [self.hostname, self.username, self.password, self.password2, self.root_password, self.root_password2]:
            e.connect('changed', self.validate_account)
        self.validate_account()

        # Confirm.
        b = self.box(); self.heading(b, 'Resumen', 'Revisa cuidadosamente qué se modificará.')
        self.summary = Gtk.Label(); self.summary.set_xalign(0); self.summary.set_line_wrap(True); b.pack_start(self.summary, False, False, 10)
        self.confirm = Gtk.CheckButton(); self.confirm.connect('toggled', lambda w: self.set_page_complete(self.confirm_page, w.get_active()))
        b.pack_start(self.confirm, False, False, 12)
        self.confirm_page = self.add_page(b, 'Confirmación', Gtk.AssistantPageType.CONFIRM, False)

        # Progress.
        b = self.box(); self.heading(b, 'Instalando DexOS', 'No apagues el equipo durante esta operación.')
        self.progress = Gtk.ProgressBar(); self.progress.set_show_text(True); b.pack_start(self.progress, False, False, 8)
        sw = Gtk.ScrolledWindow(); sw.set_vexpand(True); self.logview = Gtk.TextView(); self.logview.set_editable(False); self.logview.set_monospace(True); sw.add(self.logview); b.pack_start(sw, True, True, 0)
        self.progress_page = self.add_page(b, 'Instalación', Gtk.AssistantPageType.PROGRESS, False)

        # Finish.
        b = self.box(); self.heading(b, 'DexOS está listo', 'La instalación terminó correctamente.')
        self.finish_label = Gtk.Label(label='Reinicia el equipo y retira el medio Live.'); self.finish_label.set_xalign(0); self.finish_label.set_line_wrap(True); b.pack_start(self.finish_label, False, False, 10)
        self.finish_page = self.add_page(b, 'Finalizado', Gtk.AssistantPageType.SUMMARY, True)

    def selected_value(self, combo, items, key='path'):
        i = combo.get_active()
        if i < 0 or i >= len(items): return None
        item = items[i]
        return item.get(key) if isinstance(item, dict) else item[0]

    def refresh_probe(self):
        self.probe = backend_probe()
        disks = self.probe.get('disks') or []
        oses = self.probe.get('oses') or []
        if oses:
            names = ', '.join(sorted(set(x.get('name', 'Sistema') for x in oses)))
            self.detected.set_text('Sistemas detectados: ' + names)
        elif any(d.get('windows') for d in disks):
            self.detected.set_text('Windows detectado mediante su partición EFI.')
        else:
            self.detected.set_text('No se detectaron otros sistemas operativos.')

        self.erase_combo.remove_all(); self.erase_items = [d for d in disks if d.get('erase_safe')]
        for d in self.erase_items:
            self.erase_combo.append_text(f"{d['path']} — {d.get('model','Disco')} — {human_size(d.get('size'))}")
        if self.erase_items: self.erase_combo.set_active(0)

        self.along_disk_combo.remove_all(); self.along_disk_items = [d for d in disks if d.get('windows')]
        for d in self.along_disk_items:
            free = max([r.get('size', 0) for r in d.get('free_regions') or []] or [0])
            self.along_disk_combo.append_text(f"{d['path']} — Windows — libre máx. {human_size(free)}")
        if self.along_disk_items: self.along_disk_combo.set_active(0)
        else: self.populate_alongside(None)

        self.manual_root_combo.remove_all(); self.manual_root_items = []
        self.manual_efi_combo.remove_all(); self.manual_efi_items = []
        for p in self.probe.get('partitions') or []:
            if p.get('efi') and not p.get('mounted'):
                self.manual_efi_items.append(p)
                suffix = ' — Windows EFI' if p.get('windows_efi') else ''
                self.manual_efi_combo.append_text(f"{p['path']} — {human_size(p.get('size'))}{suffix}")
            elif not p.get('mounted') and int(p.get('size') or 0) >= MIN_ROOT:
                self.manual_root_items.append(p)
                fs = p.get('fstype') or 'sin formato'
                label = f" — {p.get('label')}" if p.get('label') else ''
                self.manual_root_combo.append_text(f"{p['path']} — {human_size(p.get('size'))} — {fs}{label}")
        if self.manual_root_items: self.manual_root_combo.set_active(0)
        if self.manual_efi_items: self.manual_efi_combo.set_active(0)
        self.update_partition_complete()

    def populate_alongside(self, disk):
        self.along_free_combo.remove_all(); self.along_free_items = []
        self.along_efi_combo.remove_all(); self.along_efi_items = []
        if not disk:
            self.update_partition_complete(); return
        self.along_free_items = [r for r in (disk.get('free_regions') or []) if int(r.get('size') or 0) >= MIN_ALONGSIDE]
        for r in self.along_free_items:
            self.along_free_combo.append_text(f"{human_size(r.get('size'))} sin asignar")
        if self.along_free_items: self.along_free_combo.set_active(0)
        pmap = {p.get('path'): p for p in disk.get('partitions') or []}
        self.along_efi_items = [pmap[x] for x in disk.get('efi_partitions') or [] if x in pmap and not pmap[x].get('mounted')]
        self.along_efi_items.sort(key=lambda p: (not p.get('windows_efi'), p.get('path')))
        for p in self.along_efi_items:
            suffix = ' — Microsoft/Windows' if p.get('windows_efi') else ''
            self.along_efi_combo.append_text(f"{p['path']} — {human_size(p.get('size'))}{suffix}")
        if self.along_efi_items: self.along_efi_combo.set_active(0)
        if disk.get('windows') and not self.along_free_items:
            self.along_hint.set_text('Windows fue detectado, pero no hay al menos 12 GiB sin asignar. Abre GParted, reduce una partición de Windows y deja espacio SIN ASIGNAR; después pulsa “Actualizar detección”.')
        else:
            self.along_hint.set_text('DexOS sólo usa espacio sin asignar y conserva Windows/EFI. No se reduce NTFS automáticamente.')
        self.update_partition_complete()

    def along_disk_changed(self, *_):
        i = self.along_disk_combo.get_active()
        self.populate_alongside(self.along_disk_items[i] if 0 <= i < len(self.along_disk_items) else None)

    def selection_changed(self, *_):
        self.update_partition_complete()

    def mode(self):
        if self.along_radio.get_active(): return 'alongside'
        if self.manual_radio.get_active(): return 'manual'
        return 'erase'

    def mode_changed(self, *_):
        mode = self.mode()
        self.mode_stack.set_visible_child_name(mode)
        self.update_partition_complete()

    def update_partition_complete(self):
        if not hasattr(self, 'partition_page'): return
        mode = self.mode()
        if mode == 'erase': ok = bool(self.erase_items) and self.erase_combo.get_active() >= 0
        elif mode == 'alongside': ok = bool(self.along_disk_items and self.along_free_items and self.along_efi_items) and self.along_disk_combo.get_active() >= 0 and self.along_free_combo.get_active() >= 0 and self.along_efi_combo.get_active() >= 0
        else: ok = bool(self.manual_root_items and self.manual_efi_items) and self.manual_root_combo.get_active() >= 0 and self.manual_efi_combo.get_active() >= 0
        self.set_page_complete(self.partition_page, ok)

    def open_gparted(self, *_):
        env = os.environ.copy()
        cmd = ['doas', 'env']
        if env.get('DISPLAY'): cmd.append('DISPLAY=' + env['DISPLAY'])
        if env.get('XAUTHORITY'): cmd.append('XAUTHORITY=' + env['XAUTHORITY'])
        cmd.append('gparted')
        try:
            p = subprocess.Popen(cmd)
            def wait_refresh():
                p.wait(); GLib.idle_add(self.refresh_probe)
            threading.Thread(target=wait_refresh, daemon=True).start()
        except Exception as e:
            self.error_dialog('No se pudo abrir GParted', str(e))

    def validate_account(self, *_):
        ok = True; msg = ''
        if not re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?', self.hostname.get_text()): ok=False; msg='Nombre de equipo no válido.'
        elif not re.fullmatch(r'[a-z_][a-z0-9_-]{0,30}', self.username.get_text()) or self.username.get_text() == 'root': ok=False; msg='Usuario no válido.'
        elif len(self.password.get_text()) < 8: ok=False; msg='La contraseña debe tener al menos 8 caracteres.'
        elif self.password.get_text() != self.password2.get_text(): ok=False; msg='Las contraseñas del usuario no coinciden.'
        elif len(self.root_password.get_text()) < 8: ok=False; msg='La contraseña root debe tener al menos 8 caracteres.'
        elif self.root_password.get_text() != self.root_password2.get_text(): ok=False; msg='Las contraseñas root no coinciden.'
        self.account_error.set_text(msg)
        if hasattr(self, 'account_page'): self.set_page_complete(self.account_page, ok)

    def timezone(self):
        return self.tz_combo.get_child().get_text().strip()

    def cfg(self):
        base = {
            'mode': self.mode(), 'hostname': self.hostname.get_text(), 'username': self.username.get_text(),
            'password': self.password.get_text(), 'root_password': self.root_password.get_text(), 'timezone': self.timezone(),
            'locale': os.environ.get('LANG', 'es_ES.UTF-8'),
        }
        if base['mode'] == 'erase':
            d = self.erase_items[self.erase_combo.get_active()]['path']; base.update(disk=d, confirm=f'BORRAR {d}')
        elif base['mode'] == 'alongside':
            d = self.along_disk_items[self.along_disk_combo.get_active()]['path']
            r = self.along_free_items[self.along_free_combo.get_active()]
            e = self.along_efi_items[self.along_efi_combo.get_active()]['path']
            base.update(disk=d, efi_partition=e, free_start=r['start'], free_end=r['end'], confirm=f'INSTALAR JUNTO A {d}')
        else:
            root = self.manual_root_items[self.manual_root_combo.get_active()]['path']
            efi = self.manual_efi_items[self.manual_efi_combo.get_active()]['path']
            base.update(root_partition=root, efi_partition=efi, confirm=f'FORMATEAR {root}')
        return base

    def on_prepare(self, assistant, page):
        if page is self.confirm_page:
            cfg = self.cfg(); self.confirm.set_active(False)
            common = f"\n<b>Zona horaria:</b> {GLib.markup_escape_text(self.timezone())}\n<b>Equipo:</b> {GLib.markup_escape_text(self.hostname.get_text())}\n<b>Usuario:</b> {GLib.markup_escape_text(self.username.get_text())}"
            if cfg['mode'] == 'erase':
                detail = f"<b>Modo:</b> borrar disco completo\n<b>Disco:</b> {cfg['disk']}\n\nSe eliminarán TODAS las particiones de ese disco."
                self.confirm.set_label('Entiendo que el disco seleccionado será borrado completamente.')
            elif cfg['mode'] == 'alongside':
                detail = f"<b>Modo:</b> instalar junto a Windows\n<b>Disco:</b> {cfg['disk']}\n<b>EFI conservada:</b> {cfg['efi_partition']}\n<b>Espacio libre:</b> {human_size(cfg['free_end']-cfg['free_start'])}\n\nWindows y la partición EFI se conservarán."
                self.confirm.set_label('Entiendo que DexOS creará una partición nueva únicamente en el espacio sin asignar seleccionado.')
            else:
                detail = f"<b>Modo:</b> particionado manual / dualboot\n<b>Raíz a FORMATEAR:</b> {cfg['root_partition']}\n<b>EFI a conservar:</b> {cfg['efi_partition']}"
                self.confirm.set_label('Entiendo que la partición raíz seleccionada será formateada y que la EFI se conservará.')
            self.summary.set_markup(detail + common + '\n\nGRUB usará el tema Argon y buscará otros sistemas operativos.')
        if page is self.progress_page and not self.installing:
            self.installing = True; threading.Thread(target=self.install_thread, daemon=True).start()

    def on_apply(self, *_):
        pass

    def append_log(self, text):
        buf = self.logview.get_buffer(); end = buf.get_end_iter(); buf.insert(end, text + '\n')
        mark = buf.create_mark(None, buf.get_end_iter(), False); self.logview.scroll_mark_onscreen(mark)

    def install_thread(self):
        try:
            p = subprocess.Popen(['doas', '/usr/local/libexec/dexos-installer-backend'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
            self.proc = p; p.stdin.write(json.dumps(self.cfg()) + '\n'); p.stdin.close()
            for line in p.stdout:
                try: msg = json.loads(line)
                except Exception: GLib.idle_add(self.append_log, line.rstrip()); continue
                t = msg.get('type')
                if t == 'log': GLib.idle_add(self.append_log, msg.get('message', ''))
                elif t == 'progress': GLib.idle_add(self.update_progress, msg)
                elif t == 'done': GLib.idle_add(self.done, msg.get('message', ''))
                elif t == 'error': GLib.idle_add(self.failed, msg.get('message', 'Error desconocido'))
            rc = p.wait()
            if rc and self.installing: GLib.idle_add(self.failed, f'El instalador terminó con código {rc}.')
        except Exception as e:
            GLib.idle_add(self.failed, str(e))

    def update_progress(self, msg):
        self.progress.set_fraction(float(msg.get('value', 0))); self.progress.set_text(msg.get('message', '')); return False

    def done(self, message):
        self.installing = False
        final = 'DexOS se instaló correctamente. Debes reiniciar el equipo para iniciar DexOS desde el disco instalado. Retira el medio Live al reiniciar.'
        self.finish_label.set_text(final)
        self.set_page_complete(self.progress_page, True)
        self.set_current_page(self.get_n_pages() - 1)
        dlg = Gtk.MessageDialog(transient_for=self, flags=0, message_type=Gtk.MessageType.INFO,
                                buttons=Gtk.ButtonsType.NONE, text='Instalación de DexOS completada')
        dlg.format_secondary_text(final)
        dlg.add_button('Más tarde', Gtk.ResponseType.CLOSE)
        dlg.add_button('Reiniciar ahora', Gtk.ResponseType.OK)
        dlg.set_default_response(Gtk.ResponseType.OK)
        response = dlg.run(); dlg.destroy()
        if response == Gtk.ResponseType.OK:
            try: subprocess.Popen(['doas', 'reboot'])
            except Exception as e: self.error_dialog('No se pudo reiniciar', str(e))
        return False

    def error_dialog(self, title, message):
        dlg = Gtk.MessageDialog(transient_for=self, flags=0, message_type=Gtk.MessageType.ERROR, buttons=Gtk.ButtonsType.CLOSE, text=title)
        dlg.format_secondary_text(message); dlg.run(); dlg.destroy()

    def failed(self, message):
        self.installing = False; self.append_log('ERROR: ' + message); self.progress.set_text('Error de instalación'); self.progress.set_fraction(0)
        self.error_dialog('No se pudo instalar DexOS', message); self.set_page_complete(self.progress_page, False); return False


if __name__ == '__main__':
    w = Installer(); w.show_all(); Gtk.main()
