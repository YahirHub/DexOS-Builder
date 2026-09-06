#!/usr/bin/python3
import os, subprocess
import gi
gi.require_version('Gtk','3.0')
gi.require_version('GdkPixbuf','2.0')
from gi.repository import Gtk, Gdk, GdkPixbuf, GLib

IMG='/usr/share/dexos/boot.jpg'

class Splash(Gtk.Window):
    def __init__(self):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self.set_decorated(False); self.set_keep_above(True); self.set_skip_taskbar_hint(True); self.set_skip_pager_hint(True)
        self.fullscreen()
        screen=Gdk.Screen.get_default(); w=screen.get_width(); h=screen.get_height()
        overlay=Gtk.Overlay()
        try:
            src=GdkPixbuf.Pixbuf.new_from_file(IMG)
            iw,ih=src.get_width(),src.get_height()
            scale=max(w/iw,h/ih)
            sw,sh=max(w,int(iw*scale)),max(h,int(ih*scale))
            scaled=src.scale_simple(sw,sh,GdkPixbuf.InterpType.BILINEAR)
            x=max(0,(sw-w)//2); y=max(0,(sh-h)//2)
            pix=scaled.new_subpixbuf(x,y,w,h)
            image=Gtk.Image.new_from_pixbuf(pix)
        except Exception:
            image=Gtk.Image()
        overlay.add(image)
        box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=12); box.set_halign(Gtk.Align.CENTER); box.set_valign(Gtk.Align.END); box.set_margin_bottom(52)
        self.spinner=Gtk.Spinner(); self.spinner.set_size_request(42,42); self.spinner.start(); box.pack_start(self.spinner,False,False,0)
        self.label=Gtk.Label(label='Iniciando sesión'); self.label.set_name('dexos-session-label'); box.pack_start(self.label,False,False,0)
        overlay.add_overlay(box); self.add(overlay)
        css=Gtk.CssProvider(); css.load_from_data(b'#dexos-session-label { color:#ff8a1c; font-size:24px; font-weight:600; text-shadow:0 0 8px #e63818; } spinner { color:#ff7a00; }')
        Gtk.StyleContext.add_provider_for_screen(screen,css,Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.ticks=0; GLib.timeout_add(250,self.check_ready); GLib.timeout_add(450,self.animate)
    def alive(self,name):
        return subprocess.call(['pidof',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)==0
    def check_ready(self):
        self.ticks += 1
        if self.alive('xfce4-session') and self.alive('xfwm4') and self.alive('xfdesktop') and self.alive('xfce4-panel'):
            GLib.timeout_add(800,self.finish); return False
        if self.ticks > 480: self.finish(); return False
        return True
    def animate(self):
        n=(self.ticks//2)%4; self.label.set_text('Iniciando sesión'+'.'*n); return True
    def finish(self):
        self.destroy(); Gtk.main_quit(); return False

w=Splash(); w.show_all(); Gtk.main()
