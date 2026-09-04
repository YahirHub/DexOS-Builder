#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
sh -n "$ROOT/project/mkimage/mkimg.yahxfce.sh"
sh -n "$ROOT/project/mkimage/genapkovl-yahxfce.sh"
cd "$TMP"
"$ROOT/project/mkimage/genapkovl-yahxfce.sh" yah-live
mkdir rootfs; tar -xzf yah-live.apkovl.tar.gz -C rootfs
for s in udev udev-trigger udev-settle; do test -L "rootfs/etc/runlevels/sysinit/$s" || { echo "missing $s"; exit 1; }; done
test -L rootfs/etc/runlevels/default/udev-postmount
test -L rootfs/etc/runlevels/default/dbus
test -L rootfs/etc/runlevels/default/elogind
test -L rootfs/etc/runlevels/default/networkmanager
test -L rootfs/etc/runlevels/default/lightdm
test ! -e rootfs/etc/runlevels/sysinit/mdev
test ! -e rootfs/etc/runlevels/sysinit/hwdrivers
test ! -e rootfs/etc/runlevels/default/acpid
grep -q '^autologin-user=yah$' rootfs/etc/lightdm/lightdm.conf.d/10-yah-live.conf
grep -q 'before lightdm' rootfs/etc/init.d/yah-live-user
grep -qx 'xf86-input-libinput' rootfs/etc/apk/world
grep -qx 'eudev' rootfs/etc/apk/world
echo 'test-config: OK'
