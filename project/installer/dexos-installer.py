#!/usr/bin/python3
import json
import os
import subprocess
import threading
from pathlib import Path

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GLib

MIN_DISK = 8 * 1024**3

RED = '#7a3438'
DARK = '#211416'

def human_size(n):
    n = int(n)
    for unit in ['B','KiB','MiB','GiB','TiB']:
        if n < 1024 or unit == 'TiB':
            return f'{n:.1f} {unit}' if isinstance(n, float) else (f'{n/1024:.1f} GiB' if unit == 'TiB' else f'{n} {unit}')
        n /= 1024

def node_mounted(node):
    if any(x for x in (node.get('mountpoints') or []) if x): return True
    return any(node_mounted(c) for c in node.get('children') or [])

def discover_disks():
    try:
        raw = subprocess.check_output(['lsblk','-J','-b','-o','PATH,NAME,TYPE,SIZE,MODEL,RO,RM,TRAN,MOUNTPOINTS'], text=True)
        data = json.loads(raw)
    except Exception:
        return []
    out=[]
    for d in data.get('blockdevices',[]):
        if d.get('type') != 'disk' or int(d.get('ro') or 0) or int(d.get('size') or 0) < MIN_DISK or node_mounted(d):
            continue
        model=(d.get('model') or 'Disco').strip()
        tran=(d.get('tran') or '').upper()
        out.append((d['path'], f"{model} — {human_size(d['size'])}" + (f" — {tran}" if tran else '')))
    return out

def timezones():
    zones=[]
    p=Path('/usr/share/zoneinfo/zone.tab')
    if p.is_file():
        for line in p.read_text(errors='ignore').splitlines():
            if line and not line.startswith('#'):
                parts=line.split('\t')
                if len(parts)>=3: zones.append(parts[2])
    return sorted(set(zones)) or ['UTC']

class Installer(Gtk.Assistant):
    def __init__(self):
        super().__init__()
        self.set_title('Instalador de DexOS')
        self.set_default_size(820, 580)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.connect('cancel', lambda *_: self.destroy())
        self.connect('close', lambda *_: self.destroy())
        self.connect('prepare', self.on_prepare)
        self.connect('apply', self.on_apply)
        self.proc=None
        self.disks=[]
        self.installing=False
        self.apply_css()
        self.build_pages()

    def apply_css(self):
        css=Gtk.CssProvider()
        css.load_from_data(f'''
            assistant, window {{ background: {DARK}; }}
            .dex-title {{ font-size: 30px; font-weight: 700; color: #f0e5e5; }}
            .dex-subtitle {{ font-size: 15px; color: #d1a8aa; }}
            button.suggested-action {{ background-image: none; background-color: {RED}; color: white; }}
            progressbar progress {{ background-color: {RED}; }}
        '''.encode())
        Gtk.StyleContext.add_provider_for_screen(self.get_screen(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    def box(self):
        b=Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        b.set_border_width(28)
        return b

    def add_page(self, widget, title, kind, complete=False):
        self.append_page(widget); self.set_page_title(widget,title); self.set_page_type(widget,kind); self.set_page_complete(widget,complete)
        return widget

    def heading(self, box, title, subtitle=''):
        l=Gtk.Label(label=title); l.set_xalign(0); l.get_style_context().add_class('dex-title'); box.pack_start(l,False,False,0)
        if subtitle:
            s=Gtk.Label(label=subtitle); s.set_xalign(0); s.set_line_wrap(True); s.get_style_context().add_class('dex-subtitle'); box.pack_start(s,False,False,0)

    def build_pages(self):
        # Welcome
        b=self.box(); self.heading(b,'Instalar DexOS','Instalador gráfico seguro para equipos UEFI y BIOS.')
        t=Gtk.Label(label='Este asistente instalará DexOS en un disco completo. El disco seleccionado se borrará únicamente después de una confirmación explícita. La zona horaria se configura directamente, sin usar setup-alpine.'); t.set_xalign(0); t.set_line_wrap(True); b.pack_start(t,False,False,18)
        self.add_page(b,'Bienvenida',Gtk.AssistantPageType.INTRO,True)

        # Disk
        b=self.box(); self.heading(b,'Selecciona el disco','No se muestran medios Live ni discos con particiones montadas.')
        self.disk_combo=Gtk.ComboBoxText(); b.pack_start(self.disk_combo,False,False,8)
        btn=Gtk.Button(label='Actualizar discos'); btn.connect('clicked',lambda *_: self.refresh_disks()); b.pack_start(btn,False,False,0)
        w=Gtk.Label(label='⚠ Todo el contenido del disco elegido será eliminado. Se crearán particiones GPT para BIOS, EFI y sistema ext4.'); w.set_xalign(0); w.set_line_wrap(True); b.pack_start(w,False,False,12)
        self.disk_page=self.add_page(b,'Disco',Gtk.AssistantPageType.CONTENT,False)
        self.disk_combo.connect('changed',lambda *_: self.set_page_complete(self.disk_page,self.disk_combo.get_active()>=0))
        self.refresh_disks()

        # Timezone
        b=self.box(); self.heading(b,'Zona horaria','DexOS validará la zona contra tzdata y creará /etc/localtime directamente.')
        self.tz_combo=Gtk.ComboBoxText.new_with_entry(); self.tz_combo.set_entry_text_column(0)
        zones=timezones();
        for z in zones: self.tz_combo.append_text(z)
        default='America/Mexico_City' if 'America/Mexico_City' in zones else 'UTC'
        self.tz_combo.get_child().set_text(default)
        b.pack_start(self.tz_combo,False,False,8)
        self.tz_page=self.add_page(b,'Zona horaria',Gtk.AssistantPageType.CONTENT,True)

        # Account
        b=self.box(); self.heading(b,'Usuario','El usuario principal tendrá sudo. También puedes definir una contraseña independiente para root.')
        grid=Gtk.Grid(column_spacing=12,row_spacing=12)
        self.hostname=Gtk.Entry(); self.hostname.set_text('dexos-pc')
        self.username=Gtk.Entry(); self.username.set_text('usuario')
        self.password=Gtk.Entry(); self.password.set_visibility(False)
        self.password2=Gtk.Entry(); self.password2.set_visibility(False)
        self.root_password=Gtk.Entry(); self.root_password.set_visibility(False)
        self.root_password2=Gtk.Entry(); self.root_password2.set_visibility(False)
        for r,(label,w) in enumerate([('Nombre del equipo',self.hostname),('Usuario',self.username),('Contraseña',self.password),('Repetir contraseña',self.password2),('Contraseña root',self.root_password),('Repetir contraseña root',self.root_password2)]):
            l=Gtk.Label(label=label); l.set_xalign(1); grid.attach(l,0,r,1,1); grid.attach(w,1,r,1,1)
        b.pack_start(grid,False,False,8)
        self.account_error=Gtk.Label(); self.account_error.set_xalign(0); b.pack_start(self.account_error,False,False,0)
        self.account_page=self.add_page(b,'Usuario',Gtk.AssistantPageType.CONTENT,False)
        for e in [self.hostname,self.username,self.password,self.password2,self.root_password,self.root_password2]: e.connect('changed',self.validate_account)
        self.validate_account()

        # Confirm
        b=self.box(); self.heading(b,'Resumen','Revisa los datos antes de comenzar.')
        self.summary=Gtk.Label(); self.summary.set_xalign(0); self.summary.set_line_wrap(True); b.pack_start(self.summary,False,False,10)
        self.confirm=Gtk.CheckButton(label='Entiendo que el disco seleccionado será borrado completamente.'); self.confirm.connect('toggled',lambda w:self.set_page_complete(self.confirm_page,w.get_active())); b.pack_start(self.confirm,False,False,12)
        self.confirm_page=self.add_page(b,'Confirmación',Gtk.AssistantPageType.CONFIRM,False)

        # Progress
        b=self.box(); self.heading(b,'Instalando DexOS','No apagues el equipo durante esta operación.')
        self.progress=Gtk.ProgressBar(); self.progress.set_show_text(True); b.pack_start(self.progress,False,False,8)
        sw=Gtk.ScrolledWindow(); sw.set_vexpand(True); self.logview=Gtk.TextView(); self.logview.set_editable(False); self.logview.set_monospace(True); sw.add(self.logview); b.pack_start(sw,True,True,0)
        self.progress_page=self.add_page(b,'Instalación',Gtk.AssistantPageType.PROGRESS,False)

        # Finish
        b=self.box(); self.heading(b,'DexOS está listo','La instalación terminó correctamente.')
        self.finish_label=Gtk.Label(label='Reinicia el equipo y retira el medio Live.'); self.finish_label.set_xalign(0); self.finish_label.set_line_wrap(True); b.pack_start(self.finish_label,False,False,10)
        self.finish_page=self.add_page(b,'Finalizado',Gtk.AssistantPageType.SUMMARY,True)

    def refresh_disks(self):
        self.disk_combo.remove_all(); self.disks=discover_disks()
        for path,label in self.disks: self.disk_combo.append(path,label)
        if self.disks: self.disk_combo.set_active(0)
        else: self.disk_combo.append_text('No hay discos seguros disponibles'); self.disk_combo.set_active(0); self.set_page_complete(self.disk_page,False) if hasattr(self,'disk_page') else None

    def validate_account(self,*_):
        import re
        ok=True; msg=''
        if not re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?',self.hostname.get_text()): ok=False; msg='Nombre de equipo no válido.'
        elif not re.fullmatch(r'[a-z_][a-z0-9_-]{0,30}',self.username.get_text()) or self.username.get_text()=='root': ok=False; msg='Usuario no válido.'
        elif len(self.password.get_text())<8: ok=False; msg='La contraseña debe tener al menos 8 caracteres.'
        elif self.password.get_text()!=self.password2.get_text(): ok=False; msg='Las contraseñas del usuario no coinciden.'
        elif len(self.root_password.get_text())<8: ok=False; msg='La contraseña root debe tener al menos 8 caracteres.'
        elif self.root_password.get_text()!=self.root_password2.get_text(): ok=False; msg='Las contraseñas root no coinciden.'
        self.account_error.set_text(msg)
        if hasattr(self,'account_page'): self.set_page_complete(self.account_page,ok)

    def selected_disk(self):
        if not self.disks or self.disk_combo.get_active()<0: return None
        return self.disks[self.disk_combo.get_active()][0]

    def timezone(self):
        return self.tz_combo.get_child().get_text().strip()

    def on_prepare(self,assistant,page):
        if page is self.confirm_page:
            d=self.selected_disk(); self.confirm.set_active(False)
            self.summary.set_markup(f'<b>Disco:</b> {d}\n<b>Zona horaria:</b> {GLib.markup_escape_text(self.timezone())}\n<b>Equipo:</b> {GLib.markup_escape_text(self.hostname.get_text())}\n<b>Usuario:</b> {GLib.markup_escape_text(self.username.get_text())}\n\nSe borrará el disco completo y se instalará DexOS con GRUB BIOS + UEFI.')
        if page is self.progress_page and not self.installing:
            self.installing=True; threading.Thread(target=self.install_thread,daemon=True).start()

    def on_apply(self,*_):
        # Gtk.Assistant moves to progress after apply.
        pass

    def cfg(self):
        d=self.selected_disk()
        return {'disk':d,'hostname':self.hostname.get_text(),'username':self.username.get_text(),'password':self.password.get_text(),'root_password':self.root_password.get_text(),'timezone':self.timezone(),'erase_confirm':f'BORRAR {d}'}

    def append_log(self,text):
        buf=self.logview.get_buffer(); end=buf.get_end_iter(); buf.insert(end,text+'\n'); mark=buf.create_mark(None,buf.get_end_iter(),False); self.logview.scroll_mark_onscreen(mark)

    def install_thread(self):
        try:
            p=subprocess.Popen(['doas','/usr/local/libexec/dexos-installer-backend'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,bufsize=1)
            self.proc=p; p.stdin.write(json.dumps(self.cfg())+'\n'); p.stdin.close()
            for line in p.stdout:
                try: msg=json.loads(line)
                except Exception: GLib.idle_add(self.append_log,line.rstrip()); continue
                t=msg.get('type')
                if t=='log': GLib.idle_add(self.append_log,msg.get('message',''))
                elif t=='progress': GLib.idle_add(self.update_progress,msg)
                elif t=='done': GLib.idle_add(self.done,msg.get('message',''))
                elif t=='error': GLib.idle_add(self.failed,msg.get('message','Error desconocido'))
            rc=p.wait()
            if rc and self.installing: GLib.idle_add(self.failed,f'El instalador terminó con código {rc}.')
        except Exception as e:
            GLib.idle_add(self.failed,str(e))

    def update_progress(self,msg):
        self.progress.set_fraction(float(msg.get('value',0))); self.progress.set_text(msg.get('message',''))
        return False

    def done(self,message):
        self.installing=False; self.finish_label.set_text(message); self.set_page_complete(self.progress_page,True); self.set_current_page(self.get_n_pages()-1); return False

    def failed(self,message):
        self.installing=False; self.append_log('ERROR: '+message); self.progress.set_text('Error de instalación'); self.progress.set_fraction(0); dlg=Gtk.MessageDialog(transient_for=self,flags=0,message_type=Gtk.MessageType.ERROR,buttons=Gtk.ButtonsType.CLOSE,text='No se pudo instalar DexOS'); dlg.format_secondary_text(message); dlg.run(); dlg.destroy(); self.set_page_complete(self.progress_page,False); return False

if __name__=='__main__':
    w=Installer(); w.show_all(); Gtk.main()
