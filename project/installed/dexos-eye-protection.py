#!/usr/bin/env python3
import configparser
import os
import signal
import subprocess
import sys
import time
from datetime import datetime
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
        data['autostart'] = cp.getboolean('eye-protection', 'autostart', fallback=data['enabled'])
        data['automatic'] = cp.getboolean('eye-protection', 'automatic', fallback=True)
    data['temperature'] = max(3000, min(6500, int(data['temperature'])))
    return data


def save_config(data):
    CFG.parent.mkdir(parents=True, exist_ok=True)
    cp = configparser.ConfigParser()
    cp['eye-protection'] = {
        'enabled': 'true' if data['enabled'] else 'false',
        'temperature': str(int(data['temperature'])),
        # Compatibility key: enabled Night Light is always restored on login.
        'autostart': 'true' if data['enabled'] else 'false',
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
            cmdline = Path(f'/proc/{pid}/cmdline').read_bytes().replace(b'\0', b' ').decode(errors='ignore')
        except OSError:
            cmdline = ''
        # PID files survive reboot; never kill an unrelated process if Linux
        # has already reused the old numeric PID.
        if 'dexos-eye-protection' in cmdline and '--auto-daemon' in cmdline:
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


def redshift_once(temp):
    return subprocess.run(
        ['redshift', '-m', 'randr', '-l', 'manual:lat=0:lon=0', '-P', '-O', str(int(temp))],
        text=True, capture_output=True, check=False,
    )


def reset_gamma():
    return subprocess.run(
        ['redshift', '-m', 'randr', '-l', 'manual:lat=0:lon=0', '-x'],
        text=True, capture_output=True, check=False,
    )


def fallback_temperature(night_temp, now=None):
    """Return a local-clock fallback temperature when geolocation is offline.

    Without coordinates an exact sunrise/sunset cannot be calculated. DexOS
    therefore uses the configured local timezone: warm at night, neutral by
    day, with two-hour dawn/dusk transitions.
    """
    now = now or datetime.now()
    hour = now.hour + now.minute / 60.0 + now.second / 3600.0
    night = max(3000, min(6500, int(night_temp)))
    day = 6500
    if 8 <= hour < 18:
        return day
    if hour >= 20 or hour < 6:
        return night
    if 6 <= hour < 8:
        ratio = (hour - 6) / 2.0
        return int(round(night + (day - night) * ratio))
    # 18:00-20:00
    ratio = (hour - 18) / 2.0
    return int(round(day + (night - day) * ratio))


def internet_available():
    """Use NetworkManager's connectivity result; no Internet means fallback."""
    try:
        result = subprocess.run(
            ['nmcli', '-t', '-f', 'CONNECTIVITY', 'general'],
            text=True, capture_output=True, check=False, timeout=5,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0 and result.stdout.strip().lower() == 'full'


def log_daemon(message):
    CACHE.mkdir(parents=True, exist_ok=True)
    with LOGFILE.open('a') as fh:
        stamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        fh.write(f'[{stamp}] {message}\n')


def automatic_daemon(night_temp):
    """Prefer GeoClue2 and fall back to the local clock while offline."""
    stopping = False
    child = None

    def request_stop(*_):
        nonlocal stopping
        stopping = True
        if child is not None and child.poll() is None:
            try:
                child.terminate()
            except ProcessLookupError:
                pass

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    last_clock_temp = None

    while not stopping:
        if internet_available():
            log_daemon('Internet disponible; usando GeoClue2 para amanecer/atardecer.')
            child = subprocess.Popen(
                ['redshift', '-m', 'randr', '-l', 'geoclue2', '-P', '-r', '-t', f'6500:{int(night_temp)}'],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            while not stopping and child.poll() is None:
                time.sleep(2)
            if stopping:
                break
            log_daemon(f'GeoClue2 terminó con código {child.returncode}; usando horario local hasta que vuelva a estar disponible.')
            child = None

        target = fallback_temperature(night_temp)
        if target != last_clock_temp:
            result = redshift_once(target)
            if result.returncode == 0:
                log_daemon(f'Sin Internet/GeoClue2: temperatura por hora local = {target} K.')
            else:
                log_daemon('Fallo al aplicar temperatura por hora local: ' + (result.stderr or '').strip())
            last_clock_temp = target

        # Retry once per minute. This keeps the fallback lightweight while
        # still adopting GeoClue2 shortly after Internet comes back.
        for _ in range(6):
            if stopping:
                break
            time.sleep(10)

    if child is not None and child.poll() is None:
        try:
            child.terminate()
            child.wait(timeout=3)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                child.kill()
            except ProcessLookupError:
                pass
    return 0


def start_automatic_daemon(temp):
    CACHE.mkdir(parents=True, exist_ok=True)
    with LOGFILE.open('a') as log:
        proc = subprocess.Popen(
            [sys.executable, '/usr/local/bin/dexos-eye-protection', '--auto-daemon', str(int(temp))],
            stdout=log, stderr=subprocess.STDOUT, start_new_session=True,
        )
    PIDFILE.write_text(str(proc.pid))
    return subprocess.CompletedProcess([], 0, '', '')


def apply(data):
    stop_daemon()
    if not data['enabled']:
        return reset_gamma()

    temp = int(data['temperature'])
    if data['automatic']:
        return start_automatic_daemon(temp)
    return redshift_once(temp)


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

        desc = Gtk.Label(label='Reduce la luz azul. Con Internet usa GeoClue2 para amanecer y atardecer; sin Internet continúa automáticamente usando la hora local.')
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

        self.auto = Gtk.CheckButton(label='Ajustar automáticamente (GeoClue2 + respaldo por hora local)')
        self.auto.set_active(self.data['automatic'])
        box.pack_start(self.auto, False, False, 0)

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
            'autostart': self.switch.get_active(),
            'automatic': self.auto.get_active(),
        }
        self.update_label()
        save_config(self.data)
        result = apply(self.data)
        if result.returncode == 0:
            if not self.data['enabled']:
                msg = 'Protección desactivada.'
            elif self.data['automatic']:
                msg = 'Protección automática activa. Usa GeoClue2 con Internet y la hora local sin conexión.'
            else:
                msg = 'Protección activa con temperatura manual.'
            if self.data['enabled']:
                msg += ' Se restaurará automáticamente al iniciar sesión.'
            self.status.set_text(msg)
        else:
            self.status.set_text((result.stderr or 'No se pudo ajustar la temperatura de color.').strip())


def main():
    if '--auto-daemon' in os.sys.argv:
        try:
            i = os.sys.argv.index('--auto-daemon')
            temp = int(os.sys.argv[i + 1])
        except (ValueError, IndexError):
            raise SystemExit(2)
        raise SystemExit(automatic_daemon(max(3000, min(6500, temp))))
    if '--startup' in os.sys.argv:
        data = load_config()
        if not data['enabled']:
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
