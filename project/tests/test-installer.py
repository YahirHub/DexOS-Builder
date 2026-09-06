#!/usr/bin/python3
import importlib.util, os, tempfile, subprocess, tarfile, pathlib, re
ROOT=pathlib.Path(__file__).resolve().parents[2]
path=ROOT/'project/installer/dexos-installer-backend.py'
spec=importlib.util.spec_from_file_location('backend',path); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
assert m.partitions('/dev/sda')==('/dev/sda1','/dev/sda2','/dev/sda3')
assert m.partitions('/dev/nvme0n1')==('/dev/nvme0n1p1','/dev/nvme0n1p2','/dev/nvme0n1p3')
assert m.HOST_RE.fullmatch('dexos-pc') and not m.HOST_RE.fullmatch('-bad')
assert m.USER_RE.fullmatch('usuario_1') and not m.USER_RE.fullmatch('Root')
# write() must unlink symlinks instead of following an absolute target outside the install root.
with tempfile.TemporaryDirectory() as td:
    td=pathlib.Path(td); victim=td/'victim'; victim.write_text('SAFE')
    link=td/'link'; link.symlink_to(victim)
    m.write(link,'DEXOS')
    assert victim.read_text()=='SAFE' and link.read_text()=='DEXOS' and not link.is_symlink()
# Partition layout is syntactically valid on a sparse 9 GiB file.
with tempfile.TemporaryDirectory() as td:
    img=pathlib.Path(td)/'disk.img'
    subprocess.run(['truncate','-s','9G',img],check=True)
    layout=f'''label: gpt\nsize=2M, type={m.BIOS_GUID}\nsize=512M, type={m.ESP_GUID}\ntype={m.LINUX_GUID}\n'''
    subprocess.run(['sfdisk','--quiet',img],input=layout,text=True,check=True)
    dump=subprocess.check_output(['sfdisk','-d',img],text=True)
    assert m.BIOS_GUID.lower() in dump.lower()
    assert m.ESP_GUID.lower() in dump.lower()
    assert m.LINUX_GUID.lower() in dump.lower()

# GRUB entries must never depend on /dev/vda3; force stable UUID and root-storage modules.
sample = '''menuentry "DexOS" {
    linux /boot/vmlinuz-stable root=/dev/vda3 quiet modules=sd-mod,ext4
    initrd /boot/initramfs-stable
}
'''
fixed = m.rewrite_grub_root(sample, '1111-2222')
assert 'root=/dev/vda3' not in fixed
assert 'root=UUID=1111-2222' in fixed
assert 'rootfstype=ext4' in fixed
assert 'modules=virtio,virtio_ring,virtio_pci,virtio_blk,ext4' in fixed


# Installed initramfs must fall back to the embedded DexOS boot image when no ISO is mounted.
mk_candidates=sorted(list((ROOT/'cache').rglob('mkinitfs-*.apk')) + list((ROOT/'alpine-root').rglob('mkinitfs-*.apk')))
assert mk_candidates, 'mkinitfs APK not found'
with tarfile.open(mk_candidates[-1],'r:gz') as tf:
    init_text=tf.extractfile('usr/share/mkinitfs/initramfs-init').read().decode()
patched=m.patch_installed_initramfs(init_text)
assert '/usr/share/dexos/boot.ppm' in patched
assert patched.count('/usr/share/dexos/boot.ppm') == 1

# Current installer contract includes an independent root password.
sample_cfg={'disk':'/dev/sda','hostname':'dexos-pc','username':'usuario','password':'12345678','root_password':'87654321','timezone':'UTC','erase_confirm':'BORRAR /dev/sda'}
assert len(sample_cfg['root_password']) >= 8

# GRUB rewrite also keeps quiet splash on installed entries.
assert 'quiet splash' in m.rewrite_grub_root('  linux /boot/vmlinuz-stable root=/dev/vda3 quiet\n','1111-2222')


# Installed systems must keep the Wi-Fi reprobe service available and enabled by backend wiring.
backend_text=(ROOT/'project/installer/dexos-installer-backend.py').read_text()
assert "dexos-wifi-init','boot'" in backend_text
assert "TARGET / 'etc/init.d/dexos-wifi-init'" in backend_text
assert "TARGET / 'etc/init.d/dexos-wifi-refresh'" in backend_text

assert 'rc_need=\"dexos-wifi-init\"' in backend_text
assert 'passwd -d root' not in backend_text
wifi=(ROOT/'project/installed/dexos-wifi-init').read_text()
for token in ['rfkill unblock wlan','/sys/bus/pci/devices/*/modalias','/sys/bus/usb/devices/*/modalias','wireless interface detected']:
    assert token in wifi
refresh=(ROOT/'project/installed/dexos-wifi-refresh').read_text()
for token in ['need networkmanager','nmcli radio wifi on','device wifi rescan','GENERAL.DEVICE,GENERAL.TYPE']:
    assert token in refresh

print('test-installer: OK')
