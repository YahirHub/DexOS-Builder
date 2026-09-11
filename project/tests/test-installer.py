#!/usr/bin/python3
import ast, datetime, importlib.util, inspect, pathlib, subprocess, tarfile, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
path = ROOT / 'project/installer/dexos-installer-backend.py'
spec = importlib.util.spec_from_file_location('backend', path)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

assert m.partitions('/dev/sda') == ('/dev/sda1','/dev/sda2','/dev/sda3')
assert m.partitions('/dev/nvme0n1') == ('/dev/nvme0n1p1','/dev/nvme0n1p2','/dev/nvme0n1p3')
assert m.HOST_RE.fullmatch('dexos-pc') and not m.HOST_RE.fullmatch('-bad')
assert m.USER_RE.fullmatch('usuario_1') and not m.USER_RE.fullmatch('Root')
assert m.MIN_ALONGSIDE >= 12 * 1024**3
backend_text = path.read_text()

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

# sfdisk free-space parser used by coexistence. It preserves exact sector coordinates.
orig_output = m.output
def fake_output(cmd):
    if cmd[:2] == ['blockdev', '--getss']:
        return '512'
    if cmd[:2] == ['sfdisk', '--list-free']:
        return '  2048  100000000  99997953  47.7G\n'
    raise AssertionError(cmd)
m.output = fake_output
regions = m.free_regions('/dev/sda')
m.output = orig_output
assert len(regions) == 1
assert regions[0]['start_sector'] == 2048 and regions[0]['sectors'] == 99997953
assert regions[0]['size'] > 40 * 1024**3

# Root eligibility rejects boot/reserved/mounted/small partitions and accepts unformatted roots.
orig_node, orig_parent = m.node_by_path, m.parent_disk
cases = {
    '/dev/sda1': {'path':'/dev/sda1','type':'part','ro':0,'size':20*1024**3,'fstype':'','parttype':m.LINUX_GUID,'mountpoints':[None]},
    '/dev/sda2': {'path':'/dev/sda2','type':'part','ro':0,'size':512*1024**2,'fstype':'vfat','parttype':m.ESP_GUID,'mountpoints':[None]},
    '/dev/sda3': {'path':'/dev/sda3','type':'part','ro':0,'size':128*1024**2,'fstype':'','parttype':m.MSR_GUID,'mountpoints':[None]},
    '/dev/sda4': {'path':'/dev/sda4','type':'part','ro':0,'size':20*1024**3,'fstype':'ext4','parttype':m.LINUX_GUID,'mountpoints':['/mnt']},
}
m.node_by_path = lambda path: cases.get(path)
m.parent_disk = lambda path: '/dev/sda'
assert m.root_partition_reason('/dev/sda1','/dev/sda') == 'ok'
assert m.root_partition_reason('/dev/sda2','/dev/sda') == 'particion-efi'
assert m.root_partition_reason('/dev/sda3','/dev/sda') == 'reservada-windows'
assert m.root_partition_reason('/dev/sda4','/dev/sda') == 'montada'
m.node_by_path, m.parent_disk = orig_node, orig_parent

# BIOS support: MBR works directly; GPT requires a BIOS Boot partition.
orig_pt, orig_tree = m.disk_pttype, m.lsblk_tree
m.disk_pttype = lambda disk: 'dos'
assert m.disk_supports_bios('/dev/sda')
m.disk_pttype = lambda disk: 'gpt'
m.lsblk_tree = lambda disk=None: [{'path':'/dev/sda','type':'disk','children':[{'path':'/dev/sda1','type':'part','parttype':m.BIOS_GUID}]}]
assert m.disk_supports_bios('/dev/sda')
m.lsblk_tree = lambda disk=None: [{'path':'/dev/sda','type':'disk','children':[{'path':'/dev/sda1','type':'part','parttype':m.LINUX_GUID}]}]
assert not m.disk_supports_bios('/dev/sda')
m.disk_pttype, m.lsblk_tree = orig_pt, orig_tree

# Coexistence creates roots with sfdisk --append and never rewrites the whole table.
create_root = inspect.getsource(m.create_root_from_free)
assert "'sfdisk', '--append', '--wipe', 'never', '--wipe-partitions', 'never'" in create_root
assert 'parted' not in create_root

# DexOS owns only its own GRUB entry; foreign Linux entries are never rewritten.
primary = (ROOT/'project/installed/09_dexos_linux').read_text()
assert 'root=UUID=$root_uuid' in primary
assert ' quiet ' in primary and 'splash' not in primary
assert 'modules=virtio,virtio_ring,virtio_pci,virtio_blk,ext4' in primary
assert 'def rewrite_grub_root' not in backend_text

# Installed initramfs uses stock mkinitfs without DexOS image/splash patching.
assert 'patch_installed_initramfs' not in backend_text
assert 'fbsplash' not in backend_text
assert '/usr/share/dexos/boot.ppm' not in backend_text

# Three safe installation paths.
assert "mode == 'erase'" in backend_text
assert "mode == 'alongside'" in backend_text
assert "mode == 'manual'" in backend_text
assert 'COEXISTIR {disk}' in backend_text
assert 'FORMATEAR {root}' in backend_text
assert "sfdisk', '--list-free'" in backend_text
assert 'free_regions(disk)' in backend_text

# Alongside/manual preserve EFI: root formatting is centralized and EFI is never formatted.
along = inspect.getsource(m.prepare_alongside)
manual = inspect.getsource(m.prepare_manual)
format_root = inspect.getsource(m.format_root_ext4)
assert 'format_root_ext4' in along and 'mkfs.vfat' not in along
assert 'format_root_ext4' in manual and 'mkfs.vfat' not in manual
assert "wipefs', '-a'" in format_root and "mkfs.ext4" in format_root
assert "'preserve_efi': bool(efi)" in along and "'preserve_efi': bool(efi)" in manual

# GRUB dualboot + Argon contract.
bootloader = inspect.getsource(m.install_bootloader)
assert 'GRUB_DISABLE_OS_PROBER=false' in bootloader
assert "'/usr/bin/os-prober'" in bootloader
assert 'install_argon_theme()' in bootloader
assert "if not preserve_efi:" in bootloader
assert 'bios_ok = disk_supports_bios(boot_disk)' in bootloader
assert 'if efi_partition:' in bootloader
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
assert 'geoclue' in packages and 'geoclue-lang' in packages
assert "TARGET / 'etc/geoclue/conf.d/90-dexos-redshift.conf'" in backend_text
assert "cfg['username'] = cfg['username'].strip().lower()" in backend_text

ui = (ROOT/'project/installer/dexos-installer.py').read_text()
assert 'Usar la misma contraseña para root' in ui
assert 'self.same_root_password.set_active(True)' in ui
assert 'self.normalized_username()' in ui
for token in ['Coexistir con Windows / Linux','Particionado manual / dualboot','Abrir GParted','--probe']:
    assert token in ui
assert '<no asignado>' in ui
assert 'se FORMATEARÁ' in ui
assert 'Ninguna — usar GRUB BIOS' in ui
assert 'COEXISTIR {d}' in ui


assert "GRUB_DISABLE_OS_PROBER=false" in backend_text
assert 'GRUB_THEME=' in backend_text and '/boot/grub/themes/argon/theme.txt' in backend_text
assert "chroot(['/usr/bin/os-prober']" in backend_text
assert "def prepare_alongside" in backend_text
assert "def prepare_manual" in backend_text
assert "gparted" in ui
assert "Coexistir con Windows / Linux" in ui
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


# v006/v015 installed branding: wallpaper remains, boot/session splash removed.
assert "'/usr/share/dexos/dexos-wallpaper.png'" in backend_text
assert "TARGET / 'usr/share/dexos/dexos-wallpaper.png'" in backend_text
assert "TARGET / 'usr/share/backgrounds/xfce/DexOS.png'" in backend_text
assert "TARGET / 'usr/share/xfce4/backdrops/DexOS.png'" in backend_text
assert "TARGET / 'etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml'" in backend_text
assert "patch-initramfs-init.py" not in backend_text
assert 'GRUB_GFXPAYLOAD_LINUX=keep' in backend_text
assert 'vt.global_cursor_default=0' in backend_text
assert '~language' not in backend_text
assert "Reiniciar ahora" in ui
assert "doas', 'reboot'" in ui
assert "/usr/share/dexos/wallpaper'" not in backend_text


# v015: no custom DexOS boot image is embedded in the installed initramfs.
assert "ata base ide scsi usb virtio ext4 nvme kms dexosroot" in backend_text
for token in ['/usr/share/dexos/boot.ppm', '/sbin/fbsplash', 'dexos-bootsplash', 'dexos-bootsplash-finish']:
    assert token not in backend_text


# v008 installed sessions use the same deterministic pre-XFCE wallpaper helper.
assert "dexos-prepare-desktop" in backend_text
assert "TARGET / 'usr/local/sbin/boot-order'" in backend_text
assert "TARGET / 'usr/local/sbin/grub-update'" in backend_text
boot_order = (ROOT/'project/installed/boot-order').read_text()
grub_update = (ROOT/'project/installed/grub-update').read_text()
assert 'grub-set-default' in boot_order and 'saved_entry' in boot_order
assert 'grub-script-check' in grub_update and 'grub-mkconfig' in grub_update
theme_gen = (ROOT/'project/installed/05_dexos_theme').read_text()
primary_gen = (ROOT/'project/installed/09_dexos_linux').read_text()
fallback_gen = (ROOT/'project/installed/grub-other-os').read_text()
assert 'gfxmenu' in theme_gen and 'themes/argon/theme.txt' in theme_gen
assert "menuentry 'DexOS'" in primary_gen and 'root=UUID=$root_uuid' in primary_gen
assert ' quiet ' in primary and 'splash' not in primary_gen and 'vt.global_cursor_default=0' in primary_gen
assert 'os-prober is still the primary detector' in fallback_gen
assert 'emit_efi_loader' in fallback_gen and 'emit_linux_kernel' in fallback_gen and 'emit_windows_bios' in fallback_gen
assert "TARGET / 'etc/grub.d/05_dexos_theme'" in backend_text
assert "TARGET / 'etc/grub.d/09_dexos_linux'" in backend_text
assert "TARGET / 'etc/grub.d/31_dexos_other_os'" in backend_text
assert "update_grub.symlink_to('grub-update')" in backend_text
assert "stock in ('10_linux', '20_linux_xen')" in backend_text
# Coexistence safety: generating GRUB must never rewrite Linux lines belonging to another OS.
boot_source = inspect.getsource(m.install_bootloader)
assert 'rewrite_grub_root(' not in boot_source
assert "'/usr/local/sbin/grub-update'" in boot_source
assert "'/usr/sbin/grub-set-default', '0'" in boot_source
assert "xfce-x.svg" in backend_text
assert "symlink_to('/usr/share/dexos/dexos-wallpaper.png')" in backend_text


# v010 installed desktop utilities and power/cursor integration.
assert "TARGET / 'usr/local/bin/dexos-boot-manager'" in backend_text
assert "TARGET / 'usr/local/bin/dexos-eye-protection'" in backend_text
assert "TARGET / 'etc/init.d/dexos-power'" in backend_text
assert "TARGET / 'etc/redshift.conf'" in backend_text
assert "TARGET / 'usr/local/sbin/dexos-power-apply'" in backend_text
assert "TARGET / 'usr/share/icons/DexOS-Windows'" in backend_text
assert "cursor-theme-name=DexOS-Windows" in backend_text
assert "TARGET / 'etc/skel/Desktop'" in backend_text
assert "('bluetooth','default'), ('alsa','default'), ('dexos-backlight','default'), ('dexos-power','default'), ('lightdm','default')" in backend_text
boot_gui = (ROOT/'project/installed/dexos-boot-manager.py').read_text()
assert 'Escanear discos y actualizar GRUB' in boot_gui
assert "self.run_async([GRUB_UPDATE], self.after_scan)" in boot_gui
assert "BOOT_ORDER, '--set'" in boot_gui
eye_gui = (ROOT/'project/installed/dexos-eye-protection.py').read_text()
assert "['redshift', '-m', 'randr', '-l', 'geoclue2'" in eye_gui
assert "manual:lat=0:lon=0" in eye_gui
power_apply = (ROOT/'project/installed/dexos-power-apply').read_text()
assert 'powerprofilesctl set balanced' in power_apply
assert 'energy_performance_preference' in power_apply
assert 'scaling_governor' in power_apply


# v013 persistence and privileged boot manager.
assert 'alsa-utils-openrc' in packages
assert "TARGET / 'etc/init.d/dexos-backlight'" in backend_text
assert "TARGET / 'usr/share/polkit-1/actions/org.dexos.boot-manager.policy'" in backend_text
audio_init = (ROOT/'project/installed/dexos-audio-init').read_text()
assert 'wpctl set-volume' not in audio_init and 'wpctl set-mute' not in audio_init
assert '/var/lib/alsa/asound.state' in audio_init
backlight = (ROOT/'project/installed/dexos-backlight-state').read_text()
assert 'save_backlights' in backlight and 'restore_backlights' in backlight
assert '/var/lib/dexos/backlight' in backlight
policy = (ROOT/'project/installed/org.dexos.boot-manager.policy').read_text()
assert 'auth_admin_keep' in policy and 'org.freedesktop.policykit.exec.allow_gui' in policy
assert 'ensure_admin()' in boot_gui and "os.execv(pkexec" in boot_gui
assert 'privileged(' not in boot_gui


# v014 brightness regression: restore validation must not contain a wildcard
# branch that matches every value.
assert 'case "$value:$max" in' not in backlight
assert 'case "$value" in' in backlight and 'case "$max" in' in backlight
assert 'restored $name=$value/$max' in backlight

# Offline Redshift uses local time with gradual dawn/dusk transitions.
eye_tree = ast.parse(eye_gui)
fallback_node = next(node for node in eye_tree.body if isinstance(node, ast.FunctionDef) and node.name == 'fallback_temperature')
ns = {'datetime': datetime.datetime}
exec(compile(ast.Module(body=[fallback_node], type_ignores=[]), '<fallback_temperature>', 'exec'), ns)
fallback_temperature = ns['fallback_temperature']
assert fallback_temperature(4500, datetime.datetime(2026, 9, 10, 2, 0)) == 4500
assert fallback_temperature(4500, datetime.datetime(2026, 9, 10, 8, 0)) == 6500
assert fallback_temperature(4500, datetime.datetime(2026, 9, 10, 19, 0)) == 5500
assert '--auto-daemon' in eye_gui and 'internet_available' in eye_gui
assert 'Sin Internet/GeoClue2' in eye_gui


# v015: persistent Night Light, user-owned wallpaper and Windows-like touchpad.
prepare_desktop = (ROOT/'project/installed/dexos-prepare-desktop').read_text()
assert 'wallpaper-initialized' in prepare_desktop
assert '[ -e "$marker" ] && exit 0' in prepare_desktop
assert 'last-image' in prepare_desktop
session = (ROOT/'project/installed/dexos-session').read_text()
assert 'dexos-session-splash' not in session
overlay = (ROOT/'project/mkimage/genapkovl-yahxfce.sh').read_text()
apply_block = overlay.split("<<'EOF_APPLY_THEME'", 1)[1].split('\nEOF_APPLY_THEME', 1)[0]
assert 'last-image' not in apply_block and 'set_backdrop' not in apply_block
for token in [
    'Option "TappingDrag" "on"', 'Option "TappingDragLock" "off"',
    'Option "HorizontalScrolling" "on"', 'Option "NaturalScrolling" "off"',
    'Option "ClickMethod" "buttonareas"', 'Option "MiddleEmulation" "off"',
    'Option "AccelProfile" "adaptive"', 'Option "AccelSpeed" "0.00"',
    'Option "ScrollPixelDistance" "15"',
]:
    assert token in overlay
assert "if not data['enabled']" in eye_gui
assert 'self.autostart = Gtk.CheckButton' not in eye_gui
assert 'Se restaurará automáticamente al iniciar sesión.' in eye_gui
for removed in [
    ROOT/'project/assets/dexos-boot.jpg', ROOT/'project/assets/dexos-boot.ppm',
    ROOT/'project/boot/fbsplash.ppm', ROOT/'project/installed/dexos-session-splash.py',
    ROOT/'project/installed/dexos-bootsplash', ROOT/'project/installed/dexos-bootsplash-finish',
    ROOT/'project/installed/dexos-splash-keys', ROOT/'project/mkimage/patch-initramfs-init.py',
]:
    assert not removed.exists()

print('test-installer: OK')
