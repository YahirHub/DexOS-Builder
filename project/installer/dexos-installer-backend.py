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
MSR_GUID = 'E3C9E316-0B5C-4DB8-817D-F92DF00215AE'
WINRE_GUID = 'DE94BBA4-06D1-4D40-A16A-BFD50179D6AC'
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
    cols = 'PATH,NAME,PKNAME,TYPE,SIZE,MODEL,RO,RM,TRAN,FSTYPE,LABEL,UUID,PARTTYPE,PTTYPE,MOUNTPOINTS'
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


def refresh_partition_nodes(disk=None):
    if disk:
        subprocess.run(['partprobe', disk], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(['partx', '-u', disk], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['udevadm', 'settle', '--timeout=10'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def disk_pttype(disk):
    node = node_by_path(disk)
    value = (node or {}).get('pttype') or ''
    if not value:
        try:
            value = output(['blkid', '-p', '-s', 'PTTYPE', '-o', 'value', disk])
        except Exception:
            value = ''
    return value.strip().lower()


def disk_supports_bios(disk):
    pttype = disk_pttype(disk)
    if pttype in ('dos', 'msdos'):
        return True
    if pttype != 'gpt':
        return False
    for node in flatten(lsblk_tree(disk)):
        if (node.get('parttype') or '').upper() == BIOS_GUID:
            return True
    return False


def free_regions(disk):
    # Prefer sfdisk: it reads gaps directly from the partition table, including
    # unallocated space left after shrinking a Windows/Linux partition.
    try:
        sector_size = int(output(['blockdev', '--getss', disk]) or '512')
    except Exception:
        sector_size = 512
    try:
        text = output(['sfdisk', '--list-free', disk])
        regions = []
        for raw in text.splitlines():
            fields = raw.split()
            if len(fields) < 3 or not all(x.isdigit() for x in fields[:3]):
                continue
            start_sector, sectors = int(fields[0]), int(fields[2])
            size = sectors * sector_size
            if size > 0:
                regions.append({
                    'start_sector': start_sector,
                    'sectors': sectors,
                    'start': start_sector * sector_size,
                    'end': (start_sector + sectors) * sector_size - 1,
                    'size': size,
                })
        if regions:
            return regions
    except Exception:
        pass

    # Compatibility fallback for old util-linux builds.
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


def root_partition_reason(path, disk=None):
    node = node_by_path(path)
    if not node or node.get('type') != 'part':
        return 'no-es-particion'
    if int(node.get('ro') or 0):
        return 'solo-lectura'
    try:
        parent = parent_disk(path)
    except Exception:
        return 'sin-disco-padre'
    if disk and parent != disk:
        return 'otro-disco'
    pt = (node.get('parttype') or '').upper()
    if pt == ESP_GUID or is_efi_partition(node):
        return 'particion-efi'
    if pt == BIOS_GUID:
        return 'bios-boot'
    if pt in (MSR_GUID, WINRE_GUID):
        return 'reservada-windows'
    if mounted(node):
        return 'montada'
    if int(node.get('size') or 0) < MIN_ROOT:
        return 'demasiado-pequena'
    return 'ok'


def root_partition_eligible(path, disk=None):
    return root_partition_reason(path, disk) == 'ok'


def is_efi_partition(node):
    pt = (node.get('parttype') or '').upper()
    fs = (node.get('fstype') or '').lower()
    return node.get('type') == 'part' and (pt == ESP_GUID or fs in ('vfat', 'fat', 'fat32'))


def efi_partition_candidate(path, disk=None):
    node = node_by_path(path)
    if not node or not is_efi_partition(node) or int(node.get('ro') or 0):
        return False
    try:
        if disk and parent_disk(path) != disk:
            return False
    except Exception:
        return False
    return not mounted(node)


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
                'ro': int(n.get('ro') or 0),
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
            'bios_capable': disk_supports_bios(dpath),
            'pttype': disk_pttype(dpath),
            'oses': os_by_disk.get(dpath, []),
            'efi_partitions': efi_parts,
            'free_regions': regions,
            'partitions': parts,
            'root_candidates': [p['path'] for p in parts if root_partition_eligible(p['path'], dpath)],
        })
    return {'disks': disks, 'partitions': partitions, 'oses': probed_os,
            'boot_mode': 'uefi' if Path('/sys/firmware/efi').is_dir() else 'bios'}


def validate_common(cfg):
    cfg.setdefault('locale', 'es_ES.UTF-8')
    if 'username' in cfg and isinstance(cfg['username'], str):
        cfg['username'] = cfg['username'].strip().lower()
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
        if not disk or node_by_path(disk) is None:
            raise InstallError('El disco seleccionado para coexistencia ya no existe.')
        if cfg.get('confirm') != f'COEXISTIR {disk}':
            raise InstallError('La confirmación de coexistencia no coincide.')

        efi = cfg.get('efi_partition') or ''
        if efi and not efi_partition_candidate(efi, disk):
            raise InstallError('La partición EFI seleccionada no es válida, está montada o pertenece a otro disco.')
        if Path('/sys/firmware/efi').is_dir() and not efi:
            raise InstallError('El Live arrancó en UEFI; selecciona una partición EFI del disco para garantizar el arranque.')
        if not efi and not disk_supports_bios(disk):
            raise InstallError('No hay una ESP seleccionada ni un destino válido para GRUB BIOS.')

        root = cfg.get('root_partition') or ''
        free_start = int(cfg.get('free_start_sector') or 0)
        free_sectors = int(cfg.get('free_sectors') or 0)
        if root and (free_start or free_sectors):
            raise InstallError('No mezcles una partición raíz existente con espacio no asignado.')
        if root:
            reason = root_partition_reason(root, disk)
            if reason != 'ok':
                raise InstallError(f'La partición raíz seleccionada ya no es válida ({reason}).')
            cfg['_root_partition'] = root
        else:
            if free_start <= 0 or free_sectors <= 0:
                raise InstallError('Selecciona una partición raíz o un espacio no asignado.')
            found = None
            for r in free_regions(disk):
                if int(r.get('start_sector') or -1) == free_start and int(r.get('sectors') or -1) == free_sectors:
                    found = r
                    break
            if not found or found['size'] < MIN_ROOT:
                raise InstallError('El espacio no asignado seleccionado cambió o ya no es utilizable.')
            cfg['_free_region'] = found
    elif mode == 'manual':
        root = cfg.get('root_partition')
        disk = parent_disk(root) if root and node_by_path(root) else None
        reason = root_partition_reason(root, disk) if disk else 'no-es-particion'
        if reason != 'ok':
            raise InstallError(f'La partición raíz seleccionada no es válida ({reason}).')
        efi = cfg.get('efi_partition') or ''
        if efi and not efi_partition_candidate(efi, disk):
            raise InstallError('La partición EFI seleccionada no es válida, está montada o pertenece a otro disco.')
        if Path('/sys/firmware/efi').is_dir() and not efi:
            raise InstallError('El Live arrancó en UEFI; selecciona una partición EFI.')
        if not efi and not disk_supports_bios(disk):
            raise InstallError('El disco no tiene un destino válido para GRUB BIOS y no se seleccionó una ESP.')
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
    xfce_default = TARGET / 'usr/share/backgrounds/xfce/xfce-x.svg'
    if xfce_default.exists() or xfce_default.is_symlink():
        xfce_default.unlink()
    xfce_default.symlink_to('/usr/share/dexos/dexos-wallpaper.png')
    copy_if('/usr/share/xfce4/backdrops/DexOS.png', TARGET / 'usr/share/xfce4/backdrops/DexOS.png')
    copy_if('/usr/share/icons/DexOS-Windows', TARGET / 'usr/share/icons/DexOS-Windows')
    icon_alias = TARGET / 'usr/share/icons/Adwaita-Xfce'
    if icon_alias.exists() or icon_alias.is_symlink():
        if icon_alias.is_symlink() or icon_alias.is_file(): icon_alias.unlink()
    if not icon_alias.exists(): icon_alias.symlink_to('adwaita-xfce')
    all_apps = TARGET / 'usr/share/icons/adwaita-xfce/scalable/categories/applications.svg'
    all_apps.parent.mkdir(parents=True, exist_ok=True)
    if all_apps.exists() or all_apps.is_symlink(): all_apps.unlink()
    all_apps.symlink_to('applications-other.svg')
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
    copy_if('/usr/share/dexos/installed/dexos-prepare-desktop', TARGET / 'usr/local/bin/dexos-prepare-desktop', 0o755)
    copy_if('/usr/share/dexos/installed/dexos-boot-manager.py', TARGET / 'usr/local/bin/dexos-boot-manager', 0o755)
    copy_if('/usr/share/dexos/installed/dexos-eye-protection.py', TARGET / 'usr/local/bin/dexos-eye-protection', 0o755)
    copy_if('/usr/share/dexos/installed/dexos-power-init', TARGET / 'etc/init.d/dexos-power', 0o755)
    copy_if('/usr/share/dexos/installed/dexos-power-apply', TARGET / 'usr/local/sbin/dexos-power-apply', 0o755)
    copy_if('/usr/share/dexos/installed/dexos-backlight-state', TARGET / 'etc/init.d/dexos-backlight', 0o755)
    copy_if('/usr/share/dexos/installed/org.dexos.boot-manager.policy', TARGET / 'usr/share/polkit-1/actions/org.dexos.boot-manager.policy')
    copy_if('/usr/share/dexos/installed/boot-order', TARGET / 'usr/local/sbin/boot-order', 0o755)
    copy_if('/usr/share/dexos/installed/grub-update', TARGET / 'usr/local/sbin/grub-update', 0o755)
    update_grub = TARGET / 'usr/local/sbin/update-grub'
    if update_grub.exists() or update_grub.is_symlink():
        update_grub.unlink()
    update_grub.symlink_to('grub-update')
    copy_if('/usr/share/dexos/installed/05_dexos_theme', TARGET / 'etc/grub.d/05_dexos_theme', 0o755)
    copy_if('/usr/share/dexos/installed/09_dexos_linux', TARGET / 'etc/grub.d/09_dexos_linux', 0o755)
    copy_if('/usr/share/dexos/installed/grub-other-os', TARGET / 'etc/grub.d/31_dexos_other_os', 0o755)
    for stock in ('10_linux', '20_linux_xen'):
        path = TARGET / 'etc/grub.d' / stock
        if path.exists():
            path.chmod(path.stat().st_mode & ~0o111)
    copy_if('/usr/share/dexos/installed/dexos-apk-refresh', TARGET / 'etc/init.d/dexos-apk-refresh', 0o755)
    copy_if('/usr/share/dexos/installed/patch-initramfs-init.py', TARGET / 'usr/share/dexos/patch-initramfs-init.py', 0o755)
    copy_if('/usr/local/sbin/dexos-xsetup', TARGET / 'usr/local/sbin/dexos-xsetup', 0o755)
    copy_if('/usr/local/bin/dexos-apply-theme', TARGET / 'usr/local/bin/dexos-apply-theme', 0o755)
    copy_if('/etc/xdg/autostart/dexos-branding.desktop', TARGET / 'etc/xdg/autostart/dexos-branding.desktop')
    copy_if('/etc/xdg/autostart/dexos-audio.desktop', TARGET / 'etc/xdg/autostart/dexos-audio.desktop')
    copy_if('/etc/xdg/autostart/dexos-video.desktop', TARGET / 'etc/xdg/autostart/dexos-video.desktop')
    copy_if('/etc/xdg/autostart/dexos-eye-protection.desktop', TARGET / 'etc/xdg/autostart/dexos-eye-protection.desktop')
    copy_if('/usr/share/applications/dexos-boot-manager.desktop', TARGET / 'usr/share/applications/dexos-boot-manager.desktop')
    copy_if('/usr/share/applications/dexos-eye-protection.desktop', TARGET / 'usr/share/applications/dexos-eye-protection.desktop')
    copy_if('/etc/skel/Desktop/Orden-de-arranque.desktop', TARGET / 'etc/skel/Desktop/Orden-de-arranque.desktop', 0o755)
    copy_if('/etc/X11/xorg.conf.d/40-dexos-libinput.conf', TARGET / 'etc/X11/xorg.conf.d/40-dexos-libinput.conf')
    copy_if('/etc/redshift.conf', TARGET / 'etc/redshift.conf')
    copy_if('/etc/geoclue/conf.d/90-dexos-redshift.conf', TARGET / 'etc/geoclue/conf.d/90-dexos-redshift.conf')
    copy_if('/etc/xdg/xfce4/xfconf/xfce-perchannel-xml', TARGET / 'etc/xdg/xfce4/xfconf/xfce-perchannel-xml')
    copy_if('/etc/skel/.config/gtk-3.0', TARGET / 'etc/skel/.config/gtk-3.0')
    copy_if('/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml', TARGET / 'etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml')
    write(TARGET / 'etc/os-release', '''NAME="DexOS"\nPRETTY_NAME="DexOS"\nID=dexos\nID_LIKE=alpine\nVERSION_ID="0.3"\nVERSION="0.3"\n''')
    write(TARGET / 'etc/issue', 'DexOS \\n \\l\n')
    write(TARGET / 'etc/lightdm/lightdm.conf.d/10-dexos.conf', '''[LightDM]\nlogind-check-graphical=false\n\n[Seat:*]\ndisplay-setup-script=/usr/local/sbin/dexos-xsetup\ngreeter-session=lightdm-gtk-greeter\nuser-session=dexos\n''')
    write(TARGET / 'etc/lightdm/lightdm-gtk-greeter.conf', '''[greeter]\nbackground=/usr/share/dexos/dexos-wallpaper.png\ntheme-name=adw-gtk3-dark\nicon-theme-name=Adwaita-Xfce\ncursor-theme-name=DexOS-Windows\ncursor-theme-size=32\nfont-name=DejaVu Sans 11\nclock-format=%A %d de %B  %H:%M\nindicators=~host;~spacer;~clock;~spacer;~session;~a11y;~power\nuser-background=false\n''')
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
    copy_if(TARGET / 'etc/skel/Desktop', home / 'Desktop')
    copy_if(TARGET / 'etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml', home / '.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml')
    chroot(['/bin/chown', '-R', f"{cfg['username']}:{cfg['username']}", f"/home/{cfg['username']}"])

    root_uuid = output(['blkid', '-s', 'UUID', '-o', 'value', root_partition])
    fstab = f'UUID={root_uuid}\t/\text4\tdefaults,noatime\t0 1\n'
    if efi_partition:
        efi_uuid = output(['blkid', '-s', 'UUID', '-o', 'value', efi_partition])
        fstab += f'UUID={efi_uuid}\t/boot/efi\tvfat\tumask=0077\t0 2\n'
    fstab += 'tmpfs\t/tmp\ttmpfs\tnosuid,nodev\t0 0\n'
    write(TARGET / 'etc/fstab', fstab)
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
        ('bluetooth','default'), ('alsa','default'), ('dexos-backlight','default'), ('dexos-power','default'), ('lightdm','default'), ('dexos-bootsplash-finish','default'), ('mount-ro','shutdown'), ('killprocs','shutdown'), ('savecache','shutdown')]:
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


def install_argon_theme():
    src = Path('/usr/share/dexos/argon-grub-theme')
    if not src.is_dir() or not (src / 'theme.txt').is_file():
        raise InstallError('Falta el tema Argon precompilado en el medio Live.')
    dst = TARGET / 'boot/grub/themes/argon'
    copy_if(src, dst)
    if not (dst / 'theme.txt').is_file():
        raise InstallError('No se pudo instalar el tema Argon de GRUB.')


def install_bootloader(boot_disk, root_uuid, efi_partition=None, *, preserve_efi=False):
    progress(0.86, 'Instalando GRUB y detectando otros sistemas')
    efi_boot = Path('/sys/firmware/efi').is_dir()
    bios_ok = disk_supports_bios(boot_disk)

    if bios_ok:
        rc = run(['grub-install', '--boot-directory=' + str(TARGET / 'boot'), '--target=i386-pc', boot_disk], check=False)
        if rc != 0 and not efi_partition:
            raise InstallError('No se pudo instalar GRUB BIOS y no existe una alternativa UEFI.')
        if rc != 0:
            log('GRUB BIOS no pudo instalarse; se continuará con UEFI.')
    elif not efi_partition:
        raise InstallError('El disco no admite GRUB BIOS y no se seleccionó una partición EFI.')

    if efi_partition:
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
    write(TARGET / 'etc/default/grub', '''GRUB_TIMEOUT=8\nGRUB_DEFAULT=saved\nGRUB_SAVEDEFAULT=false\nGRUB_DISABLE_SUBMENU=y\nGRUB_DISABLE_RECOVERY=true\nGRUB_DISTRIBUTOR="DexOS"\nGRUB_DISABLE_LINUX_UUID=false\nGRUB_DISABLE_OS_PROBER=false\nGRUB_THEME="/boot/grub/themes/argon/theme.txt"\nGRUB_GFXMODE="1920x1080,auto"\nGRUB_GFXPAYLOAD_LINUX=keep\nGRUB_CMDLINE_LINUX_DEFAULT="quiet splash vt.global_cursor_default=0 rootfstype=ext4 modules=virtio,virtio_ring,virtio_pci,virtio_blk,ext4"\n''')
    # os-prober remains the primary detector. 31_dexos_other_os safely fills
    # gaps without rewriting foreign Linux kernel command lines.
    chroot(['/usr/bin/os-prober'], check=False)
    chroot(['/usr/local/sbin/grub-update'])
    grub_cfg = TARGET / 'boot/grub/grub.cfg'
    verify = grub_cfg.read_text()
    if f'root=UUID={root_uuid}' not in verify:
        raise InstallError('GRUB no quedó configurado con el UUID de la raíz DexOS.')
    chroot(['/usr/sbin/grub-set-default', '0'], check=False)

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


def format_root_ext4(root):
    progress(0.14, f'Formateando {root} como ext4')
    run(['wipefs', '-a', root])
    wait_block(root)
    run(['mkfs.ext4', '-F', '-L', 'DexOS', root])
    fs = output(['blkid', '-p', '-s', 'TYPE', '-o', 'value', root])
    if fs != 'ext4':
        raise InstallError(f'El formato de {root} no quedó como ext4 (detectado: {fs or "desconocido"}).')


def create_root_from_free(disk, region):
    start = int(region.get('start_sector') or 0)
    sectors = int(region.get('sectors') or 0)
    if not start or not sectors:
        raise InstallError('El hueco libre no contiene coordenadas de sectores seguras.')
    current = {(int(r.get('start_sector') or -1), int(r.get('sectors') or -1)) for r in free_regions(disk)}
    if (start, sectors) not in current:
        raise InstallError('El espacio no asignado cambió desde la última revisión.')
    pttype = disk_pttype(disk)
    progress(0.10, 'Creando partición DexOS dentro del espacio no asignado')
    if pttype == 'gpt':
        spec = f'start={start},size={sectors},type={LINUX_GUID},name="DexOS"\n'
    elif pttype in ('dos', 'msdos'):
        spec = f'start={start},size={sectors},type=83\n'
    else:
        raise InstallError(f'La tabla de particiones {pttype or "desconocida"} no permite coexistencia automática.')
    before = {n.get('path') for n in flatten(lsblk_tree(disk)) if n.get('type') == 'part'}
    run(['sfdisk', '--append', '--wipe', 'never', '--wipe-partitions', 'never', disk], input_text=spec)
    refresh_partition_nodes(disk)
    after = [n for n in flatten(lsblk_tree(disk)) if n.get('type') == 'part' and n.get('path') not in before]
    if len(after) != 1:
        raise InstallError('La partición fue creada, pero no pudo identificarse de forma inequívoca.')
    root = after[0]['path']
    wait_block(root)
    return root


def prepare_alongside(cfg):
    disk = cfg['disk']
    root = cfg.get('_root_partition')
    if not root:
        root = create_root_from_free(disk, cfg['_free_region'])
    reason = root_partition_reason(root, disk)
    if reason != 'ok':
        raise InstallError(f'El destino raíz cambió antes del formateo ({reason}).')
    format_root_ext4(root)
    efi = cfg.get('efi_partition') or ''
    return {'root': root, 'efi': efi, 'boot_disk': disk, 'preserve_efi': bool(efi)}


def prepare_manual(cfg):
    root = cfg['root_partition']
    disk = parent_disk(root)
    reason = root_partition_reason(root, disk)
    if reason != 'ok':
        raise InstallError(f'El destino raíz cambió antes del formateo ({reason}).')
    format_root_ext4(root)
    efi = cfg.get('efi_partition') or ''
    return {'root': root, 'efi': efi, 'boot_disk': disk, 'preserve_efi': bool(efi)}

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
        if efi_partition:
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
        install_bootloader(layout['boot_disk'], root_uuid, efi_partition, preserve_efi=layout['preserve_efi'])
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
