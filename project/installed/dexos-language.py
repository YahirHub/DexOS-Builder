#!/usr/bin/env python3
import os
from pathlib import Path
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk

CHOICES = [
    ('Español', 'es_ES.UTF-8', 'es_ES:es'),
    ('English', 'en_US.UTF-8', 'en_US:en'),
    ('Português', 'pt_BR.UTF-8', 'pt_BR:pt'),
    ('Français', 'fr_FR.UTF-8', 'fr_FR:fr'),
    ('Deutsch', 'de_DE.UTF-8', 'de_DE:de'),
    ('Italiano', 'it_IT.UTF-8', 'it_IT:it'),
]

def installed_locale():
    p = Path('/etc/dexos-locale')
    if p.is_file():
        val = p.read_text(errors='ignore').strip()
        if any(val == loc for _, loc, _ in CHOICES):
            return val
    return None

def saved_locale():
    p = Path.home()/'.config/dexos/locale'
    if p.is_file():
        val = p.read_text(errors='ignore').strip()
        if any(val == loc for _, loc, _ in CHOICES):
            return val
    return None

def save(locale):
    p = Path.home()/'.config/dexos/locale'
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(locale + '\n')

def choose():
    dialog = Gtk.Dialog(title='DexOS — Idioma / Language', flags=0)
    dialog.set_default_size(520, 320)
    dialog.set_position(Gtk.WindowPosition.CENTER_ALWAYS)
    area = dialog.get_content_area()
    area.set_spacing(12)
    title = Gtk.Label()
    title.set_markup('<span size="x-large" weight="bold">Elige el idioma / Choose language</span>')
    title.set_margin_top(18)
    area.pack_start(title, False, False, 0)
    subtitle = Gtk.Label(label='Se aplicará a esta sesión Live y al sistema que instales.')
    subtitle.set_margin_bottom(8)
    area.pack_start(subtitle, False, False, 0)
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=7)
    box.set_margin_start(28); box.set_margin_end(28); box.set_margin_bottom(20)
    area.pack_start(box, True, True, 0)
    selected = {'locale': None}
    def pick(_button, locale):
        selected['locale'] = locale
        dialog.response(Gtk.ResponseType.OK)
    for label, locale, _language in CHOICES:
        b = Gtk.Button(label=label)
        b.set_size_request(-1, 38)
        b.connect('clicked', pick, locale)
        box.pack_start(b, False, False, 0)
    dialog.show_all()
    while Gtk.events_pending():
        Gtk.main_iteration_do(False)
    display = Gdk.Display.get_default()
    window = dialog.get_window()
    if display is not None and window is not None:
        cursor = Gdk.Cursor.new_from_name(display, 'default') or Gdk.Cursor.new_from_name(display, 'left_ptr')
        if cursor is not None:
            window.set_cursor(cursor)
    dialog.present()
    dialog.run()
    dialog.destroy()
    return selected['locale'] or 'es_ES.UTF-8'

loc = installed_locale() or saved_locale()
if not loc:
    loc = choose()
    save(loc)
print(loc)
