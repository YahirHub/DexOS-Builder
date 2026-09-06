#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
sh -n "$ROOT/project/mkimage/mkimg.yahxfce.sh"
sh -n "$ROOT/project/mkimage/genapkovl-yahxfce.sh"
cd "$TMP"
DEXOS_WALLPAPER_ASSET="$ROOT/project/assets/dexos-wallpaper.jpg" "$ROOT/project/mkimage/genapkovl-yahxfce.sh" dexos-live
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
for fw in linux-firmware-intel linux-firmware-realtek linux-firmware-mediatek linux-firmware-ath10k linux-firmware-ath11k linux-firmware-brcm linux-firmware-qcom; do grep -qx "$fw" rootfs/etc/apk/world; done

test -L rootfs/etc/runlevels/boot/dexos-splash-keys
grep -q 'need localmount dbus elogind networkmanager dexos-live-user' rootfs/etc/init.d/lightdm
grep -q 'udevadm settle --timeout=15' rootfs/etc/init.d/lightdm
grep -q 'pidof xfce4-session' rootfs/usr/local/sbin/dexos-desktop-ready
grep -q 'progress 100' rootfs/usr/local/sbin/dexos-desktop-ready
grep -q 'ESC para volver' rootfs/usr/local/sbin/dexos-splash-keys
grep -q 'initfs_cmdline="\$initfs_cmdline splash"' "$ROOT/project/mkimage/mkimg.yahxfce.sh"

grep -qx 'xsetroot' rootfs/etc/apk/world
grep -q '^display-setup-script=/usr/local/sbin/dexos-xsetup$' rootfs/etc/lightdm/lightdm.conf.d/10-dexos-live.conf
grep -q "xsetroot -solid '#6b2a2e'" rootfs/usr/local/sbin/dexos-xsetup
grep -q 'nohup /usr/local/sbin/dexos-desktop-ready' rootfs/etc/init.d/lightdm
grep -q 'return 0' rootfs/etc/init.d/lightdm
grep -q 'pidof xfwm4' rootfs/usr/local/sbin/dexos-desktop-ready
grep -q 'pidof xfdesktop' rootfs/usr/local/sbin/dexos-desktop-ready
grep -q 'pidof xfce4-panel' rootfs/usr/local/sbin/dexos-desktop-ready
grep -q '\[ "\$i" -lt 720 \]' rootfs/usr/local/sbin/dexos-desktop-ready
grep -q '^Exec=/usr/local/bin/dexos-installer$' rootfs/usr/share/applications/dexos-installer.desktop
grep -q '^TryExec=/usr/local/bin/dexos-installer$' rootfs/usr/share/applications/dexos-installer.desktop
grep -q '^Terminal=false$' rootfs/usr/share/applications/dexos-installer.desktop
grep -q '^permit nopass dexos as root$' rootfs/etc/doas.d/20-dexos-live.conf
test -x rootfs/usr/local/bin/dexos-installer
test -x rootfs/usr/local/libexec/dexos-installer-backend
test -s rootfs/usr/share/dexos/installer-packages.txt
grep -q 'Gtk.Assistant' rootfs/usr/local/bin/dexos-installer
grep -q 'BORRAR ' rootfs/usr/local/libexec/dexos-installer-backend
grep -q 'setup-alpine' rootfs/usr/local/libexec/dexos-installer-backend && exit 1 || true
grep -qx 'python3' rootfs/etc/apk/world
grep -qx 'py3-gobject3' rootfs/etc/apk/world
grep -q 'Instalar-DexOS.desktop' rootfs/etc/init.d/dexos-live-user
grep -q '#7a3438' rootfs/etc/skel/.config/gtk-3.0/gtk.css
grep -q '/usr/share/dexos/wallpaper' rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml
grep -q '^NAME="DexOS"$' rootfs/etc/os-release
grep -q '^PRETTY_NAME="DexOS Live"$' rootfs/etc/os-release
grep -q '^DexOS Live$' rootfs/etc/issue
grep -q '^Welcome to DexOS Live$' rootfs/etc/motd
test -f rootfs/etc/xdg/autostart/dexos-branding.desktop
grep -q '^Exec=/usr/local/bin/dexos-apply-theme$' rootfs/etc/xdg/autostart/dexos-branding.desktop
grep -q "wall=/usr/share/dexos/wallpaper" rootfs/usr/local/bin/dexos-apply-theme
grep -q "grep '/last-image\$'" rootfs/usr/local/bin/dexos-apply-theme
grep -q "xsetroot -solid '#6b2a2e'" rootfs/usr/local/bin/dexos-apply-theme

# DexOS UX/runtime additions.
grep -qx 'sudo' rootfs/etc/apk/world
grep -qx 'bash' rootfs/etc/apk/world
grep -qx 'firefox' rootfs/etc/apk/world
grep -qx 'chrony' rootfs/etc/apk/world
grep -qx 'chrony-openrc' rootfs/etc/apk/world
test -L rootfs/etc/runlevels/boot/swclock
test ! -e rootfs/etc/runlevels/boot/hwclock
test -L rootfs/etc/runlevels/default/chronyd
grep -q 'adduser -D -h /home/dexos -s /bin/bash dexos' rootfs/etc/init.d/dexos-live-user
grep -q 'passwd -d root' rootfs/etc/init.d/dexos-live-user
test -x rootfs/usr/local/bin/su
grep -q 'exec /usr/bin/doas /bin/bash -l' rootfs/usr/local/bin/su
grep -q '^permit nopass dexos as root$' rootfs/etc/doas.d/20-dexos-live.conf
grep -q '^user-session=dexos$' rootfs/etc/lightdm/lightdm.conf.d/10-dexos-live.conf
grep -q '^autologin-session=dexos$' rootfs/etc/lightdm/lightdm.conf.d/10-dexos-live.conf
grep -q '^background=/usr/share/dexos/wallpaper$' rootfs/etc/lightdm/lightdm-gtk-greeter.conf
test -s rootfs/usr/share/dexos/boot.jpg
test -s rootfs/usr/share/dexos/boot.ppm
test -s rootfs/usr/share/dexos/wallpaper
head -c 2 rootfs/usr/share/dexos/boot.ppm | grep -q '^P6$'
test -x rootfs/usr/local/bin/dexos-session-splash
test -x rootfs/usr/local/bin/dexos-session
grep -q '^Exec=/usr/local/bin/dexos-session$' rootfs/usr/share/xsessions/dexos.desktop
grep -q 'pidof.*xfce4-panel' rootfs/usr/local/bin/dexos-session-splash || grep -q "alive('xfce4-panel')" rootfs/usr/local/bin/dexos-session-splash
test -x rootfs/usr/share/dexos/installed/dexos-bootsplash
test -x rootfs/usr/share/dexos/installed/dexos-bootsplash-finish
test -x rootfs/usr/share/dexos/installed/dexos-splash-keys


# Wi-Fi reprobe service: unblocks radio, resolves modaliases and notifies NetworkManager.
test -x rootfs/etc/init.d/dexos-wifi-init
test -L rootfs/etc/runlevels/boot/dexos-wifi-init
grep -q 'rfkill unblock wlan' rootfs/etc/init.d/dexos-wifi-init
grep -q '^rc_need="dexos-wifi-init"$' rootfs/etc/conf.d/networkmanager
grep -q '/sys/bus/pci/devices/\*/modalias' rootfs/etc/init.d/dexos-wifi-init
grep -q '/sys/bus/usb/devices/\*/modalias' rootfs/etc/init.d/dexos-wifi-init
grep -q 'udevadm trigger --action=add --subsystem-match=net' rootfs/etc/init.d/dexos-wifi-init
test -x rootfs/etc/init.d/dexos-wifi-refresh
test -L rootfs/etc/runlevels/default/dexos-wifi-refresh
grep -q 'need networkmanager' rootfs/etc/init.d/dexos-wifi-refresh
grep -q 'nmcli radio wifi on' rootfs/etc/init.d/dexos-wifi-refresh
grep -q 'device wifi rescan' rootfs/etc/init.d/dexos-wifi-refresh
test -x rootfs/usr/share/dexos/installed/dexos-wifi-init

echo 'test-config: OK'
