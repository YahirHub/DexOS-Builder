#!/usr/bin/python3
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

TARGET = Path('/mnt/dexos-target')
MIN_DISK = 8 * 1024**3
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
    cmd = ['lsblk', '-J', '-b', '-o', 'PATH,NAME,TYPE,SIZE,MODEL,RO,RM,TRAN,MOUNTPOINTS']
    if disk:
        cmd.append(disk)
    return json.loads(output(cmd)).get('blockdevices', [])

def mounted(node):
    mps = node.get('mountpoints') or []
    if any(x for x in mps if x):
        return True
    return any(mounted(c) for c in node.get('children') or [])

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

def validate(cfg):
    required = ['disk', 'hostname', 'username', 'password', 'root_password', 'timezone', 'erase_confirm']
    for k in required:
        if k not in cfg:
            raise InstallError(f'Falta el dato requerido: {k}')
    disk = cfg['disk']
    allowed = {d['path'] for d in safe_disks()}
    if disk not in allowed:
        raise InstallError('El disco seleccionado ya no es un destino seguro o tiene particiones montadas.')
    if not HOST_RE.fullmatch(cfg['hostname']):
        raise InstallError('Hostname no válido.')
    if not USER_RE.fullmatch(cfg['username']) or cfg['username'] == 'root':
        raise InstallError('Nombre de usuario no válido.')
    if len(cfg['password']) < 8:
        raise InstallError('La contraseña del usuario debe tener al menos 8 caracteres.')
    if len(cfg['root_password']) < 8:
        raise InstallError('La contraseña root debe tener al menos 8 caracteres.')
    tz = cfg['timezone']
    if tz.startswith('/') or '..' in tz.split('/') or not (Path('/usr/share/zoneinfo') / tz).is_file():
        raise InstallError('Zona horaria no válida.')
    if cfg['erase_confirm'] != f'BORRAR {disk}':
        raise InstallError('La confirmación de borrado no coincide con el disco seleccionado.')
    return cfg

def partitions(disk):
    suffix = 'p' if disk[-1].isdigit() else ''
    return f'{disk}{suffix}1', f'{disk}{suffix}2', f'{disk}{suffix}3'

def wait_block(path, timeout=15):
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
    copy_if('/usr/share/dexos/wallpaper', TARGET / 'usr/share/dexos/wallpaper.jpg')
    copy_if('/usr/local/bin/dexos-session', TARGET / 'usr/local/bin/dexos-session', 0o755)
    copy_if('/usr/local/bin/dexos-session-splash', TARGET / 'usr/local/bin/dexos-session-splash', 0o755)
    copy_if('/usr/share/dexos/installed/dexos-splash-keys', TARGET / 'usr/local/sbin/dexos-splash-keys', 0o755)
    copy_if('/usr/share/dexos/installed/dexos-bootsplash', TARGET / 'etc/init.d/dexos-bootsplash', 0o755)
    copy_if('/usr/share/dexos/installed/dexos-bootsplash-finish', TARGET / 'etc/init.d/dexos-bootsplash-finish', 0o755)
    copy_if('/usr/share/dexos/installed/dexos-wifi-init', TARGET / 'etc/init.d/dexos-wifi-init', 0o755)
    copy_if('/usr/share/dexos/installed/dexos-wifi-refresh', TARGET / 'etc/init.d/dexos-wifi-refresh', 0o755)
    copy_if('/usr/local/sbin/dexos-xsetup', TARGET / 'usr/local/sbin/dexos-xsetup', 0o755)
    copy_if('/usr/local/bin/dexos-apply-theme', TARGET / 'usr/local/bin/dexos-apply-theme', 0o755)
    copy_if('/etc/xdg/autostart/dexos-branding.desktop', TARGET / 'etc/xdg/autostart/dexos-branding.desktop')
    copy_if('/etc/xdg/xfce4/xfconf/xfce-perchannel-xml', TARGET / 'etc/xdg/xfce4/xfconf/xfce-perchannel-xml')
    copy_if('/etc/skel/.config/gtk-3.0', TARGET / 'etc/skel/.config/gtk-3.0')
    write(TARGET / 'etc/os-release', '''NAME="DexOS"\nPRETTY_NAME="DexOS"\nID=dexos\nID_LIKE=alpine\nVERSION_ID="0.1"\nVERSION="0.1"\n''')
    write(TARGET / 'etc/issue', 'DexOS \\n \\l\n')
    write(TARGET / 'etc/lightdm/lightdm.conf.d/10-dexos.conf', '''[LightDM]\nlogind-check-graphical=false\n\n[Seat:*]\ndisplay-setup-script=/usr/local/sbin/dexos-xsetup\ngreeter-session=lightdm-gtk-greeter\nuser-session=dexos\n''')
    write(TARGET / 'etc/lightdm/lightdm-gtk-greeter.conf', '''[greeter]\nbackground=/usr/share/dexos/wallpaper\ntheme-name=adw-gtk3-dark\nicon-theme-name=Adwaita-Xfce\nfont-name=DejaVu Sans 11\nclock-format=%A %d de %B  %H:%M\nindicators=~host;~spacer;~clock;~spacer;~session;~language;~a11y;~power\nuser-background=false\n''')
    write(TARGET / 'etc/doas.d/20-dexos.conf', 'permit :wheel\n', 0o600)
    write(TARGET / 'etc/sudoers.d/10-wheel', '%wheel ALL=(ALL:ALL) ALL\n', 0o440)
    write(TARGET / 'etc/conf.d/networkmanager', 'rc_need="dexos-wifi-init"\n')
    write(TARGET / 'usr/share/xsessions/dexos.desktop', '[Desktop Entry]\nName=DexOS\nComment=DexOS XFCE Session\nExec=/usr/local/bin/dexos-session\nTryExec=/usr/local/bin/dexos-session\nType=Application\nDesktopNames=XFCE\n')

def patch_installed_initramfs(text):
    """Enable DexOS bootsplash from the installed initramfs when no ISO is present."""
    if '/usr/share/dexos/boot.ppm' in text:
        return text
    needle = 'for fbsplash in /media/*/fbsplash.ppm; do\n\t\t[ -e "$fbsplash" ] && break\n\tdone'
    if needle not in text:
        raise InstallError('La versión de mkinitfs no contiene el punto de integración de bootsplash esperado.')
    return text.replace(needle, needle + '\n\t[ -e "$fbsplash" ] || fbsplash=/usr/share/dexos/boot.ppm', 1)


def configure_system(cfg, p2, p3):
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

    configure_branding()

    chroot(['/usr/sbin/adduser', '-D', '-s', '/bin/bash', cfg['username']])
    for group in ['wheel', 'audio', 'video', 'input', 'netdev', 'plugdev']:
        chroot(['/usr/sbin/addgroup', cfg['username'], group], check=False)
    chroot(['/usr/sbin/chpasswd'], input_text=f"{cfg['username']}:{cfg['password']}\nroot:{cfg['root_password']}\n")
    chroot(['/usr/sbin/usermod', '-s', '/bin/bash', 'root'], check=False)
    write(TARGET / 'etc/default/useradd', 'SHELL=/bin/bash\n')

    # Copy the red GTK defaults into the new user's home too.
    home = TARGET / 'home' / cfg['username']
    copy_if(TARGET / 'etc/skel/.config', home / '.config')
    chroot(['/bin/chown', '-R', f"{cfg['username']}:{cfg['username']}", f"/home/{cfg['username']}"])

    root_uuid = output(['blkid', '-s', 'UUID', '-o', 'value', p3])
    efi_uuid = output(['blkid', '-s', 'UUID', '-o', 'value', p2])
    write(TARGET / 'etc/fstab', f'''UUID={root_uuid}\t/\text4\tdefaults,noatime\t0 1\nUUID={efi_uuid}\t/boot/efi\tvfat\tumask=0077\t0 2\ntmpfs\t/tmp\ttmpfs\tnosuid,nodev\t0 0\n''')
    write(TARGET / 'etc/apk/repositories', '''https://dl-cdn.alpinelinux.org/alpine/edge/main\nhttps://dl-cdn.alpinelinux.org/alpine/edge/community\n''')
    write(TARGET / 'etc/mkinitfs/features.d/dexosroot.modules', '''kernel/drivers/virtio/virtio.ko*\nkernel/drivers/virtio/virtio_ring.ko*\nkernel/drivers/virtio/virtio_pci.ko*\nkernel/drivers/block/virtio_blk.ko*\nkernel/fs/ext4/ext4.ko*\n''')
    write(TARGET / 'etc/mkinitfs/features.d/dexosroot.files', '/usr/share/dexos/boot.ppm\n')
    init_script = TARGET / 'usr/share/mkinitfs/initramfs-init'
    if not init_script.is_file():
        raise InstallError('Falta initramfs-init en el sistema destino.')
    init_script.write_text(patch_installed_initramfs(init_script.read_text()))
    write(TARGET / 'etc/mkinitfs/mkinitfs.conf', 'features="ata base ide scsi usb virtio ext4 nvme dexosroot"\n')

    # Standard installed-system OpenRC, never the Live-only services.
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
        try: d.unlink()
        except FileNotFoundError: pass

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
    initramfs = TARGET / 'boot/initramfs-stable'
    if not initramfs.is_file() or initramfs.stat().st_size < 1024 * 1024:
        raise InstallError('mkinitfs no generó un initramfs válido.')

def rewrite_grub_root(text, root_uuid):
    fixed = []
    for line in text.splitlines():
        if re.match(r'^\s*linux(?:efi)?\s', line):
            line = re.sub(r'\s+root=\S+', '', line)
            line = re.sub(r'\s+rootfstype=\S+', '', line)
            line = re.sub(r'\s+modules=\S+', '', line)
            line += f' root=UUID={root_uuid} quiet splash rootfstype=ext4 modules=virtio,virtio_ring,virtio_pci,virtio_blk,ext4'
        fixed.append(line)
    return '\n'.join(fixed) + '\n'


def install_bootloader(disk, root_uuid):
    progress(0.86, 'Instalando GRUB BIOS/UEFI')
    # BIOS path for older PCs.
    run(['grub-install', '--boot-directory=' + str(TARGET / 'boot'), '--target=i386-pc', disk])
    # UEFI path with fallback file; no NVRAM dependency.
    run(['grub-install', '--target=x86_64-efi', '--efi-directory=' + str(TARGET / 'boot/efi'),
         '--bootloader-id=DexOS', '--boot-directory=' + str(TARGET / 'boot'), '--no-nvram'])
    efi = TARGET / 'boot/efi/EFI/DexOS/grubx64.efi'
    if not efi.is_file():
        raise InstallError('GRUB UEFI no generó grubx64.efi.')
    fallback = TARGET / 'boot/efi/EFI/BOOT/BOOTX64.EFI'
    fallback.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(efi, fallback)
    write(TARGET / 'etc/default/grub', '''GRUB_TIMEOUT=3\nGRUB_DISABLE_SUBMENU=y\nGRUB_DISABLE_RECOVERY=true\nGRUB_DISTRIBUTOR="DexOS"\nGRUB_DISABLE_LINUX_UUID=false\nGRUB_CMDLINE_LINUX_DEFAULT="quiet splash rootfstype=ext4 modules=virtio,virtio_ring,virtio_pci,virtio_blk,ext4"\n''')
    chroot(['/usr/sbin/grub-mkconfig', '-o', '/boot/grub/grub.cfg'])
    grub_cfg = TARGET / 'boot/grub/grub.cfg'
    text = grub_cfg.read_text()
    write(grub_cfg, rewrite_grub_root(text, root_uuid), 0o644)
    verify = grub_cfg.read_text()
    if f'root=UUID={root_uuid}' not in verify:
        raise InstallError('GRUB no quedó configurado con el UUID de la raíz.')
    if re.search(r'\sroot=/dev/', verify):
        raise InstallError('GRUB todavía contiene una ruta /dev/ inestable para la raíz.')

def install(cfg):
    cfg = validate(cfg)
    disk = cfg['disk']
    p1, p2, p3 = partitions(disk)
    repo = find_repo()
    pkgs = package_list()
    progress(0.03, 'Validando disco y medio Live')
    log(f'Destino: {disk}')
    log(f'Repositorio offline: {repo}')
    log(f'Paquetes base: {len(pkgs)}')

    try:
        progress(0.08, 'Creando tabla GPT segura')
        run(['wipefs', '-a', disk])
        layout = f'''label: gpt\nsize=2M, type={BIOS_GUID}\nsize=512M, type={ESP_GUID}\ntype={LINUX_GUID}\n'''
        run(['sfdisk', '--wipe', 'always', '--wipe-partitions', 'always', disk], input_text=layout)
        run(['partprobe', disk])
        run(['udevadm', 'settle', '--timeout=15'])
        for p in (p1, p2, p3): wait_block(p)

        progress(0.14, 'Formateando particiones')
        run(['mkfs.vfat', '-F', '32', '-n', 'DEXOS_EFI', p2])
        run(['mkfs.ext4', '-F', '-L', 'DexOS', p3])

        progress(0.19, 'Montando sistema destino')
        TARGET.mkdir(parents=True, exist_ok=True)
        mount(p3, TARGET)
        mount(p2, TARGET / 'boot/efi')
        for src in ['/proc', '/dev', '/sys', '/run']:
            mount(src, TARGET / src.lstrip('/'), rbind=True)

        (TARGET / 'etc/apk/keys').mkdir(parents=True, exist_ok=True)
        for key in Path('/etc/apk/keys').glob('*'):
            if key.is_file(): shutil.copy2(key, TARGET / 'etc/apk/keys' / key.name)

        progress(0.24, 'Instalando DexOS desde la ISO')
        run(['apk', 'add', '--root', str(TARGET), '--initdb', '--arch', 'x86_64', '--keys-dir', '/etc/apk/keys',
             '--no-network', '--repository', repo] + pkgs)

        configure_system(cfg, p2, p3)
        root_uuid = output(['blkid', '-s', 'UUID', '-o', 'value', p3])
        install_bootloader(disk, root_uuid)
        progress(0.96, 'Sincronizando datos')
        run(['sync'])
        cleanup()
        progress(1.0, 'DexOS instalado correctamente')
        send('done', message='Instalación completada. Ya puedes reiniciar y retirar el medio Live.')
    except Exception:
        cleanup()
        raise

def main():
    if os.geteuid() != 0:
        raise InstallError('El backend debe ejecutarse como root mediante doas.')
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
