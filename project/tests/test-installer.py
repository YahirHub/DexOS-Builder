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
print('test-installer: OK')
