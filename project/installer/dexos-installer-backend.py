#!/usr/bin/python3
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

TARGET = Path('/mnt/dexos-target')
MIN_DISK = 8 * 1024**3
MIN_ROOT = 10 * 1024**3
MIN_ALONGSIDE = 12 * 1024**3
SUPPORTED_LOCALES = {'es_ES.UTF-8','en_US.UTF-8','pt_BR.UTF-8','fr_FR.UTF-8','de_DE.UTF-8','it_IT.UTF-8'}
HOST_RE = re.compile(r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$')
USER_RE = re.compile(r'^[a-z_][a-z0-9_-]{0,30}$')
BIOS_GUID = '21686148-6449-6E6F-744E-656564454649'
ESP_GUID = 'C12A7328-F81F-11D2-BA4B-00A0C93EC93B'
LINUX_GUID = '0FC63DAF-8483-4772-8E79-3D69D8477DE4'
MOUNTS = []


class InstallError(RuntimeError):
    pass


def send(kind, **kw):
    obj = {'type': kind}
    obj.update(kw)
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def progress(value, message):
    send('progress', value=max(0.0, min(1.0, value)), message=message)


def log(message):
    send('log', message=str(message))


def run(cmd, *, input_text=None, check=True, env=None, capture=False):
    safe = ' '.join(map(str, cmd))
    log('$ ' + safe)
    p = subprocess.Popen(
        [str(x) for x in cmd],
        stdin=subprocess.PIPE if input_text is not None else subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        env=env,
    )
    out = []
    if input_text is not None:
        p.stdin.write(input_text)
        p.stdin.close()
    assert p.stdout is not None
    for line in p.stdout:
        line = line.rstrip()
        if line:
            out.append(line)
            log(line)
            m = re.search(r'\((\d+)/(\d+)\) Installing ', line)
            if m:
                cur, total = map(int, m.groups())
                if total:
                    progress(0.24 + 0.42 * cur / total, f'Instalando paquetes ({cur}/{total})')
    rc = p.wait()
    if check and rc != 0:
        raise InstallError(f'El comando falló ({rc}): {safe}')
    return '\n'.join(out) if capture else rc


def output(cmd):
    return subprocess.check_output([str(x) for x in cmd], text=True, stderr=subprocess.STDOUT).strip()


def lsblk_tree(disk=None):
    cols = 'PATH,NAME,PKNAME,TYPE,SIZE,MODEL,RO,RM,TRAN,FSTYPE,LABEL,UUID,PARTTYPE,MOUNTPOINTS'
    cmd = ['lsblk', '-J', '-b', '-o', cols]
    if disk:
        cmd.append(disk)
    return json.loads(output(cmd)).get('blockdevices', [])


def flatten(nodes):
    for node in nodes:
        yield node
        yield from flatten(node.get('children') or [])


def mounted(node):
    mps = node.get('mountpoints') or []
    if any(x for x in mps if x):
        return True
    return any(mounted(c) for c in node.get('children') or [])


def node_by_path(path):
    for node in flatten(lsblk_tree()):
        if node.get('path') == path:
            return node
    return None


def parent_disk(path):
    node = node_by_path(path)
    if not node:
        raise InstallError(f'No se encontró el dispositivo {path}.')
    if node.get('type') == 'disk':
        return path
    pk = node.get('pkname')
    if not pk:
        try:
            pk = output(['lsblk', '-no', 'PKNAME', path]).splitlines()[0].strip()
        except Exception:
            pk = ''
    if not pk:
        raise InstallError(f'No se pudo determinar el disco padre de {path}.')
    return '/dev/' + pk


def safe_disks():
    result = []
    for d in lsblk_tree():
        if d.get('type') != 'disk' or int(d.get('ro') or 0):
            continue
        if int(d.get('size') or 0) < MIN_DISK:
            continue
        if mounted(d):
            continue
        result.append(d)
    return result


def parse_bytes(value):
    value = value.strip()
    if value.endswith('B'):
        value = value[:-1]
    return int(float(value or 0))


def free_regions(disk):
    try:
        text = output(['parted', '-m', '-s', disk, 'unit', 'B', 'print', 'free'])
    except Exception:
        return []
    regions = []
    for line in text.splitlines():
        line = line.strip().rstrip(';')
        if not line or ':' not in line:
            continue
        fields = line.split(':')
        if 'free' not in fields[-1].lower() or len(fields) < 4:
            continue
        try:
            start, end, size = map(parse_bytes, fields[1:4])
        except Exception:
            continue
        if size > 0:
            regions.append({'start': start, 'end': end, 'size': size})
    return regions


def is_efi_partition(node):
    pt = (node.get('parttype') or '').upper()
    fs = (node.get('fstype') or '').lower()
    return node.get('type') == 'part' and (pt == ESP_GUID or fs in ('vfat', 'fat', 'fat32'))


def check_windows_efi(path, node=None):
    node = node or node_by_path(path)
    if not node or not is_efi_partition(node):
        return False
    mps = [m for m in (node.get('mountpoints') or []) if m]
    mounted_here = False
    temp = None
    try:
        if mps:
            root = Path(mps[0])
        else:
            temp = tempfile.mkdtemp(prefix='dexos-efi-probe-')
            p = subprocess.run(['mount', '-o', 'ro', path, temp], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if p.returncode != 0:
                return False
            mounted_here = True
            root = Path(temp)
        return (root / 'EFI/Microsoft/Boot/bootmgfw.efi').is_file()
    finally:
        if mounted_here and temp:
            subprocess.run(['umount', temp], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            shutil.rmtree(temp, ignore_errors=True)


def os_prober_results():
    if not shutil.which('os-prober'):
        return []
    try:
        p = subprocess.run(['os-prober'], text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=30)
    except Exception:
        return []
    out = []
    for line in p.stdout.splitlines():
        parts = line.split(':')
        if len(parts) >= 2:
            out.append({'device': parts[0], 'name': parts[1], 'raw': line})
    return out


def probe_system():
    probed_os = os_prober_results()
    os_by_disk = {}
    for item in probed_os:
        try:
            disk = parent_disk(item['device'])
        except Exception:
            continue
        os_by_disk.setdefault(disk, []).append(item)

    disks = []
    partitions = []
    for d in lsblk_tree():
        if d.get('type') != 'disk' or int(d.get('ro') or 0) or int(d.get('size') or 0) < MIN_DISK:
            continue
        dpath = d['path']
        parts = []
        windows = any('windows' in x.get('name', '').lower() for x in os_by_disk.get(dpath, []))
        efi_parts = []
        for n in d.get('children') or []:
            if n.get('type') != 'part':
                continue
            entry = {
                'path': n.get('path'), 'size': int(n.get('size') or 0), 'fstype': n.get('fstype') or '',
                'label': n.get('label') or '', 'uuid': n.get('uuid') or '', 'parttype': n.get('parttype') or '',
                'mounted': bool(any(x for x in (n.get('mountpoints') or []) if x)),
                'efi': is_efi_partition(n), 'windows_efi': False,
            }
            if entry['efi']:
                entry['windows_efi'] = check_windows_efi(entry['path'], n)
                windows = windows or entry['windows_efi']
                efi_parts.append(entry['path'])
            parts.append(entry)
            partitions.append(dict(entry, disk=dpath))
        regions = free_regions(dpath)
        disks.append({
            'path': dpath,
            'size': int(d.get('size') or 0),
            'model': (d.get('model') or 'Disco').strip(),
            'tran': (d.get('tran') or '').upper(),
            'mounted': mounted(d),
            'erase_safe': not mounted(d),
            'windows': windows,
            'oses': os_by_disk.get(dpath, []),
            'efi_partitions': efi_parts,
            'free_regions': regions,
            'partitions': parts,
        })
    return {'disks': disks, 'partitions': partitions, 'oses': probed_os}


def validate_common(cfg):
    cfg.setdefault('locale', 'es_ES.UTF-8')
    for k in ['hostname', 'username', 'password', 'root_password', 'timezone', 'mode', 'locale']:
        if k not in cfg:
            raise InstallError(f'Falta el dato requerido: {k}')
    if not HOST_RE.fullmatch(cfg['hostname']):
        raise InstallError('Hostname no válido.')
    if not USER_RE.fullmatch(cfg['username']) or cfg['username'] == 'root':
        raise InstallError('Nombre de usuario no válido.')
    if len(cfg['password']) < 8:
        raise InstallError('La contraseña del usuario debe tener al menos 8 caracteres.')
    if len(cfg['root_password']) < 8:
        raise InstallError('La contraseña root debe tener al menos 8 caracteres.')
    if cfg['locale'] not in SUPPORTED_LOCALES:
        raise InstallError('Idioma/locale no soportado.')
    tz = cfg['timezone']
    if tz.startswith('/') or '..' in tz.split('/') or not (Path('/usr/share/zoneinfo') / tz).is_file():
        raise InstallError('Zona horaria no válida.')
    return cfg


def validate(cfg):
    cfg = validate_common(cfg)
    mode = cfg['mode']
    if mode == 'erase':
        disk = cfg.get('disk')
        allowed = {d['path'] for d in safe_disks()}
        if disk not in allowed:
            raise InstallError('El disco seleccionado ya no es un destino seguro o tiene particiones montadas.')
        if cfg.get('confirm') != f'BORRAR {disk}':
            raise InstallError('La confirmación de borrado no coincide con el disco seleccionado.')
    elif mode == 'alongside':
        disk = cfg.get('disk')
        efi = cfg.get('efi_partition')
        if not disk or not Path(disk).exists() or node_by_path(disk) is None:
            raise InstallError('El disco para instalación junto a Windows ya no existe.')
        if cfg.get('confirm') != f'INSTALAR JUNTO A {disk}':
            raise InstallError('La confirmación de instalación junto a Windows no coincide.')
        enode = node_by_path(efi)
        if not enode or not is_efi_partition(enode) or parent_disk(efi) != disk:
            raise InstallError('La particición EFI seleccionada no es válida para ese disco.')
        if bool(any(x for x in (enode.get('mountpoints') or []) if x)):
            raise InstallError('La particición EFI está montada. Desmóntala antes de instalar.')
        requested = (int(cfg.get('free_start') or 0), int(cfg.get('free_end') or 0))
        found = None
        for r in free_regions(disk):
            if abs(r['start'] - requested[0]) <= 2 * 1024**2 and abs(r['end'] - requested[1]) <= 2 * 1024**2:
                found = r
                break
        if not found or found['size'] < MIN_ALONGSIDE:
            raise InstallError('El espacio libre seleccionado ya no está disponible o es demasiado pequeño.')
        cfg['_free_region'] = found
    elif mode == 'manual':
        root = cfg.get('root_partition')
        efi = cfg.get('efi_partition')
        rnode, enode = node_by_path(root), node_by_path(efi)
        if not rnode or rnode.get('type') != 'part' or int(rnode.get('size') or 0) < MIN_ROOT:
            raise InstallError('La partición raíz seleccionada no es válida o es demasiado pequeña.')
        if bool(any(x for x in (rnode.get('mountpoints') or []) if x)):
            raise InstallError('La partición raíz está montada. Desmóntala antes de instalar.')
        if not enode or not is_efi_partition(enode):
            raise InstallError('La partición EFI seleccionada no es válida.')
        if bool(any(x for x in (enode.get('mountpoints') or []) if x)):
            raise InstallError('La partición EFI está montada. Desmóntala antes de instalar.')
        if root == efi:
            raise InstallError('La partición raíz y la EFI no pueden ser la misma.')
        if cfg.get('confirm') != f'FORMATEAR {root}':
            raise InstallError('La confirmación de formateo no coincide con la partición raíz.')
    else:
        raise InstallError('Modo de instalación no válido.')
    return cfg


def partitions(disk):
    suffix = 'p' if disk[-1].isdigit() else ''
    return f'{disk}{suffix}1', f'{disk}{suffix}2', f'{disk}{suffix}3'


def wait_block(path, timeout=20):
    for _ in range(timeout * 10):
        if Path(path).exists():
            return
        time.sleep(0.1)
    raise InstallError(f'No apareció el dispositivo {path}')


def mount(src, dst, *, rbind=False):
    Path(dst).mkdir(parents=True, exist_ok=True)
    if rbind:
        run(['mount', '--rbind', src, dst])
        run(['mount', '--make-rslave', dst])
    else:
        run(['mount', src, dst])
    MOUNTS.append(str(dst))


def cleanup():
    for m in reversed(MOUNTS):
        subprocess.run(['umount', '-R', m], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    MOUNTS.clear()


def find_repo():
    candidates = list(Path('/media').glob('*/apks/x86_64/APKINDEX.tar.gz'))
    candidates += list(Path('/media').glob('*/*/apks/x86_64/APKINDEX.tar.gz'))
    for idx in candidates:
        return str(idx.parent.parent)
    raise InstallError('No se encontró el repositorio APK de la ISO DexOS.')


def package_list():
    p = Path('/usr/share/dexos/installer-packages.txt')
    if not p.is_file():
        raise InstallError('Falta la lista de paquetes del instalador.')
    pkgs = []
    for line in p.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith('#'):
            pkgs.extend(line.split())
    if not pkgs:
        raise InstallError('La lista de paquetes está vacía.')
    return pkgs


def write(path, text, mode=0o644):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        path.unlink()
    path.write_text(text)
    os.chmod(path, mode)


def copy_if(src, dst, mode=None):
    src, dst = Path(src), Path(dst)
    if not src.exists():
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    if src.is_dir():
        shutil.copytree(src, dst, dirs_exist_ok=True)
    else:
        shutil.copy2(src, dst)
        if mode is not None:
            os.chmod(dst, mode)


def chroot(cmd, *, input_text=None, check=True):
    return run(['chroot', str(TARGET)] + list(cmd), input_text=input_text, check=check)


def configure_branding():
    progress(0.70, 'Aplicando identidad DexOS')
    copy_if('/usr/share/dexos/boot.jpg', TARGET / 'usr/share/dexos/boot.jpg')
    copy_if('/usr/share/dexos/boot.ppm', TARGET / 'usr/share/dexos/boot.ppm')
    copy_if('/usr/share/dexos/dexos-wallpaper.png', TARGET / 'usr/share/dexos/dexos-wallpaper.png')
    copy_if('/usr/share/backgrounds/xfce/DexOS.png', TARGET / 'usr/share/backgrounds/xfce/DexOS.png')
    copy_if('/usr/share/xfce4/backdrops/DexOS.png', TARGET / 'usr/share/xfce4/backdrops/DexOS.png')
    copy_if('/usr/local/bin/dexos-session', TARGET / 'usr/local/bin/dexos-session', 0o755)
    copy_if('/usr/local/bin/dexos-session-splash', TARGET / 'usr/local/bin/dexos-session-splash', 0o755)
    copy_if('/usr/share/dexos/installed/dexos-language', TARGET / 'usr/local/bin/dexos-language', 0o755)
    copy_if('/usr/share/dexos/installed/dexos-splash-keys', TARGET / 'usr/local/sbin/dexos-splash-keys', 0o755)
    copy_if('/usr/share/dexos/installed/dexos-bootsplash', TARGET / 'etc/init.d/dexos-bootsplash', 0o755)
    copy_if('/usr/share/dexos/installed/dexos-bootsplash-finish', TARGET / 'etc/init.d/dexos-bootsplash-finish', 0o755)
    copy_if('/usr/share/dexos/installed/dexos-wifi-init', TARGET / 'etc/init.d/dexos-wifi-init', 0o755)
    copy_if('/usr/share/dexos/installed/dexos-wifi-refresh', TARGET / 'etc/init.d/dexos-wifi-refresh', 0o755)
    copy_if('/usr/share/dexos/installed/dexos-audio-init', TARGET / 'usr/local/bin/dexos-audio-init', 0o755)
    copy_if('/usr/share/dexos/installed/dexos-video-init', TARGET / 'usr/local/bin/dexos-video-init', 0o755)
    copy_if('/usr/share/dexos/installed/dexos-apk-refresh', TARGET / 'etc/init.d/dexos-apk-refresh', 0o755)
    copy_if('/usr/share/dexos/installed/patch-initramfs-init.py', TARGET / 'usr/share/dexos/patch-initramfs-init.py', 0o755)
    copy_if('/usr/local/sbin/dexos-xsetup', TARGET / 'usr/local/sbin/dexos-xsetup', 0o755)
    copy_if('/usr/local/bin/dexos-apply-theme', TARGET / 'usr/local/bin/dexos-apply-theme', 0o755)
    copy_if('/etc/xdg/autostart/dexos-branding.desktop', TARGET / 'etc/xdg/autostart/dexos-branding.desktop')
    copy_if('/etc/xdg/autostart/dexos-audio.desktop', TARGET / 'etc/xdg/autostart/dexos-audio.desktop')
    copy_if('/etc/xdg/autostart/dexos-video.desktop', TARGET / 'etc/xdg/autostart/dexos-video.desktop')
    copy_if('/etc/X11/xorg.conf.d/40-dexos-libinput.conf', TARGET / 'etc/X11/xorg.conf.d/40-dexos-libinput.conf')
    copy_if('/etc/xdg/xfce4/xfconf/xfce-perchannel-xml', TARGET / 'etc/xdg/xfce4/xfconf/xfce-perchannel-xml')
    copy_if('/etc/skel/.config/gtk-3.0', TARGET / 'etc/skel/.config/gtk-3.0')
    copy_if('/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml', TARGET / 'etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml')
    write(TARGET / 'etc/os-release', '''NAME="DexOS"\nPRETTY_NAME="DexOS"\nID=dexos\nID_LIKE=alpine\nVERSION_ID="0.3"\nVERSION="0.3"\n''')
    write(TARGET / 'etc/issue', 'DexOS \\n \\l\n')
    write(TARGET / 'etc/lightdm/lightdm.conf.d/10-dexos.conf', '''[LightDM]\nlogind-check-graphical=false\n\n[Seat:*]\ndisplay-setup-script=/usr/local/sbin/dexos-xsetup\ngreeter-session=lightdm-gtk-greeter\nuser-session=dexos\n''')
    write(TARGET / 'etc/lightdm/lightdm-gtk-greeter.conf', '''[greeter]\nbackground=/usr/share/dexos/dexos-wallpaper.png\ntheme-name=adw-gtk3-dark\nicon-theme-name=Adwaita-Xfce\ncursor-theme-name=Breeze\ncursor-theme-size=24\nfont-name=DejaVu Sans 11\nclock-format=%A %d de %B  %H:%M\nindicators=~host;~spacer;~clock;~spacer;~session;~a11y;~power\nuser-background=false\n''')
    write(TARGET / 'etc/doas.d/20-dexos.conf', 'permit :wheel\n', 0o600)
    write(TARGET / 'etc/sudoers.d/10-wheel', '%wheel ALL=(ALL:ALL) ALL\n', 0o440)
    write(TARGET / 'etc/conf.d/networkmanager', 'rc_need="dexos-wifi-init"\n')
    write(TARGET / 'usr/share/xsessions/dexos.desktop', '[Desktop Entry]\nName=DexOS\nComment=DexOS XFCE Session\nExec=/usr/local/bin/dexos-session\nTryExec=/usr/local/bin/dexos-session\nType=Application\nDesktopNames=XFCE\n')


def patch_installed_initramfs(text):
    if '/usr/share/dexos/boot.ppm' in text:
        return text
    needle = 'for fbsplash in /media/*/fbsplash.ppm; do\n\t\t[ -e "$fbsplash" ] && break\n\tdone'
    if needle not in text:
        raise InstallError('La versión de mkinitfs no contiene el punto de integración de bootsplash esperado.')
    return text.replace(needle, needle + '\n\t[ -e "$fbsplash" ] || fbsplash=/usr/share/dexos/boot.ppm', 1)


def configure_system(cfg, efi_partition, root_partition):
    progress(0.74, 'Configurando sistema')
    write(TARGET / 'etc/hostname', cfg['hostname'] + '\n')
    write(TARGET / 'etc/hosts', f'''127.0.0.1\tlocalhost localhost.localdomain\n127.0.1.1\t{cfg['hostname']} {cfg['hostname']}.localdomain\n::1\tlocalhost localhost.localdomain\n''')
    tz_src = TARGET / 'usr/share/zoneinfo' / cfg['timezone']
    if not tz_src.is_file():
        raise InstallError('tzdata no contiene la zona horaria seleccionada en el sistema destino.')
    localtime = TARGET / 'etc/localtime'
    if localtime.exists() or localtime.is_symlink():
        localtime.unlink()
    localtime.symlink_to('/usr/share/zoneinfo/' + cfg['timezone'])
    write(TARGET / 'etc/timezone', cfg['timezone'] + '\n')
    write(TARGET / 'etc/dexos-locale', cfg['locale'] + '\n')
    language = {
        'es_ES.UTF-8':'es_ES:es', 'en_US.UTF-8':'en_US:en', 'pt_BR.UTF-8':'pt_BR:pt',
        'fr_FR.UTF-8':'fr_FR:fr', 'de_DE.UTF-8':'de_DE:de', 'it_IT.UTF-8':'it_IT:it'
    }[cfg['locale']]
    write(TARGET / 'etc/profile.d/00-dexos-locale.sh', f'export LANG="{cfg["locale"]}"\nexport LC_MESSAGES="{cfg["locale"]}"\nexport LANGUAGE="{language}"\n', 0o644)
    write(TARGET / 'etc/locale.conf', f'LANG={cfg["locale"]}\n')

    configure_branding()

    chroot(['/usr/sbin/adduser', '-D', '-s', '/bin/bash', cfg['username']])
    for group in ['wheel', 'audio', 'video', 'input', 'netdev', 'plugdev']:
        chroot(['/usr/sbin/addgroup', cfg['username'], group], check=False)
    chroot(['/usr/sbin/chpasswd'], input_text=f"{cfg['username']}:{cfg['password']}\nroot:{cfg['root_password']}\n")
    chroot(['/usr/sbin/usermod', '-s', '/bin/bash', 'root'], check=False)
    write(TARGET / 'etc/default/useradd', 'SHELL=/bin/bash\n')

    home = TARGET / 'home' / cfg['username']
    copy_if(TARGET / 'etc/skel/.config', home / '.config')
    copy_if(TARGET / 'etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml', home / '.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml')
    chroot(['/bin/chown', '-R', f"{cfg['username']}:{cfg['username']}", f"/home/{cfg['username']}"])

    root_uuid = output(['blkid', '-s', 'UUID', '-o', 'value', root_partition])
    efi_uuid = output(['blkid', '-s', 'UUID', '-o', 'value', efi_partition])
    write(TARGET / 'etc/fstab', f'''UUID={root_uuid}\t/\text4\tdefaults,noatime\t0 1\nUUID={efi_uuid}\t/boot/efi\tvfat\tumask=0077\t0 2\ntmpfs\t/tmp\ttmpfs\tnosuid,nodev\t0 0\n''')
    write(TARGET / 'etc/apk/repositories', '''https://dl-cdn.alpinelinux.org/alpine/edge/main\nhttps://dl-cdn.alpinelinux.org/alpine/edge/community\n@testing https://dl-cdn.alpinelinux.org/alpine/edge/testing\n''')
    write(TARGET / 'etc/mkinitfs/features.d/dexosroot.modules', '''kernel/drivers/virtio/virtio.ko*\nkernel/drivers/virtio/virtio_ring.ko*\nkernel/drivers/virtio/virtio_pci.ko*\nkernel/drivers/block/virtio_blk.ko*\nkernel/fs/ext4/ext4.ko*\n''')
    write(TARGET / 'etc/mkinitfs/features.d/dexosroot.files', '/usr/share/dexos/boot.ppm\n/sbin/fbsplash\n/usr/bin/setsid\n/usr/bin/chvt\n/bin/stty\n')
    init_script = TARGET / 'usr/share/mkinitfs/initramfs-init'
    if not init_script.is_file():
        raise InstallError('Falta initramfs-init en el sistema destino.')
    patcher = TARGET / 'usr/share/dexos/patch-initramfs-init.py'
    if not patcher.is_file():
        raise InstallError('Falta el parche DexOS de bootsplash en el sistema destino.')
    run(['/usr/bin/python3', str(patcher), str(init_script)])
    write(TARGET / 'etc/mkinitfs/mkinitfs.conf', 'features="ata base ide scsi usb virtio ext4 nvme kms dexosroot"\n')

    for service, level in [
        ('devfs','sysinit'), ('dmesg','sysinit'), ('udev','sysinit'), ('udev-trigger','sysinit'), ('udev-settle','sysinit'),
        ('udev-postmount','default'), ('swclock','boot'), ('modules','boot'), ('sysctl','boot'), ('hostname','boot'),
        ('bootmisc','boot'), ('syslog','boot'), ('dexos-bootsplash','boot'), ('dexos-wifi-init','boot'), ('dbus','default'), ('elogind','default'), ('networkmanager','default'), ('dexos-wifi-refresh','default'), ('chronyd','default'),
        ('bluetooth','default'), ('lightdm','default'), ('dexos-bootsplash-finish','default'), ('mount-ro','shutdown'), ('killprocs','shutdown'), ('savecache','shutdown')]:
        chroot(['/sbin/rc-update', 'add', service, level], check=False)
    chroot(['/sbin/rc-update', 'del', 'mdev', 'sysinit'], check=False)
    chroot(['/sbin/rc-update', 'del', 'hwdrivers', 'sysinit'], check=False)
    chroot(['/sbin/rc-update', 'del', 'hwclock', 'boot'], check=False)
    for d in (TARGET / 'etc/runlevels').glob('*/modloop'):
        try:
            d.unlink()
        except FileNotFoundError:
            pass

    versions = sorted((TARGET / 'lib/modules').iterdir(), key=lambda x: x.name)
    if not versions:
        raise InstallError('No se encontró el kernel instalado.')
    kver = versions[-1].name
    module_dir = TARGET / 'lib/modules' / kver
    required_patterns = [
        'kernel/drivers/virtio/virtio.ko*',
        'kernel/drivers/virtio/virtio_ring.ko*',
        'kernel/drivers/virtio/virtio_pci.ko*',
        'kernel/drivers/block/virtio_blk.ko*',
        'kernel/fs/ext4/ext4.ko*',
    ]
    missing = [pattern for pattern in required_patterns if not list(module_dir.glob(pattern))]
    if missing:
        raise InstallError('Faltan módulos críticos del kernel: ' + ', '.join(missing))
    chroot(['/sbin/mkinitfs', '-c', '/etc/mkinitfs/mkinitfs.conf', kver])
    initramfs = TARGET / 'boot/initramfs-lts'
    if not initramfs.is_file() or initramfs.stat().st_size < 1024 * 1024:
        raise InstallError('mkinitfs no generó un initramfs válido.')


def rewrite_grub_root(text, root_uuid):
    fixed = []
    for line in text.splitlines():
        if re.match(r'^\s*linux(?:efi)?\s', line):
            line = re.sub(r'\s+root=\S+', '', line)
            line = re.sub(r'\s+rootfstype=\S+', '', line)
            line = re.sub(r'\s+modules=\S+', '', line)
            line += f' root=UUID={root_uuid} quiet splash vt.global_cursor_default=0 rootfstype=ext4 modules=virtio,virtio_ring,virtio_pci,virtio_blk,ext4'
        fixed.append(line)
    return '\n'.join(fixed) + '\n'


def install_argon_theme():
    src = Path('/usr/share/dexos/argon-grub-theme')
    if not src.is_dir() or not (src / 'theme.txt').is_file():
        raise InstallError('Falta el tema Argon precompilado en el medio Live.')
    dst = TARGET / 'boot/grub/themes/argon'
    copy_if(src, dst)
    if not (dst / 'theme.txt').is_file():
        raise InstallError('No se pudo instalar el tema Argon de GRUB.')


def install_bootloader(boot_disk, root_uuid, *, preserve_efi=False):
    progress(0.86, 'Instalando GRUB y detectando otros sistemas')
    efi_boot = Path('/sys/firmware/efi').is_dir()

    if not preserve_efi or not efi_boot:
        rc = run(['grub-install', '--boot-directory=' + str(TARGET / 'boot'), '--target=i386-pc', boot_disk], check=False)
        if rc != 0 and not efi_boot:
            raise InstallError('No se pudo instalar GRUB BIOS en el disco seleccionado.')

    uefi_cmd = ['grub-install', '--target=x86_64-efi', '--efi-directory=' + str(TARGET / 'boot/efi'),
                '--bootloader-id=DexOS', '--boot-directory=' + str(TARGET / 'boot')]
    if efi_boot:
        rc = run(uefi_cmd, check=False)
        if rc != 0:
            log('No se pudo registrar DexOS en NVRAM; reintentando sin modificar NVRAM.')
            run(uefi_cmd + ['--no-nvram'])
    else:
        run(uefi_cmd + ['--no-nvram'])

    efi = TARGET / 'boot/efi/EFI/DexOS/grubx64.efi'
    if not efi.is_file():
        raise InstallError('GRUB UEFI no generó grubx64.efi.')
    if not preserve_efi:
        fallback = TARGET / 'boot/efi/EFI/BOOT/BOOTX64.EFI'
        fallback.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(efi, fallback)

    install_argon_theme()
    write(TARGET / 'etc/default/grub', '''GRUB_TIMEOUT=8\nGRUB_DISABLE_SUBMENU=y\nGRUB_DISABLE_RECOVERY=true\nGRUB_DISTRIBUTOR="DexOS"\nGRUB_DISABLE_LINUX_UUID=false\nGRUB_DISABLE_OS_PROBER=false\nGRUB_THEME="/boot/grub/themes/argon/theme.txt"\nGRUB_GFXMODE="1920x1080,auto"\nGRUB_GFXPAYLOAD_LINUX=keep\nGRUB_CMDLINE_LINUX_DEFAULT="quiet splash vt.global_cursor_default=0 rootfstype=ext4 modules=virtio,virtio_ring,virtio_pci,virtio_blk,ext4"\n''')
    # os-prober is intentionally enabled only during explicit OS installation.
    chroot(['/usr/bin/os-prober'], check=False)
    chroot(['/usr/sbin/grub-mkconfig', '-o', '/boot/grub/grub.cfg'])
    grub_cfg = TARGET / 'boot/grub/grub.cfg'
    text = grub_cfg.read_text()
    write(grub_cfg, rewrite_grub_root(text, root_uuid), 0o644)
    verify = grub_cfg.read_text()
    if f'root=UUID={root_uuid}' not in verify:
        raise InstallError('GRUB no quedó configurado con el UUID de la raíz.')
    if re.search(r'\sroot=/dev/', verify):
        raise InstallError('GRUB todavía contiene una ruta /dev/ inestable para la raíz.')


def prepare_erase(cfg):
    disk = cfg['disk']
    p1, p2, p3 = partitions(disk)
    progress(0.08, 'Creando tabla GPT segura')
    run(['wipefs', '-a', disk])
    layout = f'''label: gpt\nsize=2M, type={BIOS_GUID}\nsize=512M, type={ESP_GUID}\ntype={LINUX_GUID}\n'''
    run(['sfdisk', '--wipe', 'always', '--wipe-partitions', 'always', disk], input_text=layout)
    run(['partprobe', disk])
    run(['udevadm', 'settle', '--timeout=15'])
    for p in (p1, p2, p3):
        wait_block(p)
    progress(0.14, 'Formateando particiones')
    run(['mkfs.vfat', '-F', '32', '-n', 'DEXOS_EFI', p2])
    run(['mkfs.ext4', '-F', '-L', 'DexOS', p3])
    return {'root': p3, 'efi': p2, 'boot_disk': disk, 'preserve_efi': False}


def prepare_alongside(cfg):
    disk = cfg['disk']
    region = cfg['_free_region']
    margin = 2 * 1024**2
    start = region['start'] + margin
    end = region['end'] - margin
    if end - start < MIN_ROOT:
        raise InstallError('El espacio libre útil es menor de 10 GiB.')
    before = {n.get('path') for n in flatten(lsblk_tree(disk)) if n.get('type') == 'part'}
    progress(0.10, 'Creando partición DexOS en el espacio libre')
    run(['parted', '-s', disk, 'unit', 'B', 'mkpart', 'DexOS', 'ext4', f'{start}B', f'{end}B'])
    run(['partprobe', disk])
    run(['udevadm', 'settle', '--timeout=20'])
    after_nodes = [n for n in flatten(lsblk_tree(disk)) if n.get('type') == 'part']
    new_parts = [n.get('path') for n in after_nodes if n.get('path') not in before]
    if len(new_parts) != 1:
        raise InstallError('No se pudo identificar de forma segura la nueva partición DexOS.')
    root = new_parts[0]
    wait_block(root)
    progress(0.14, 'Formateando la nueva partición DexOS')
    run(['mkfs.ext4', '-F', '-L', 'DexOS', root])
    return {'root': root, 'efi': cfg['efi_partition'], 'boot_disk': parent_disk(cfg['efi_partition']), 'preserve_efi': True}


def prepare_manual(cfg):
    root = cfg['root_partition']
    efi = cfg['efi_partition']
    progress(0.12, f'Formateando {root} como ext4')
    run(['mkfs.ext4', '-F', '-L', 'DexOS', root])
    return {'root': root, 'efi': efi, 'boot_disk': parent_disk(efi), 'preserve_efi': True}


def install(cfg):
    cfg = validate(cfg)
    repo = find_repo()
    pkgs = package_list()
    progress(0.03, 'Validando particiones y medio Live')
    log(f"Modo: {cfg['mode']}")
    log(f'Repositorio offline: {repo}')
    log(f'Paquetes base: {len(pkgs)}')

    try:
        if cfg['mode'] == 'erase':
            layout = prepare_erase(cfg)
        elif cfg['mode'] == 'alongside':
            layout = prepare_alongside(cfg)
        else:
            layout = prepare_manual(cfg)

        root_partition = layout['root']
        efi_partition = layout['efi']
        progress(0.19, 'Montando sistema destino')
        TARGET.mkdir(parents=True, exist_ok=True)
        mount(root_partition, TARGET)
        mount(efi_partition, TARGET / 'boot/efi')
        for src in ['/proc', '/dev', '/sys', '/run']:
            mount(src, TARGET / src.lstrip('/'), rbind=True)

        (TARGET / 'etc/apk/keys').mkdir(parents=True, exist_ok=True)
        for key in Path('/etc/apk/keys').glob('*'):
            if key.is_file():
                shutil.copy2(key, TARGET / 'etc/apk/keys' / key.name)

        progress(0.24, 'Instalando DexOS desde la ISO')
        run(['apk', 'add', '--root', str(TARGET), '--initdb', '--arch', 'x86_64', '--keys-dir', '/etc/apk/keys',
             '--no-network', '--repository', repo] + pkgs)

        configure_system(cfg, efi_partition, root_partition)
        root_uuid = output(['blkid', '-s', 'UUID', '-o', 'value', root_partition])
        install_bootloader(layout['boot_disk'], root_uuid, preserve_efi=layout['preserve_efi'])
        progress(0.96, 'Sincronizando datos')
        run(['sync'])
        cleanup()
        progress(1.0, 'DexOS instalado correctamente')
        send('done', message='Instalación completada. Reinicia y retira el medio Live. GRUB mostrará los sistemas detectados.')
    except Exception:
        cleanup()
        raise


def main():
    if os.geteuid() != 0:
        raise InstallError('El backend debe ejecutarse como root mediante doas.')
    if len(sys.argv) > 1 and sys.argv[1] == '--probe':
        send('probe', data=probe_system())
        return
    raw = sys.stdin.readline()
    if not raw:
        raise InstallError('No se recibió configuración de instalación.')
    cfg = json.loads(raw)
    install(cfg)


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        send('error', message=str(e))
        sys.exit(1)
