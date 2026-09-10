#!/usr/bin/env python3
import os
import shutil
import sys
import subprocess
import threading

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import GLib, Gtk

BOOT_ORDER = '/usr/local/sbin/boot-order'
GRUB_UPDATE = '/usr/local/sbin/grub-update'


def run(cmd):
    return subprocess.run(cmd, text=True, capture_output=True, check=False)



def ensure_admin():
    if os.geteuid() == 0:
        return
    pkexec = shutil.which('pkexec')
    if not pkexec:
        raise SystemExit('Se requiere pkexec/polkit para administrar GRUB.')
    os.execv(pkexec, [pkexec, '/usr/local/bin/dexos-boot-manager'] + sys.argv[1:])



class BootManager(Gtk.Window):
    def __init__(self):
        super().__init__(title='Orden de arranque')
        self.set_default_size(620, 430)
        self.set_border_width(18)
        self.set_position(Gtk.WindowPosition.CENTER)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.add(box)

        title = Gtk.Label()
        title.set_markup('<span size="x-large" weight="bold">Orden de arranque de DexOS</span>')
        title.set_xalign(0)
        box.pack_start(title, False, False, 0)

        info = Gtk.Label(label='Elige qué sistema iniciará por defecto. También puedes volver a escanear todos los discos para añadir Windows, Linux y cargadores EFI detectados a GRUB.')
        info.set_line_wrap(True)
        info.set_xalign(0)
        box.pack_start(info, False, False, 0)

        frame = Gtk.Frame(label='Sistemas detectados')
        box.pack_start(frame, True, True, 0)
        sc = Gtk.ScrolledWindow()
        sc.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        frame.add(sc)
        self.listbox = Gtk.ListBox()
        self.listbox.set_selection_mode(Gtk.SelectionMode.SINGLE)
        sc.add(self.listbox)

        controls = Gtk.Box(spacing=8)
        box.pack_start(controls, False, False, 0)
        self.refresh_btn = Gtk.Button(label='Actualizar lista')
        self.scan_btn = Gtk.Button(label='Escanear discos y actualizar GRUB')
        self.apply_btn = Gtk.Button(label='Usar como predeterminado')
        self.apply_btn.get_style_context().add_class('suggested-action')
        controls.pack_start(self.refresh_btn, False, False, 0)
        controls.pack_start(self.scan_btn, False, False, 0)
        controls.pack_end(self.apply_btn, False, False, 0)

        status_box = Gtk.Box(spacing=8)
        box.pack_start(status_box, False, False, 0)
        self.spinner = Gtk.Spinner()
        self.status = Gtk.Label(label='')
        self.status.set_xalign(0)
        self.status.set_line_wrap(True)
        status_box.pack_start(self.spinner, False, False, 0)
        status_box.pack_start(self.status, True, True, 0)

        self.entries = []
        self.refresh_btn.connect('clicked', lambda *_: self.load_entries())
        self.scan_btn.connect('clicked', self.scan_disks)
        self.apply_btn.connect('clicked', self.set_default)
        self.listbox.connect('row-selected', lambda *_: self.update_apply_state())
        GLib.idle_add(self.load_entries)

    def set_busy(self, busy, message=''):
        for w in (self.refresh_btn, self.scan_btn, self.apply_btn):
            w.set_sensitive(not busy)
        if busy:
            self.spinner.start()
        else:
            self.spinner.stop()
            self.update_apply_state()
        if message:
            self.status.set_text(message)

    def update_apply_state(self):
        row = self.listbox.get_selected_row()
        self.apply_btn.set_sensitive(row is not None)

    def clear_rows(self):
        for child in list(self.listbox.get_children()):
            self.listbox.remove(child)

    def load_entries(self):
        self.clear_rows()
        self.entries = []
        result = run([BOOT_ORDER, '--list'])
        if result.returncode != 0:
            self.status.set_text((result.stderr or result.stdout or 'No se pudo leer GRUB.').strip())
            self.update_apply_state()
            return False
        current_row = None
        for line in result.stdout.splitlines():
            parts = line.split('\t', 2)
            if len(parts) != 3:
                continue
            idx, current, label = parts
            try:
                index = int(idx)
            except ValueError:
                continue
            row = Gtk.ListBoxRow()
            inner = Gtk.Box(spacing=10)
            inner.set_border_width(10)
            icon = Gtk.Image.new_from_icon_name('drive-harddisk', Gtk.IconSize.DIALOG)
            inner.pack_start(icon, False, False, 0)
            texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            primary = Gtk.Label(label=label)
            primary.set_xalign(0)
            primary.set_ellipsize(3)
            secondary = Gtk.Label(label='Predeterminado actual' if current == '1' else 'Disponible')
            secondary.set_xalign(0)
            texts.pack_start(primary, False, False, 0)
            texts.pack_start(secondary, False, False, 0)
            inner.pack_start(texts, True, True, 0)
            row.add(inner)
            row.dexos_index = index
            row.dexos_label = label
            self.listbox.add(row)
            self.entries.append((index, label))
            if current == '1':
                current_row = row
        self.listbox.show_all()
        if current_row is not None:
            self.listbox.select_row(current_row)
        self.status.set_text(f'{len(self.entries)} entradas de arranque detectadas.')
        self.update_apply_state()
        return False

    def set_default(self, *_):
        row = self.listbox.get_selected_row()
        if row is None:
            return
        self.set_busy(True, f'Guardando {row.dexos_label} como predeterminado…')
        self.run_async([BOOT_ORDER, '--set', str(row.dexos_index)], self.after_set)

    def after_set(self, result):
        self.set_busy(False)
        if result.returncode == 0:
            self.status.set_text((result.stdout or 'Orden de arranque actualizado.').strip())
            self.load_entries()
        else:
            self.show_error('No se pudo cambiar el arranque', result)

    def scan_disks(self, *_):
        self.set_busy(True, 'Escaneando todos los discos y regenerando GRUB…')
        self.run_async([GRUB_UPDATE], self.after_scan)

    def after_scan(self, result):
        self.set_busy(False)
        if result.returncode == 0:
            self.load_entries()
            self.status.set_text('Escaneo terminado. GRUB fue actualizado con los sistemas detectados.')
        else:
            self.show_error('No se pudo actualizar GRUB', result)

    def run_async(self, cmd, callback):
        def worker():
            result = run(cmd)
            GLib.idle_add(callback, result)
        threading.Thread(target=worker, daemon=True).start()

    def show_error(self, title, result):
        detail = (result.stderr or result.stdout or 'Operación cancelada o fallida.').strip()
        dlg = Gtk.MessageDialog(transient_for=self, flags=0, message_type=Gtk.MessageType.ERROR,
                                buttons=Gtk.ButtonsType.CLOSE, text=title)
        dlg.format_secondary_text(detail)
        dlg.run()
        dlg.destroy()
        self.status.set_text(detail)


def main():
    ensure_admin()
    win = BootManager()
    win.connect('destroy', Gtk.main_quit)
    win.show_all()
    Gtk.main()


if __name__ == '__main__':
    main()
