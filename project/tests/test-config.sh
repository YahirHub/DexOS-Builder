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
for fw in linux-firmware-amdgpu linux-firmware-i915 linux-firmware-intel linux-firmware-realtek linux-firmware-mediatek linux-firmware-ath10k linux-firmware-ath11k linux-firmware-brcm; do grep -qx "$fw" rootfs/etc/apk/world; done
! grep -qx 'linux-firmware-qcom' rootfs/etc/apk/world
! grep -qx 'linux-firmware-mrvl' rootfs/etc/apk/world

test -L rootfs/etc/runlevels/boot/dexos-splash-keys
grep -q 'need localmount dbus elogind networkmanager dexos-live-user' rootfs/etc/init.d/lightdm
grep -q 'udevadm settle --timeout=15' rootfs/etc/init.d/lightdm
grep -q 'pidof xfce4-session' rootfs/usr/local/sbin/dexos-desktop-ready
grep -q 'progress 100' rootfs/usr/local/sbin/dexos-desktop-ready
grep -q 'ESC para volver' rootfs/usr/local/sbin/dexos-splash-keys
grep -q 'initfs_cmdline="modules=loop,squashfs,sd-mod,usb-storage,uas,sr-mod,isofs quiet splash"' "$ROOT/project/mkimage/mkimg.yahxfce.sh"

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
grep -q '/usr/share/dexos/dexos-wallpaper.png' rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml
grep -q '^NAME="DexOS"$' rootfs/etc/os-release
grep -q '^PRETTY_NAME="DexOS Live"$' rootfs/etc/os-release
grep -q '^DexOS Live$' rootfs/etc/issue
grep -q '^Welcome to DexOS Live$' rootfs/etc/motd
test -f rootfs/etc/xdg/autostart/dexos-branding.desktop
grep -q '^Exec=/usr/local/bin/dexos-apply-theme$' rootfs/etc/xdg/autostart/dexos-branding.desktop
grep -q "wall=/usr/share/dexos/dexos-wallpaper.png" rootfs/usr/local/bin/dexos-apply-theme
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
grep -q '^background=/usr/share/dexos/dexos-wallpaper.png$' rootfs/etc/lightdm/lightdm-gtk-greeter.conf
test -s rootfs/usr/share/dexos/boot.jpg
test -s rootfs/usr/share/dexos/boot.ppm
test -s rootfs/usr/share/dexos/dexos-wallpaper.png
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

# v003 desktop, audio, repositories and dualboot resources.
grep -qx 'https://dl-cdn.alpinelinux.org/alpine/edge/main' rootfs/etc/apk/repositories
grep -qx 'https://dl-cdn.alpinelinux.org/alpine/edge/community' rootfs/etc/apk/repositories
grep -qx 'gparted' rootfs/etc/apk/world
grep -qx 'os-prober' rootfs/etc/apk/world
grep -qx 'ntfs-3g' rootfs/etc/apk/world
grep -qx 'alsa-ucm-conf' rootfs/etc/apk/world
grep -qx 'sof-firmware' rootfs/etc/apk/world
test -f rootfs/etc/X11/xorg.conf.d/40-dexos-libinput.conf
grep -q 'Option "Tapping" "on"' rootfs/etc/X11/xorg.conf.d/40-dexos-libinput.conf
grep -q 'Option "AccelProfile" "adaptive"' rootfs/etc/X11/xorg.conf.d/40-dexos-libinput.conf
grep -q 'Option "AccelSpeed" "0.20"' rootfs/etc/X11/xorg.conf.d/40-dexos-libinput.conf
test -f rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
grep -q 'value="pulseaudio"' rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
grep -q 'name="volume-max" type="uint" value="150"' rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
test -x rootfs/usr/local/bin/dexos-audio-init
test -f rootfs/etc/xdg/autostart/dexos-audio.desktop
grep -q 'alsactl init' rootfs/usr/local/bin/dexos-audio-init
test -f rootfs/usr/share/dexos/argon-grub-theme/theme.txt
test -f rootfs/usr/share/dexos/argon-grub-theme/background.png
test -f rootfs/usr/share/dexos/argon-grub-theme/LICENCE.txt
grep -q 'Instalar junto a Windows' rootfs/usr/local/bin/dexos-installer
grep -q 'Abrir GParted' rootfs/usr/local/bin/dexos-installer
grep -q 'GRUB_DISABLE_OS_PROBER=false' rootfs/usr/local/libexec/dexos-installer-backend

# v003 repositories, input, audio and installer tooling.
grep -qx 'https://dl-cdn.alpinelinux.org/alpine/edge/main' rootfs/etc/apk/repositories
grep -qx 'https://dl-cdn.alpinelinux.org/alpine/edge/community' rootfs/etc/apk/repositories
grep -qx '@testing https://dl-cdn.alpinelinux.org/alpine/edge/testing' rootfs/etc/apk/repositories
test -x rootfs/etc/init.d/dexos-apk-refresh
test -L rootfs/etc/runlevels/default/dexos-apk-refresh
grep -q 'apk update' rootfs/etc/init.d/dexos-apk-refresh

grep -q 'Option "Tapping" "on"' rootfs/etc/X11/xorg.conf.d/40-dexos-libinput.conf
grep -q 'Option "TappingButtonMap" "lrm"' rootfs/etc/X11/xorg.conf.d/40-dexos-libinput.conf
grep -q 'Option "DisableWhileTyping" "on"' rootfs/etc/X11/xorg.conf.d/40-dexos-libinput.conf
grep -q 'Option "AccelProfile" "adaptive"' rootfs/etc/X11/xorg.conf.d/40-dexos-libinput.conf
grep -q 'Option "AccelSpeed" "0.20"' rootfs/etc/X11/xorg.conf.d/40-dexos-libinput.conf

grep -q 'value="pulseaudio"' rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
grep -q 'name="volume-max" type="uint" value="150"' rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
for p in pipewire pipewire-pulse wireplumber alsa-utils alsa-ucm-conf sof-firmware pavucontrol xfce4-pulseaudio-plugin; do grep -qx "$p" rootfs/etc/apk/world; done
test -x rootfs/usr/local/bin/dexos-audio-init
grep -q 'wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0' rootfs/usr/local/bin/dexos-audio-init

for p in gparted os-prober ntfs-3g ntfs-3g-progs; do grep -qx "$p" rootfs/etc/apk/world; done
test -f rootfs/usr/share/dexos/argon-grub-theme/theme.txt
test -f rootfs/usr/share/dexos/argon-grub-theme/background.png
test -f rootfs/usr/share/dexos/argon-grub-theme/icons/windows.png
test -f rootfs/usr/share/dexos/argon-grub-theme/icons/linux.png


# v004 video acceleration / tear-free compositor.
for p in mesa-va-gallium mesa-utils libva-utils intel-media-driver libva-intel-driver vulkan-loader mesa-vulkan-ati mesa-vulkan-intel libva-vdpau-driver libvdpau vdpauinfo ffmpeg gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav; do grep -qx "$p" rootfs/etc/apk/world; done
test -f rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
grep -q 'name="use_compositing" type="bool" value="true"' rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
grep -q 'name="vblank_mode" type="string" value="xpresent"' rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
test -x rootfs/usr/local/bin/dexos-video-init
grep -q 'TearFree on' rootfs/usr/local/bin/dexos-video-init
test -f rootfs/etc/xdg/autostart/dexos-video.desktop

# v004 complete GParted filesystem tooling.
for p in exfatprogs btrfs-progs xfsprogs f2fs-tools nilfs-utils jfsutils udftools lvm2 mdadm cryptsetup e2fsprogs-extra; do grep -qx "$p" rootfs/etc/apk/world; done

# v004 trusted desktop installer launcher.
test -x rootfs/usr/local/bin/dexos-trust-launchers
grep -q 'metadata::trusted true' rootfs/usr/local/bin/dexos-trust-launchers
test -f rootfs/etc/xdg/autostart/dexos-trust-launchers.desktop
grep -q 'install -m 0755 /usr/share/applications/dexos-installer.desktop' rootfs/etc/init.d/dexos-live-user

# v004 multilingual Live.
for p in musl-locales musl-locales-lang gettext-lang libxfce4ui-lang libxfce4util-lang xfce4-panel-lang xfce4-session-lang xfce4-settings-lang xfce4-terminal-lang thunar-lang xfdesktop-lang xfwm4-lang lightdm-lang lightdm-gtk-greeter-lang; do grep -qx "$p" rootfs/etc/apk/world; done
test -x rootfs/usr/local/bin/dexos-language
grep -q 'es_ES.UTF-8' rootfs/usr/local/bin/dexos-language
grep -q 'en_US.UTF-8' rootfs/usr/local/bin/dexos-language
grep -q 'pt_BR.UTF-8' rootfs/usr/local/bin/dexos-language
grep -q 'fr_FR.UTF-8' rootfs/usr/local/bin/dexos-language
grep -q 'de_DE.UTF-8' rootfs/usr/local/bin/dexos-language
grep -q 'it_IT.UTF-8' rootfs/usr/local/bin/dexos-language
grep -q '/usr/local/bin/dexos-language' rootfs/usr/local/bin/dexos-session
grep -q 'export LANG=' rootfs/usr/local/bin/dexos-session


test -s rootfs/usr/share/dexos/dexos-wallpaper.png
test -s rootfs/usr/share/backgrounds/xfce/DexOS.png
test -s rootfs/usr/share/xfce4/backdrops/DexOS.png
cmp -s rootfs/usr/share/dexos/dexos-wallpaper.png rootfs/usr/share/backgrounds/xfce/DexOS.png
cmp -s rootfs/usr/share/dexos/dexos-wallpaper.png rootfs/usr/share/xfce4/backdrops/DexOS.png
grep -qx 'breeze-cursors' rootfs/etc/apk/world
grep -q 'CursorThemeName" type="string" value="Breeze"' rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml
grep -q 'xsetroot -cursor_name left_ptr' rootfs/usr/local/sbin/dexos-xsetup
grep -q 'monitor${mon}/workspace0' rootfs/usr/local/bin/dexos-apply-theme
grep -q 'xfdesktop --reload' rootfs/usr/local/bin/dexos-apply-theme
grep -q 'xfce-perchannel-xml/xfce4-desktop.xml' rootfs/etc/init.d/dexos-live-user
grep -q 'export XCURSOR_THEME=Breeze' rootfs/usr/local/bin/dexos-session
grep -q 'Gdk.Cursor.new_from_name' rootfs/usr/local/bin/dexos-language

echo 'test-config: OK'
