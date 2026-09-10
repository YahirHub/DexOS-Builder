#!/usr/bin/env python3
import configparser
import os
import signal
import subprocess
from pathlib import Path

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk

CFG = Path.home() / '.config/dexos/eye-protection.ini'
CACHE = Path.home() / '.cache/dexos'
PIDFILE = CACHE / 'redshift.pid'
LOGFILE = CACHE / 'redshift.log'
DEFAULT_TEMP = 4500


def load_config():
    data = {
        'enabled': False,
        'temperature': DEFAULT_TEMP,
        'autostart': False,
        'automatic': True,
    }
    cp = configparser.ConfigParser()
    if CFG.is_file():
        cp.read(CFG)
        data['enabled'] = cp.getboolean('eye-protection', 'enabled', fallback=False)
        data['temperature'] = cp.getint('eye-protection', 'temperature', fallback=DEFAULT_TEMP)
        data['autostart'] = cp.getboolean('eye-protection', 'autostart', fallback=False)
        data['automatic'] = cp.getboolean('eye-protection', 'automatic', fallback=True)
    data['temperature'] = max(3000, min(6500, int(data['temperature'])))
    return data


def save_config(data):
    CFG.parent.mkdir(parents=True, exist_ok=True)
    cp = configparser.ConfigParser()
    cp['eye-protection'] = {
        'enabled': 'true' if data['enabled'] else 'false',
        'temperature': str(int(data['temperature'])),
        'autostart': 'true' if data['autostart'] else 'false',
        'automatic': 'true' if data['automatic'] else 'false',
    }
    with CFG.open('w') as fh:
        cp.write(fh)


def stop_daemon():
    try:
        pid = int(PIDFILE.read_text().strip())
    except (OSError, ValueError):
        pid = None
    if pid:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        except PermissionError:
            pass
    try:
        PIDFILE.unlink()
    except FileNotFoundError:
        pass


def reset_gamma():
    return subprocess.run(
        ['redshift', '-m', 'randr', '-l', 'manual:lat=0:lon=0', '-x'],
        text=True, capture_output=True, check=False,
    )


def apply(data):
    stop_daemon()
    if not data['enabled']:
        return reset_gamma()

    temp = str(int(data['temperature']))
    if data['automatic']:
        CACHE.mkdir(parents=True, exist_ok=True)
        log = LOGFILE.open('a')
        proc = subprocess.Popen(
            ['redshift', '-m', 'randr', '-l', 'geoclue2', '-P', '-r', '-t', f'6500:{temp}'],
            stdout=log, stderr=subprocess.STDOUT, start_new_session=True,
        )
        PIDFILE.write_text(str(proc.pid))
        return subprocess.CompletedProcess([], 0, '', '')

    return subprocess.run(
        ['redshift', '-m', 'randr', '-l', 'manual:lat=0:lon=0', '-P', '-O', temp],
        text=True, capture_output=True, check=False,
    )


class EyeProtection(Gtk.Window):
    def __init__(self):
        super().__init__(title='Protección de la vista')
        self.set_default_size(520, 355)
        self.set_border_width(20)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.data = load_config()
        self.loading = True

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        self.add(box)
        title = Gtk.Label()
        title.set_markup('<span size="x-large" weight="bold">Protección de la vista</span>')
        title.set_xalign(0)
        box.pack_start(title, False, False, 0)

        desc = Gtk.Label(label='Reduce la luz azul. Puede usar GeoClue2 para ajustar automáticamente la temperatura según amanecer y atardecer.')
        desc.set_line_wrap(True)
        desc.set_xalign(0)
        box.pack_start(desc, False, False, 0)

        row = Gtk.Box(spacing=12)
        label = Gtk.Label(label='Activar luz cálida')
        label.set_xalign(0)
        self.switch = Gtk.Switch()
        self.switch.set_active(self.data['enabled'])
        row.pack_start(label, True, True, 0)
        row.pack_end(self.switch, False, False, 0)
        box.pack_start(row, False, False, 0)

        self.auto = Gtk.CheckButton(label='Ajustar automáticamente con ubicación (GeoClue2)')
        self.auto.set_active(self.data['automatic'])
        box.pack_start(self.auto, False, False, 0)

        self.autostart = Gtk.CheckButton(label='Iniciar protección automáticamente al entrar a DexOS')
        self.autostart.set_active(self.data['autostart'])
        box.pack_start(self.autostart, False, False, 0)

        self.temp_label = Gtk.Label()
        self.temp_label.set_xalign(0)
        box.pack_start(self.temp_label, False, False, 0)
        adj = Gtk.Adjustment(value=self.data['temperature'], lower=3000, upper=6500, step_increment=100, page_increment=500)
        self.scale = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL, adjustment=adj)
        self.scale.set_draw_value(False)
        self.scale.set_hexpand(True)
        box.pack_start(self.scale, False, False, 0)

        hint = Gtk.Label(label='Más cálido  ←                                      →  Más neutro')
        hint.set_xalign(0)
        box.pack_start(hint, False, False, 0)
        self.status = Gtk.Label(label='')
        self.status.set_xalign(0)
        self.status.set_line_wrap(True)
        box.pack_end(self.status, False, False, 0)

        self.switch.connect('notify::active', self.changed)
        self.auto.connect('toggled', self.changed)
        self.autostart.connect('toggled', self.changed)
        self.scale.connect('value-changed', self.changed)
        self.loading = False
        self.update_label()

    def update_label(self):
        suffix = ' (temperatura nocturna)' if self.auto.get_active() else ''
        self.temp_label.set_text(f'Temperatura: {int(self.scale.get_value())} K{suffix}')

    def changed(self, *_):
        if self.loading:
            return
        self.data = {
            'enabled': self.switch.get_active(),
            'temperature': int(self.scale.get_value()),
            'autostart': self.autostart.get_active(),
            'automatic': self.auto.get_active(),
        }
        self.update_label()
        save_config(self.data)
        result = apply(self.data)
        if result.returncode == 0:
            if not self.data['enabled']:
                msg = 'Protección desactivada.'
            elif self.data['automatic']:
                msg = 'Protección activa con ajuste automático por GeoClue2.'
            else:
                msg = 'Protección activa con temperatura manual.'
            if self.data['autostart']:
                msg += ' Se restaurará al iniciar sesión.'
            self.status.set_text(msg)
        else:
            self.status.set_text((result.stderr or 'No se pudo ajustar la temperatura de color.').strip())


def main():
    if '--startup' in os.sys.argv:
        data = load_config()
        if not data['autostart']:
            raise SystemExit(0)
        raise SystemExit(apply(data).returncode)
    if '--apply' in os.sys.argv:
        raise SystemExit(apply(load_config()).returncode)
    win = EyeProtection()
    win.connect('destroy', Gtk.main_quit)
    win.show_all()
    Gtk.main()


if __name__ == '__main__':
    main()
