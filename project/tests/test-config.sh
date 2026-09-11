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

grep -q 'initfs_cmdline="modules=loop,squashfs,sd-mod,usb-storage,uas,sr-mod,isofs quiet"' "$ROOT/project/mkimage/mkimg.yahxfce.sh"
! grep -q 'quiet splash' "$ROOT/project/mkimage/mkimg.yahxfce.sh"

grep -qx 'xsetroot' rootfs/etc/apk/world
grep -q '^display-setup-script=/usr/local/sbin/dexos-xsetup$' rootfs/etc/lightdm/lightdm.conf.d/10-dexos-live.conf
grep -q "xsetroot -solid '#000000'" rootfs/usr/local/sbin/dexos-xsetup
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
! grep -q 'last-image' rootfs/usr/local/bin/dexos-apply-theme
! grep -q 'set_backdrop' rootfs/usr/local/bin/dexos-apply-theme
grep -q "xsetroot -solid '#000000'" rootfs/usr/local/bin/dexos-apply-theme

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
test -s rootfs/usr/share/dexos/dexos-wallpaper.png
test ! -e rootfs/usr/share/dexos/boot.jpg
test ! -e rootfs/usr/share/dexos/boot.ppm
test ! -e rootfs/usr/local/bin/dexos-session-splash
test ! -e rootfs/usr/share/dexos/installed/dexos-bootsplash
test ! -e rootfs/usr/share/dexos/installed/dexos-bootsplash-finish
test ! -e rootfs/usr/share/dexos/installed/dexos-splash-keys
test -x rootfs/usr/local/bin/dexos-session
grep -q '^Exec=/usr/local/bin/dexos-session$' rootfs/usr/share/xsessions/dexos.desktop
! grep -q 'dexos-session-splash' rootfs/usr/local/bin/dexos-session


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
grep -q 'Option "AccelSpeed" "0.00"' rootfs/etc/X11/xorg.conf.d/40-dexos-libinput.conf
test -f rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
grep -q 'value="pulseaudio"' rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
grep -q 'name="volume-max" type="uint" value="150"' rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
test -x rootfs/usr/local/bin/dexos-audio-init
test -f rootfs/etc/xdg/autostart/dexos-audio.desktop
grep -q 'alsactl init' rootfs/usr/local/bin/dexos-audio-init
test -f rootfs/usr/share/dexos/argon-grub-theme/theme.txt
test -f rootfs/usr/share/dexos/argon-grub-theme/background.png
test -f rootfs/usr/share/dexos/argon-grub-theme/LICENCE.txt
test -x rootfs/usr/share/dexos/installed/boot-order
test -x rootfs/usr/share/dexos/installed/grub-update
test -x rootfs/usr/share/dexos/installed/grub-other-os
test -x rootfs/usr/share/dexos/installed/05_dexos_theme
test -x rootfs/usr/share/dexos/installed/09_dexos_linux
grep -q "menuentry 'DexOS'" rootfs/usr/share/dexos/installed/09_dexos_linux
grep -q 'emit_efi_loader' rootfs/usr/share/dexos/installed/grub-other-os
grep -q 'Coexistir con Windows / Linux' rootfs/usr/local/bin/dexos-installer
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
grep -q 'Option "AccelSpeed" "0.00"' rootfs/etc/X11/xorg.conf.d/40-dexos-libinput.conf

grep -q 'value="pulseaudio"' rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
grep -q 'name="volume-max" type="uint" value="150"' rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
for p in pipewire pipewire-pulse wireplumber alsa-utils alsa-ucm-conf sof-firmware pavucontrol xfce4-pulseaudio-plugin; do grep -qx "$p" rootfs/etc/apk/world; done
test -x rootfs/usr/local/bin/dexos-audio-init
! grep -q 'wpctl set-volume' rootfs/usr/local/bin/dexos-audio-init
! grep -q 'wpctl set-mute' rootfs/usr/local/bin/dexos-audio-init
grep -q '/var/lib/alsa/asound.state' rootfs/usr/local/bin/dexos-audio-init

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
grep -q 'metadata::xfce-exe-checksum' rootfs/usr/local/bin/dexos-trust-launchers
grep -q 'sha256sum' rootfs/usr/local/bin/dexos-trust-launchers
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
grep -q 'CursorThemeName" type="string" value="DexOS-Windows"' rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml
grep -q 'xsetroot -cursor_name left_ptr' rootfs/usr/local/sbin/dexos-xsetup
! grep -q 'monitor${mon}/workspace0' rootfs/usr/local/bin/dexos-apply-theme
! grep -q 'xfdesktop --reload' rootfs/usr/local/bin/dexos-apply-theme
grep -q 'xfce-perchannel-xml/xfce4-desktop.xml' rootfs/etc/init.d/dexos-live-user
grep -q 'export XCURSOR_THEME=DexOS-Windows' rootfs/usr/local/bin/dexos-session
grep -q 'Gdk.Cursor.new_from_name' rootfs/usr/local/bin/dexos-language


# v006: branding and installer trust are applied independent of XDG autostart.
grep -q '/usr/local/bin/dexos-apply-theme' rootfs/usr/local/bin/dexos-session
grep -q '/usr/local/bin/dexos-trust-launchers' rootfs/usr/local/bin/dexos-session
test ! -e rootfs/usr/share/dexos/installed/patch-initramfs-init.py
grep -q '^cursor-theme-name=DexOS-Windows$' rootfs/etc/lightdm/lightdm-gtk-greeter.conf
! grep -q '~language' rootfs/etc/lightdm/lightdm-gtk-greeter.conf


# v007 wallpaper helper must attach to the real XFCE session bus.
grep -q '/proc/$xpid/environ' rootfs/usr/local/bin/dexos-apply-theme
grep -q 'DBUS_SESSION_BUS_ADDRESS' rootfs/usr/local/bin/dexos-apply-theme
! grep -q 'set_backdrop' rootfs/usr/local/bin/dexos-apply-theme


# v008: wallpaper is prepared before XFCE and XFCE's own fallback is DexOS.
test -x rootfs/usr/local/bin/dexos-prepare-desktop
grep -q 'xrandr --query' rootfs/usr/local/bin/dexos-prepare-desktop
grep -q 'monitor%s' rootfs/usr/local/bin/dexos-prepare-desktop
grep -q '/usr/share/dexos/dexos-wallpaper.png' rootfs/usr/local/bin/dexos-prepare-desktop
grep -q 'dexos-prepare-desktop' rootfs/usr/local/bin/dexos-session
test -L rootfs/usr/share/backgrounds/xfce/xfce-x.svg
[ "$(readlink rootfs/usr/share/backgrounds/xfce/xfce-x.svg)" = '/usr/share/dexos/dexos-wallpaper.png' ]


# v010: Windows-like cursor, visible menu categories, balanced power and desktop utilities.
for p in redshift geoclue geoclue-lang power-profiles-daemon; do grep -qx "$p" rootfs/etc/apk/world; done
test -L rootfs/usr/share/icons/Adwaita-Xfce
[ "$(readlink rootfs/usr/share/icons/Adwaita-Xfce)" = 'adwaita-xfce' ]
test -L rootfs/usr/share/icons/adwaita-xfce/scalable/categories/applications.svg
test -f rootfs/usr/share/icons/DexOS-Windows/index.theme
test -s rootfs/usr/share/icons/DexOS-Windows/cursors/left_ptr
grep -q '^cursor-theme-name=DexOS-Windows$' rootfs/etc/lightdm/lightdm-gtk-greeter.conf
grep -q 'value="DexOS-Windows"' rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml
grep -q 'export XCURSOR_SIZE=32' rootfs/usr/local/bin/dexos-session
test -x rootfs/etc/init.d/dexos-power
test -x rootfs/usr/local/sbin/dexos-power-apply
test -L rootfs/etc/runlevels/default/dexos-power
grep -q 'powerprofilesctl set balanced' rootfs/usr/local/sbin/dexos-power-apply
grep -q 'energy_performance_preference' rootfs/usr/local/sbin/dexos-power-apply
grep -q 'scaling_governor' rootfs/usr/local/sbin/dexos-power-apply
test -x rootfs/usr/local/bin/dexos-eye-protection
test -f rootfs/etc/redshift.conf
grep -q '^adjustment-method=randr$' rootfs/etc/redshift.conf
grep -q '^location-provider=geoclue2$' rootfs/etc/redshift.conf
test -f rootfs/etc/geoclue/conf.d/90-dexos-redshift.conf
grep -q '^\[redshift\]$' rootfs/etc/geoclue/conf.d/90-dexos-redshift.conf
grep -q '^allowed=true$' rootfs/etc/geoclue/conf.d/90-dexos-redshift.conf
grep -q '^Exec=/usr/local/bin/dexos-eye-protection --startup$' rootfs/etc/xdg/autostart/dexos-eye-protection.desktop
! grep -q 'Iniciar protección automáticamente al entrar a DexOS' rootfs/usr/local/bin/dexos-eye-protection
grep -q "if not data\['enabled'\]" rootfs/usr/local/bin/dexos-eye-protection
grep -q 'Ajustar automáticamente (GeoClue2 + respaldo por hora local)' rootfs/usr/local/bin/dexos-eye-protection
test -f rootfs/usr/share/applications/dexos-eye-protection.desktop
test -f rootfs/etc/xdg/autostart/dexos-eye-protection.desktop
grep -q "redshift', '-m', 'randr', '-l', 'geoclue2'" rootfs/usr/local/bin/dexos-eye-protection
test -x rootfs/usr/local/bin/dexos-boot-manager
test -f rootfs/usr/share/applications/dexos-boot-manager.desktop
test -x rootfs/etc/skel/Desktop/Orden-de-arranque.desktop
grep -q 'Escanear discos y actualizar GRUB' rootfs/usr/local/bin/dexos-boot-manager
grep -q "BOOT_ORDER, '--set'" rootfs/usr/local/bin/dexos-boot-manager
grep -q '^    --list)' rootfs/usr/share/dexos/installed/boot-order
grep -q '^    --set)' rootfs/usr/share/dexos/installed/boot-order
grep -q 'INTERVAL=86400' rootfs/etc/init.d/dexos-apk-refresh
! grep -q 'glxinfo -B' rootfs/usr/local/bin/dexos-video-init


# v013: persistent mixer/backlight state and privileged GRUB UI.
grep -qx 'alsa-utils-openrc' rootfs/etc/apk/world
test -L rootfs/etc/runlevels/default/alsa
test -x rootfs/etc/init.d/dexos-backlight
test -L rootfs/etc/runlevels/default/dexos-backlight
grep -q 'STATE_DIR=/var/lib/dexos/backlight' rootfs/etc/init.d/dexos-backlight
grep -q 'save_backlights' rootfs/etc/init.d/dexos-backlight
grep -q 'restore_backlights' rootfs/etc/init.d/dexos-backlight
test -x rootfs/usr/share/dexos/installed/dexos-backlight-state
test -f rootfs/usr/share/polkit-1/actions/org.dexos.boot-manager.policy
test -f rootfs/usr/share/dexos/installed/org.dexos.boot-manager.policy
grep -q 'auth_admin_keep' rootfs/usr/share/polkit-1/actions/org.dexos.boot-manager.policy
grep -q 'org.freedesktop.policykit.exec.allow_gui' rootfs/usr/share/polkit-1/actions/org.dexos.boot-manager.policy
grep -q "ensure_admin()" rootfs/usr/local/bin/dexos-boot-manager
grep -q "os.execv(pkexec" rootfs/usr/local/bin/dexos-boot-manager


# v014: brightness restore regression + offline Redshift fallback.
! grep -q "case \"\$value:\$max\" in" rootfs/etc/init.d/dexos-backlight
grep -Fq 'case "$value" in' rootfs/etc/init.d/dexos-backlight
grep -Fq 'case "$max" in' rootfs/etc/init.d/dexos-backlight
grep -q 'restored \$name=\$value/\$max' rootfs/etc/init.d/dexos-backlight
grep -q 'fallback_temperature' rootfs/usr/local/bin/dexos-eye-protection
grep -q 'internet_available' rootfs/usr/local/bin/dexos-eye-protection
grep -q -- '--auto-daemon' rootfs/usr/local/bin/dexos-eye-protection
grep -q 'Sin Internet/GeoClue2' rootfs/usr/local/bin/dexos-eye-protection
grep -q 'hora local sin conexión' rootfs/usr/local/bin/dexos-eye-protection


# v015: persistent Night Light, user-owned wallpaper, clean boot and Windows-like touchpad.
grep -q 'wallpaper-initialized' rootfs/usr/local/bin/dexos-prepare-desktop
grep -q '\[ -e "\$marker" \] && exit 0' rootfs/usr/local/bin/dexos-prepare-desktop
! grep -q 'last-image' rootfs/usr/local/bin/dexos-apply-theme
! grep -q 'dexos-session-splash' rootfs/usr/local/bin/dexos-session
for opt in \
  'Option "TappingDrag" "on"' \
  'Option "TappingDragLock" "off"' \
  'Option "HorizontalScrolling" "on"' \
  'Option "NaturalScrolling" "off"' \
  'Option "ClickMethod" "buttonareas"' \
  'Option "MiddleEmulation" "off"' \
  'Option "ScrollPixelDistance" "15"'; do
    grep -q "$opt" rootfs/etc/X11/xorg.conf.d/40-dexos-libinput.conf
done
! grep -Rqs 'fbsplash' rootfs/usr/share/dexos rootfs/usr/local/bin 2>/dev/null

echo 'test-config: OK'
