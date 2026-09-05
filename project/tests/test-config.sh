#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
sh -n "$ROOT/project/mkimage/mkimg.yahxfce.sh"
sh -n "$ROOT/project/mkimage/genapkovl-yahxfce.sh"
cd "$TMP"
"$ROOT/project/mkimage/genapkovl-yahxfce.sh" dexos-live
mkdir rootfs; tar -xzf dexos-live.apkovl.tar.gz -C rootfs
tar -tvzf dexos-live.apkovl.tar.gz | awk '$6=="./"{print $1}' | grep -q '^drwxr-xr-x'
for s in udev udev-trigger udev-settle; do test -L "rootfs/etc/runlevels/sysinit/$s" || { echo "missing $s"; exit 1; }; done
test -L rootfs/etc/runlevels/default/udev-postmount
test -L rootfs/etc/runlevels/default/dbus
test -L rootfs/etc/runlevels/default/elogind
test -L rootfs/etc/runlevels/default/networkmanager
test -L rootfs/etc/runlevels/default/lightdm
grep -qx 'evdev' rootfs/etc/modules
test -L rootfs/etc/runlevels/sysinit/modloop
test "$(readlink rootfs/etc/runlevels/sysinit/modloop)" = '/etc/init.d/modloop'
test ! -e rootfs/etc/runlevels/sysinit/mdev
test ! -e rootfs/etc/runlevels/sysinit/hwdrivers
test ! -e rootfs/etc/runlevels/default/acpid
grep -q '^autologin-user=dexos$' rootfs/etc/lightdm/lightdm.conf.d/10-dexos-live.conf
grep -q '^logind-check-graphical=false$' rootfs/etc/lightdm/lightdm.conf.d/10-dexos-live.conf
grep -q 'before lightdm' rootfs/etc/init.d/dexos-live-user
grep -qx 'xf86-input-libinput' rootfs/etc/apk/world
grep -qx 'eudev' rootfs/etc/apk/world

test -L rootfs/etc/runlevels/boot/dexos-splash-keys
grep -q 'need localmount dbus elogind networkmanager dexos-live-user' rootfs/etc/init.d/lightdm
grep -q 'udevadm settle --timeout=15' rootfs/etc/init.d/lightdm
grep -q 'pidof xfce4-session' rootfs/etc/init.d/lightdm
grep -q 'splash_progress 100' rootfs/etc/init.d/lightdm
grep -q 'ESC para volver' rootfs/usr/local/sbin/dexos-splash-keys
grep -q 'initfs_cmdline="\$initfs_cmdline splash"' "$ROOT/project/mkimage/mkimg.yahxfce.sh"

grep -qx 'xsetroot' rootfs/etc/apk/world
grep -q '^display-setup-script=/usr/local/sbin/dexos-xsetup$' rootfs/etc/lightdm/lightdm.conf.d/10-dexos-live.conf
grep -q "xsetroot -solid '#6b2a2e'" rootfs/usr/local/sbin/dexos-xsetup
grep -q 'pidof xfwm4' rootfs/etc/init.d/lightdm
grep -q 'pidof xfdesktop' rootfs/etc/init.d/lightdm
grep -q 'pidof xfce4-panel' rootfs/etc/init.d/lightdm
grep -q '^Exec=/usr/local/bin/dexos-installer$' rootfs/usr/share/applications/dexos-installer.desktop
! grep -q '^Exec=doas ' rootfs/usr/share/applications/dexos-installer.desktop
grep -q -- '--command="doas /usr/local/sbin/dexos-install-root"' rootfs/usr/local/bin/dexos-installer
grep -q '^permit nopass dexos as root cmd /usr/local/sbin/dexos-install-root$' rootfs/etc/doas.d/20-dexos-live.conf
grep -q 'Instalar-DexOS.desktop' rootfs/etc/init.d/dexos-live-user
grep -q '#7a3438' rootfs/etc/skel/.config/gtk-3.0/gtk.css
grep -q '/usr/share/backgrounds/dexos.svg' rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml
echo 'test-config: OK'
