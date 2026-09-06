#!/usr/bin/python3
import importlib.util, inspect, pathlib, subprocess, tarfile, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
path = ROOT / 'project/installer/dexos-installer-backend.py'
spec = importlib.util.spec_from_file_location('backend', path)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

assert m.partitions('/dev/sda') == ('/dev/sda1','/dev/sda2','/dev/sda3')
assert m.partitions('/dev/nvme0n1') == ('/dev/nvme0n1p1','/dev/nvme0n1p2','/dev/nvme0n1p3')
assert m.HOST_RE.fullmatch('dexos-pc') and not m.HOST_RE.fullmatch('-bad')
assert m.USER_RE.fullmatch('usuario_1') and not m.USER_RE.fullmatch('Root')
assert m.MIN_ALONGSIDE >= 12 * 1024**3

# write() must unlink symlinks rather than following them outside the target.
with tempfile.TemporaryDirectory() as td:
    td = pathlib.Path(td); victim = td/'victim'; victim.write_text('SAFE')
    link = td/'link'; link.symlink_to(victim)
    m.write(link, 'DEXOS')
    assert victim.read_text() == 'SAFE' and link.read_text() == 'DEXOS' and not link.is_symlink()

# Full-disk GPT layout remains valid.
with tempfile.TemporaryDirectory() as td:
    img = pathlib.Path(td)/'disk.img'; subprocess.run(['truncate','-s','9G',img], check=True)
    layout = f'''label: gpt\nsize=2M, type={m.BIOS_GUID}\nsize=512M, type={m.ESP_GUID}\ntype={m.LINUX_GUID}\n'''
    subprocess.run(['sfdisk','--quiet',img], input=layout, text=True, check=True)
    dump = subprocess.check_output(['sfdisk','-d',img], text=True).lower()
    assert m.BIOS_GUID.lower() in dump and m.ESP_GUID.lower() in dump and m.LINUX_GUID.lower() in dump

# Parted free-space parser used by "alongside".
orig_output = m.output
m.output = lambda cmd: '''BYT;\n/dev/sda:100000000000B:scsi:512:512:gpt:Disk:;\n1:1048576B:50000000000B:49998951425B:ntfs:Windows:msftdata;\n1:50000000001B:99999999999B:49999999999B:free;'''
regions = m.free_regions('/dev/sda')
m.output = orig_output
assert len(regions) == 1 and regions[0]['size'] > 40 * 1024**3

# GRUB entries use stable UUIDs, splash and storage modules.
sample = '''menuentry "DexOS" {\n    linux /boot/vmlinuz-lts root=/dev/vda3 quiet modules=sd-mod,ext4\n    initrd /boot/initramfs-lts\n}\n'''
fixed = m.rewrite_grub_root(sample, '1111-2222')
assert 'root=/dev/vda3' not in fixed
assert 'root=UUID=1111-2222' in fixed
assert 'quiet splash' in fixed
assert 'modules=virtio,virtio_ring,virtio_pci,virtio_blk,ext4' in fixed

# Installed initramfs embeds the DexOS splash fallback.
mk_candidates = sorted(list((ROOT/'cache').rglob('mkinitfs-*.apk')) + list((ROOT/'alpine-root').rglob('mkinitfs-*.apk')))
assert mk_candidates
with tarfile.open(mk_candidates[-1], 'r:gz') as tf:
    init_text = tf.extractfile('usr/share/mkinitfs/initramfs-init').read().decode()
patched = m.patch_installed_initramfs(init_text)
assert '/usr/share/dexos/boot.ppm' in patched and patched.count('/usr/share/dexos/boot.ppm') == 1

backend_text = path.read_text()
# Three safe installation paths.
assert "mode == 'erase'" in backend_text
assert "mode == 'alongside'" in backend_text
assert "mode == 'manual'" in backend_text
assert 'INSTALAR JUNTO A' in backend_text
assert 'FORMATEAR {root}' in backend_text
assert 'free_regions(disk)' in backend_text

# Alongside/manual preserve EFI: they may format root but never mkfs.vfat.
along = inspect.getsource(m.prepare_alongside)
manual = inspect.getsource(m.prepare_manual)
assert 'mkfs.ext4' in along and 'mkfs.vfat' not in along
assert 'mkfs.ext4' in manual and 'mkfs.vfat' not in manual
assert "'preserve_efi': True" in along and "'preserve_efi': True" in manual

# GRUB dualboot + Argon contract.
bootloader = inspect.getsource(m.install_bootloader)
assert 'GRUB_DISABLE_OS_PROBER=false' in bootloader
assert "'/usr/bin/os-prober'" in bootloader
assert 'install_argon_theme()' in bootloader
assert "if not preserve_efi:" in bootloader
assert 'EFI/BOOT/BOOTX64.EFI' in bootloader
assert 'GRUB_THEME=\"/boot/grub/themes/argon/theme.txt\"' in bootloader

# Installed systems retain Wi-Fi/audio services and do not get passwordless root.
assert "dexos-wifi-init','boot'" in backend_text
assert "TARGET / 'etc/init.d/dexos-wifi-init'" in backend_text
assert "TARGET / 'etc/init.d/dexos-wifi-refresh'" in backend_text
assert 'rc_need="dexos-wifi-init"' in backend_text
assert 'passwd -d root' not in backend_text
assert '40-dexos-libinput.conf' in backend_text
assert 'dexos-audio-init' in backend_text

wifi = (ROOT/'project/installed/dexos-wifi-init').read_text()
for token in ['rfkill unblock wlan','/sys/bus/pci/devices/*/modalias','/sys/bus/usb/devices/*/modalias','wireless interface detected']:
    assert token in wifi
refresh = (ROOT/'project/installed/dexos-wifi-refresh').read_text()
for token in ['need networkmanager','nmcli radio wifi on','device wifi rescan','GENERAL.DEVICE,GENERAL.TYPE']:
    assert token in refresh

packages = (ROOT/'project/installer/installer-packages.txt').read_text().split()
for pkg in ['gparted','os-prober','ntfs-3g','ntfs-3g-progs','alsa-ucm-conf','sof-firmware']:
    assert pkg in packages
assert 'linux-firmware' not in packages, 'full linux-firmware metapackage would bloat ISO'

ui = (ROOT/'project/installer/dexos-installer.py').read_text()
for token in ['Instalar junto a Windows','Particionado manual / dualboot','Abrir GParted','--probe']:
    assert token in ui


assert "GRUB_DISABLE_OS_PROBER=false" in backend_text
assert 'GRUB_THEME=' in backend_text and '/boot/grub/themes/argon/theme.txt' in backend_text
assert "chroot(['/usr/bin/os-prober']" in backend_text
assert "def prepare_alongside" in backend_text
assert "def prepare_manual" in backend_text
assert "gparted" in ui
assert "Instalar junto a Windows" in ui
assert "Particionado manual / dualboot" in ui
for pkg in ['os-prober','ntfs-3g','alsa-ucm-conf','sof-firmware']:
    assert pkg in packages


# v004 hardware, partitioning and locale contract.
for pkg in ['mesa-va-gallium','mesa-utils','libva-utils','intel-media-driver','libva-intel-driver','mesa-vulkan-ati','mesa-vulkan-intel',
            'exfatprogs','btrfs-progs','xfsprogs','f2fs-tools','lvm2','mdadm','cryptsetup','e2fsprogs-extra',
            'musl-locales','musl-locales-lang','xfce4-panel-lang','xfce4-session-lang','xfce4-settings-lang','xfce4-terminal-lang','thunar-lang','xfdesktop-lang','xfwm4-lang']:
    assert pkg in packages
assert "SUPPORTED_LOCALES" in backend_text
for loc in ['es_ES.UTF-8','en_US.UTF-8','pt_BR.UTF-8','fr_FR.UTF-8','de_DE.UTF-8','it_IT.UTF-8']:
    assert loc in backend_text
assert "TARGET / 'etc/dexos-locale'" in backend_text
assert "TARGET / 'etc/profile.d/00-dexos-locale.sh'" in backend_text
assert "TARGET / 'usr/local/bin/dexos-video-init'" in backend_text
assert "TARGET / 'usr/local/bin/dexos-language'" in backend_text
assert "'locale': os.environ.get('LANG'" in ui

print('test-installer: OK')
