#!/bin/sh -e
HOSTNAME="${1:-dexos-live}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
INSTALLER_ASSETS="$SCRIPT_DIR"
[ -f "$INSTALLER_ASSETS/dexos-installer.py" ] || INSTALLER_ASSETS="$SCRIPT_DIR/../installer"
BRAND_ASSETS="$SCRIPT_DIR"
[ -f "$BRAND_ASSETS/argon-grub-theme/theme.txt" ] || BRAND_ASSETS="$SCRIPT_DIR/../assets"
SYSTEM_ASSETS="$SCRIPT_DIR"
[ -f "$SYSTEM_ASSETS/dexos-session" ] || SYSTEM_ASSETS="$SCRIPT_DIR/../installed"
for f in dexos-installer.py dexos-installer-backend.py installer-packages.txt; do
    [ -f "$INSTALLER_ASSETS/$f" ] || { echo "Falta recurso del instalador: $f" >&2; exit 1; }
done
WALLPAPER_ASSET="${DEXOS_WALLPAPER_ASSET:-}"
if [ -n "$WALLPAPER_ASSET" ] && [ ! -s "$WALLPAPER_ASSET" ]; then
    echo "Wallpaper indicado no existe: $WALLPAPER_ASSET" >&2
    exit 1
fi
if [ -z "$WALLPAPER_ASSET" ]; then
    for candidate in         "$BRAND_ASSETS/dexos-wallpaper-user"         "$BRAND_ASSETS/dexos-wallpaper-user.png"         "$BRAND_ASSETS/dexos-wallpaper-user.jpg"         "$BRAND_ASSETS/dexos-wallpaper-user.jpeg"         "$BRAND_ASSETS/dexos-wallpaper"; do
        if [ -s "$candidate" ]; then WALLPAPER_ASSET="$candidate"; break; fi
    done
fi
[ -n "$WALLPAPER_ASSET" ] || { echo "Falta recurso visual de wallpaper exacto" >&2; exit 1; }
ARGON_ASSET="$BRAND_ASSETS/argon-grub-theme"
[ -f "$ARGON_ASSET/theme.txt" ] || { echo "Falta tema Argon precompilado" >&2; exit 1; }
CURSOR_ASSET="$BRAND_ASSETS/dexos-windows-cursor"
[ -f "$CURSOR_ASSET/index.theme" ] && [ -f "$CURSOR_ASSET/cursors/left_ptr" ] || { echo "Falta tema de cursor DexOS-Windows" >&2; exit 1; }
for f in dexos-session dexos-wifi-init dexos-wifi-refresh dexos-audio-init dexos-apk-refresh dexos-language.py dexos-trust-launchers dexos-video-init dexos-prepare-desktop dexos-boot-manager.py dexos-eye-protection.py dexos-power-init dexos-power-apply dexos-backlight-state org.dexos.boot-manager.policy boot-order grub-update grub-other-os 05_dexos_theme 09_dexos_linux; do
    [ -f "$SYSTEM_ASSETS/$f" ] || { echo "Falta recurso del sistema: $f" >&2; exit 1; }
done
tmp="$(mktemp -d)"
chmod 0755 "$tmp"
trap 'rm -rf "$tmp"' EXIT
makefile(){ owner="$1"; perms="$2"; path="$3"; mkdir -p "$(dirname "$path")"; cat >"$path"; chown "$owner" "$path"; chmod "$perms" "$path"; }
rc_add(){ mkdir -p "$tmp/etc/runlevels/$2"; ln -sf "/etc/init.d/$1" "$tmp/etc/runlevels/$2/$1"; }

mkdir -p "$tmp/etc/apk" "$tmp/etc/network" "$tmp/etc/NetworkManager/conf.d"
makefile root:root 0644 "$tmp/etc/hostname" <<EOF_HOST
$HOSTNAME
EOF_HOST
makefile root:root 0644 "$tmp/etc/os-release" <<'EOF_OS_RELEASE'
NAME="DexOS"
PRETTY_NAME="DexOS Live"
ID=dexos
ID_LIKE=alpine
VERSION_ID=edge
VERSION="Live"
HOME_URL="https://alpinelinux.org/"
EOF_OS_RELEASE
makefile root:root 0644 "$tmp/etc/issue" <<'EOF_ISSUE'
DexOS Live
Kernel \r on \m (\l)
EOF_ISSUE
makefile root:root 0644 "$tmp/etc/motd" <<'EOF_MOTD'
Welcome to DexOS Live
EOF_MOTD
makefile root:root 0644 "$tmp/etc/hosts" <<EOF_HOSTS
127.0.0.1 localhost localhost.localdomain $HOSTNAME
::1 localhost localhost.localdomain $HOSTNAME
EOF_HOSTS

makefile root:root 0644 "$tmp/etc/apk/repositories" <<'EOF_APK_REPOS'
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
@testing https://dl-cdn.alpinelinux.org/alpine/edge/testing
EOF_APK_REPOS

makefile root:root 0644 "$tmp/etc/apk/world" <<'EOF_WORLD'
alpine-base
alpine-conf
doas
sudo
bash
shadow
python3
py3-gobject3
dbus
dbus-x11
dbus-openrc
eudev
eudev-openrc
udev-init-scripts
udev-init-scripts-openrc
elogind
elogind-openrc
polkit-elogind
polkit-common
xorg-server
xinit
xsetroot
xf86-input-libinput
xf86-video-vesa
xf86-video-vmware
xf86-video-qxl
xf86-video-amdgpu
mesa-dri-gallium
mesa-gl
mesa-va-gallium
mesa-utils
libva-utils
intel-media-driver
libva-intel-driver
vulkan-loader
mesa-vulkan-ati
mesa-vulkan-intel
libva-vdpau-driver
libvdpau
vdpauinfo
ffmpeg
gst-plugins-good
gst-plugins-bad
gst-plugins-ugly
gst-libav
xfce4
xfce4-terminal
xfce4-screensaver
xfce4-whiskermenu-plugin
xfce4-power-manager
xfce4-battery-plugin
xfce4-pulseaudio-plugin
xfce4-notifyd
xfce4-taskmanager
xfce4-screenshooter
lightdm
lightdm-openrc
lightdm-gtk-greeter
font-dejavu
font-noto
adw-gtk3
adwaita-xfce-icon-theme
breeze-cursors
xfce-polkit
redshift
geoclue
geoclue-lang
power-profiles-daemon
musl-locales
musl-locales-lang
gettext-lang
libxfce4ui-lang
libxfce4util-lang
libxfce4windowing-lang
xfce4-appfinder-lang
xfce4-panel-lang
xfce4-session-lang
xfce4-settings-lang
xfce4-terminal-lang
thunar-lang
xfdesktop-lang
xfwm4-lang
xfce4-power-manager-lang
xfce4-pulseaudio-plugin-lang
xfce4-notifyd-lang
xfce4-screensaver-lang
xfce4-whiskermenu-plugin-lang
xfce4-taskmanager-lang
xfce4-screenshooter-lang
lightdm-lang
lightdm-gtk-greeter-lang
thunar-volman-lang
garcon-lang
exo-lang
tumbler-lang
gvfs
udisks2
thunar-volman
tumbler
networkmanager
networkmanager-openrc
networkmanager-wifi
networkmanager-cli
network-manager-applet
iw
util-linux-misc
wireless-tools
wpa_supplicant
wireless-regdb
linux-firmware-amd
linux-firmware-amdgpu
linux-firmware-i915
linux-firmware-xe
linux-firmware-intel
linux-firmware-nvidia
linux-firmware-realtek
linux-firmware-rtlwifi
linux-firmware-rtw88
linux-firmware-rtw89
linux-firmware-mediatek
linux-firmware-ath6k
linux-firmware-ath9k_htc
linux-firmware-ath10k
linux-firmware-ath11k
linux-firmware-ath12k
linux-firmware-brcm
linux-firmware-cypress
linux-firmware-qca
linux-firmware-mwl8k
linux-firmware-mwlwifi
linux-firmware-libertas
linux-firmware-ti-connectivity
linux-firmware-rsi
linux-firmware-wfx
sof-firmware
bluez
bluez-openrc
pipewire
pipewire-pulse
pipewire-alsa
wireplumber
alsa-utils
alsa-utils-openrc
alsa-ucm-conf
sof-firmware
pavucontrol
upower
brightnessctl
util-linux
sfdisk
dosfstools
e2fsprogs
efibootmgr
grub-bios
grub-efi
syslinux
parted
gparted
os-prober
ntfs-3g
ntfs-3g-progs
exfatprogs
btrfs-progs
xfsprogs
f2fs-tools
nilfs-utils
jfsutils
udftools
lvm2
mdadm
cryptsetup
e2fsprogs-extra
mtools
pciutils
usbutils
tzdata
ca-certificates
curl
chrony
chrony-openrc
firefox
EOF_WORLD

# evdev crea /dev/input/event*; Xorg/libinput depende de estos nodos.
makefile root:root 0644 "$tmp/etc/modules" <<'EOF_MODULES'
evdev
EOF_MODULES

makefile root:root 0644 "$tmp/etc/network/interfaces" <<'EOF_NET'
auto lo
iface lo inet loopback
EOF_NET
makefile root:root 0644 "$tmp/etc/redshift.conf" <<'EOF_REDSHIFT'
[redshift]
adjustment-method=randr
location-provider=geoclue2
temp-day=6500
temp-night=4500
transition=0
EOF_REDSHIFT

mkdir -p "$tmp/etc/geoclue/conf.d"
makefile root:root 0644 "$tmp/etc/geoclue/conf.d/90-dexos-redshift.conf" <<'EOF_GEOCLUE_REDSHIFT'
[redshift]
allowed=true
system=false
users=
EOF_GEOCLUE_REDSHIFT
makefile root:root 0644 "$tmp/etc/NetworkManager/NetworkManager.conf" <<'EOF_NM'
[main]
dhcp=internal
plugins=ifupdown,keyfile

[ifupdown]
managed=true

[device]
wifi.backend=wpa_supplicant
wifi.scan-rand-mac-address=yes
EOF_NM
makefile root:root 0644 "$tmp/etc/NetworkManager/conf.d/10-dexos-live.conf" <<'EOF_NMC'
[connection]
wifi.powersave=2
EOF_NMC

makefile root:root 0644 "$tmp/etc/conf.d/networkmanager" <<'EOF_NM_OPENRC'
# Do not let NetworkManager start until DexOS has completed its hardware probe.
rc_need="dexos-wifi-init"
EOF_NM_OPENRC


# Session Live: user normal + elogind + LightDM. Nunca se inicia XFCE como root.
mkdir -p "$tmp/etc/lightdm/lightdm.conf.d"
makefile root:root 0644 "$tmp/etc/lightdm/lightdm.conf.d/10-dexos-live.conf" <<'EOF_LDM'
[LightDM]
logind-check-graphical=false

[Seat:*]
display-setup-script=/usr/local/sbin/dexos-xsetup
greeter-session=lightdm-gtk-greeter
user-session=dexos
autologin-user=dexos
autologin-user-timeout=0
autologin-session=dexos
EOF_LDM
makefile root:root 0644 "$tmp/etc/lightdm/lightdm-gtk-greeter.conf" <<'EOF_GREETER'
[greeter]
background=/usr/share/dexos/dexos-wallpaper.png
theme-name=adw-gtk3-dark
icon-theme-name=Adwaita-Xfce
cursor-theme-name=DexOS-Windows
cursor-theme-size=32
font-name=DejaVu Sans 11
clock-format=%A %d de %B  %H:%M
indicators=~host;~spacer;~clock;~spacer;~session;~a11y;~power
user-background=false
EOF_GREETER

mkdir -p "$tmp/usr/share/dexos" "$tmp/usr/share/xsessions" "$tmp/usr/local/bin" "$tmp/usr/local/sbin" "$tmp/etc/init.d" "$tmp/usr/share/backgrounds/xfce" "$tmp/usr/share/xfce4/backdrops"
install -m 0644 "$WALLPAPER_ASSET" "$tmp/usr/share/dexos/dexos-wallpaper.png"
install -m 0644 "$WALLPAPER_ASSET" "$tmp/usr/share/backgrounds/xfce/DexOS.png"
install -m 0644 "$WALLPAPER_ASSET" "$tmp/usr/share/xfce4/backdrops/DexOS.png"
mkdir -p "$tmp/usr/share/icons/DexOS-Windows"
cp -a "$CURSOR_ASSET/." "$tmp/usr/share/icons/DexOS-Windows/"
mkdir -p "$tmp/usr/share/icons"
ln -sfn adwaita-xfce "$tmp/usr/share/icons/Adwaita-Xfce"
mkdir -p "$tmp/usr/share/icons/adwaita-xfce/scalable/categories"
ln -sfn applications-other.svg "$tmp/usr/share/icons/adwaita-xfce/scalable/categories/applications.svg"
install -m 0755 "$SYSTEM_ASSETS/dexos-session" "$tmp/usr/local/bin/dexos-session"
mkdir -p "$tmp/usr/share/dexos/installed"
install -m 0755 "$SYSTEM_ASSETS/dexos-wifi-init" "$tmp/usr/share/dexos/installed/dexos-wifi-init"
install -m 0755 "$SYSTEM_ASSETS/dexos-wifi-init" "$tmp/etc/init.d/dexos-wifi-init"
install -m 0755 "$SYSTEM_ASSETS/dexos-wifi-refresh" "$tmp/usr/share/dexos/installed/dexos-wifi-refresh"
install -m 0755 "$SYSTEM_ASSETS/dexos-wifi-refresh" "$tmp/etc/init.d/dexos-wifi-refresh"
install -m 0755 "$SYSTEM_ASSETS/dexos-audio-init" "$tmp/usr/local/bin/dexos-audio-init"
install -m 0755 "$SYSTEM_ASSETS/dexos-audio-init" "$tmp/usr/share/dexos/installed/dexos-audio-init"
install -m 0755 "$SYSTEM_ASSETS/dexos-apk-refresh" "$tmp/usr/share/dexos/installed/dexos-apk-refresh"
install -m 0755 "$SYSTEM_ASSETS/dexos-apk-refresh" "$tmp/etc/init.d/dexos-apk-refresh"
install -m 0755 "$SYSTEM_ASSETS/dexos-language.py" "$tmp/usr/local/bin/dexos-language"
install -m 0755 "$SYSTEM_ASSETS/dexos-language.py" "$tmp/usr/share/dexos/installed/dexos-language"
install -m 0755 "$SYSTEM_ASSETS/dexos-trust-launchers" "$tmp/usr/local/bin/dexos-trust-launchers"
install -m 0755 "$SYSTEM_ASSETS/dexos-video-init" "$tmp/usr/local/bin/dexos-video-init"
install -m 0755 "$SYSTEM_ASSETS/dexos-video-init" "$tmp/usr/share/dexos/installed/dexos-video-init"
install -m 0755 "$SYSTEM_ASSETS/dexos-prepare-desktop" "$tmp/usr/local/bin/dexos-prepare-desktop"
install -m 0755 "$SYSTEM_ASSETS/dexos-prepare-desktop" "$tmp/usr/share/dexos/installed/dexos-prepare-desktop"
install -m 0755 "$SYSTEM_ASSETS/dexos-boot-manager.py" "$tmp/usr/local/bin/dexos-boot-manager"
install -m 0755 "$SYSTEM_ASSETS/dexos-boot-manager.py" "$tmp/usr/share/dexos/installed/dexos-boot-manager.py"
install -m 0755 "$SYSTEM_ASSETS/dexos-eye-protection.py" "$tmp/usr/local/bin/dexos-eye-protection"
install -m 0755 "$SYSTEM_ASSETS/dexos-eye-protection.py" "$tmp/usr/share/dexos/installed/dexos-eye-protection.py"
install -m 0755 "$SYSTEM_ASSETS/dexos-power-init" "$tmp/etc/init.d/dexos-power"
install -m 0755 "$SYSTEM_ASSETS/dexos-power-init" "$tmp/usr/share/dexos/installed/dexos-power-init"
install -m 0755 "$SYSTEM_ASSETS/dexos-power-apply" "$tmp/usr/local/sbin/dexos-power-apply"
install -m 0755 "$SYSTEM_ASSETS/dexos-power-apply" "$tmp/usr/share/dexos/installed/dexos-power-apply"
install -m 0755 "$SYSTEM_ASSETS/dexos-backlight-state" "$tmp/etc/init.d/dexos-backlight"
install -m 0755 "$SYSTEM_ASSETS/dexos-backlight-state" "$tmp/usr/share/dexos/installed/dexos-backlight-state"
mkdir -p "$tmp/usr/share/polkit-1/actions"
install -m 0644 "$SYSTEM_ASSETS/org.dexos.boot-manager.policy" "$tmp/usr/share/polkit-1/actions/org.dexos.boot-manager.policy"
install -m 0644 "$SYSTEM_ASSETS/org.dexos.boot-manager.policy" "$tmp/usr/share/dexos/installed/org.dexos.boot-manager.policy"
install -m 0755 "$SYSTEM_ASSETS/boot-order" "$tmp/usr/share/dexos/installed/boot-order"
install -m 0755 "$SYSTEM_ASSETS/grub-update" "$tmp/usr/share/dexos/installed/grub-update"
install -m 0755 "$SYSTEM_ASSETS/grub-other-os" "$tmp/usr/share/dexos/installed/grub-other-os"
install -m 0755 "$SYSTEM_ASSETS/05_dexos_theme" "$tmp/usr/share/dexos/installed/05_dexos_theme"
install -m 0755 "$SYSTEM_ASSETS/09_dexos_linux" "$tmp/usr/share/dexos/installed/09_dexos_linux"
# XFCE 4.20 falls back to xfce-x.svg on a fresh channel. Overlay that exact
# path with DexOS so even an internal first-run reset cannot show XFCE artwork.
ln -sf /usr/share/dexos/dexos-wallpaper.png "$tmp/usr/share/backgrounds/xfce/xfce-x.svg"
makefile root:root 0644 "$tmp/usr/share/xsessions/dexos.desktop" <<'EOF_DEXOS_SESSION'
[Desktop Entry]
Name=DexOS
Comment=DexOS XFCE Session
Exec=/usr/local/bin/dexos-session
TryExec=/usr/local/bin/dexos-session
Type=Application
DesktopNames=XFCE
EOF_DEXOS_SESSION

# Keep the pre-desktop X root neutral; the wallpaper appears when XFCE starts.
makefile root:root 0755 "$tmp/usr/local/sbin/dexos-xsetup" <<'EOF_XSETUP'
#!/bin/sh
/usr/bin/xsetroot -solid '#000000' || true
/usr/bin/xsetroot -cursor_name left_ptr 2>/dev/null || true
exit 0
EOF_XSETUP

mkdir -p "$tmp/etc/skel/.config/gtk-3.0"
makefile root:root 0644 "$tmp/etc/skel/.config/gtk-3.0/gtk.css" <<'EOF_GTKCSS'
@define-color theme_selected_bg_color #7a3438;
@define-color theme_selected_fg_color #f7eeee;
@define-color accent_bg_color #7a3438;
@define-color accent_fg_color #f7eeee;
selection { background-color: #7a3438; color: #f7eeee; }
*:selected { background-color: #7a3438; }
EOF_GTKCSS

mkdir -p "$tmp/etc/X11/xorg.conf.d"
makefile root:root 0644 "$tmp/etc/X11/xorg.conf.d/40-dexos-libinput.conf" <<'EOF_LIBINPUT'
Section "InputClass"
    Identifier "DexOS mouse acceleration"
    MatchIsPointer "on"
    Driver "libinput"
    Option "AccelProfile" "adaptive"
    Option "AccelSpeed" "0.20"
EndSection

Section "InputClass"
    Identifier "DexOS Windows-like touchpad"
    MatchIsTouchpad "on"
    Driver "libinput"
    # Windows Precision Touchpad-style defaults: accelerated cursor, tap,
    # two-finger right click/scroll, no natural-scroll reversal and palm guard.
    Option "Tapping" "on"
    Option "TappingButtonMap" "lrm"
    Option "TappingDrag" "on"
    Option "TappingDragLock" "off"
    Option "DisableWhileTyping" "on"
    Option "ScrollMethod" "twofinger"
    Option "HorizontalScrolling" "on"
    Option "NaturalScrolling" "off"
    Option "ClickMethod" "buttonareas"
    Option "MiddleEmulation" "off"
    Option "AccelProfile" "adaptive"
    Option "AccelSpeed" "0.00"
    Option "ScrollPixelDistance" "15"
EndSection
EOF_LIBINPUT

mkdir -p "$tmp/etc/xdg/xfce4/xfconf/xfce-perchannel-xml"
makefile root:root 0644 "$tmp/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" <<'EOF_XSET'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0"><property name="Net" type="empty"><property name="ThemeName" type="string" value="adw-gtk3-dark"/><property name="IconThemeName" type="string" value="Adwaita-Xfce"/></property><property name="Gtk" type="empty"><property name="FontName" type="string" value="DejaVu Sans 10"/><property name="CursorThemeName" type="string" value="DexOS-Windows"/><property name="CursorThemeSize" type="int" value="32"/></property></channel>
EOF_XSET
makefile root:root 0644 "$tmp/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml" <<'EOF_XFWM'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="true"/>
    <property name="vblank_mode" type="string" value="xpresent"/>
  </property>
</channel>
EOF_XFWM
makefile root:root 0644 "$tmp/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml" <<'EOF_XFCE_PANEL'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="dark-mode" type="bool" value="true"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=6;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="34"/>
      <property name="icon-size" type="uint" value="20"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
        <value type="int" value="5"/>
        <value type="int" value="6"/>
        <value type="int" value="7"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="whiskermenu"/>
    <property name="plugin-2" type="string" value="tasklist">
      <property name="grouping" type="uint" value="1"/>
    </property>
    <property name="plugin-3" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-4" type="string" value="systray">
      <property name="square-icons" type="bool" value="true"/>
    </property>
    <property name="plugin-5" type="string" value="pulseaudio">
      <property name="volume-step" type="uint" value="5"/>
      <property name="volume-max" type="uint" value="150"/>
      <property name="mixer-command" type="string" value="pavucontrol"/>
      <property name="enable-keyboard-shortcuts" type="bool" value="true"/>
      <property name="enable-multimedia-keys" type="bool" value="true"/>
      <property name="show-notifications" type="bool" value="true"/>
    </property>
    <property name="plugin-6" type="string" value="clock"/>
    <property name="plugin-7" type="string" value="actions"/>
  </property>
</channel>
EOF_XFCE_PANEL
makefile root:root 0644 "$tmp/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml" <<'EOF_DESKTOP_XFCE'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0"><property name="backdrop" type="empty"><property name="screen0" type="empty"><property name="monitor0" type="empty"><property name="workspace0" type="empty"><property name="last-image" type="string" value="/usr/share/dexos/dexos-wallpaper.png"/><property name="image-style" type="int" value="5"/><property name="color-style" type="int" value="0"/><property name="rgba1" type="array"><value type="double" value="0.1686"/><value type="double" value="0.0902"/><value type="double" value="0.0980"/><value type="double" value="1"/></property></property></property></property></property></channel>
EOF_DESKTOP_XFCE

# Apply UI theme/cursor only. Wallpaper ownership belongs to XFCE after the
# one-time dexos-prepare-desktop seed and is never overwritten here.
makefile root:root 0755 "$tmp/usr/local/bin/dexos-apply-theme" <<'EOF_APPLY_THEME'
#!/bin/sh
/usr/bin/xsetroot -solid '#000000' 2>/dev/null || true
/usr/bin/xsetroot -cursor_name left_ptr 2>/dev/null || true

# Wait for the user xfconfd session so these cosmetic defaults reach the right
# DBus session, but never modify the user wallpaper.
i=0
xpid=
while [ "$i" -lt 120 ]; do
    xpid=$(pidof xfdesktop 2>/dev/null | awk '{print $1}')
    [ -n "$xpid" ] && [ -r "/proc/$xpid/environ" ] && break
    sleep 0.25
    i=$((i + 1))
done
if [ -n "$xpid" ] && [ -r "/proc/$xpid/environ" ]; then
    while IFS= read -r envline; do
        case "$envline" in
            DBUS_SESSION_BUS_ADDRESS=*) export DBUS_SESSION_BUS_ADDRESS=${envline#*=} ;;
            DISPLAY=*) export DISPLAY=${envline#*=} ;;
            XAUTHORITY=*) export XAUTHORITY=${envline#*=} ;;
        esac
    done <<EOF_ENV
$(tr '\0' '
' < "/proc/$xpid/environ")
EOF_ENV
fi
xfconf-query -c xsettings -p /Net/ThemeName -s adw-gtk3-dark 2>/dev/null || true
xfconf-query -c xsettings -p /Net/IconThemeName -s Adwaita-Xfce 2>/dev/null || true
xfconf-query -c xsettings -p /Gtk/CursorThemeName -s DexOS-Windows 2>/dev/null || \
  xfconf-query -c xsettings -p /Gtk/CursorThemeName -n -t string -s DexOS-Windows 2>/dev/null || true
xfconf-query -c xsettings -p /Gtk/CursorThemeSize -s 32 2>/dev/null || \
  xfconf-query -c xsettings -p /Gtk/CursorThemeSize -n -t int -s 32 2>/dev/null || true
exit 0
EOF_APPLY_THEME
mkdir -p "$tmp/etc/xdg/autostart"
makefile root:root 0644 "$tmp/etc/xdg/autostart/dexos-audio.desktop" <<'EOF_AUDIO_AUTOSTART'
[Desktop Entry]
Type=Application
Name=DexOS Audio
Comment=Initialize laptop audio controls
Exec=/usr/local/bin/dexos-audio-init
OnlyShowIn=XFCE;
Terminal=false
StartupNotify=false
NoDisplay=true
X-GNOME-Autostart-Delay=2
EOF_AUDIO_AUTOSTART

makefile root:root 0644 "$tmp/etc/xdg/autostart/dexos-branding.desktop" <<'EOF_BRAND_AUTOSTART'
[Desktop Entry]
Type=Application
Name=DexOS Branding
Comment=Apply DexOS desktop theme and cursor
Exec=/usr/local/bin/dexos-apply-theme
OnlyShowIn=XFCE;
Terminal=false
StartupNotify=false
NoDisplay=true
EOF_BRAND_AUTOSTART

makefile root:root 0644 "$tmp/etc/xdg/autostart/dexos-trust-launchers.desktop" <<'EOF_TRUST_AUTOSTART'
[Desktop Entry]
Type=Application
Name=DexOS Launcher Trust
Exec=/usr/local/bin/dexos-trust-launchers
OnlyShowIn=XFCE;
Terminal=false
NoDisplay=true
X-GNOME-Autostart-Delay=2
EOF_TRUST_AUTOSTART

makefile root:root 0644 "$tmp/etc/xdg/autostart/dexos-video.desktop" <<'EOF_VIDEO_AUTOSTART'
[Desktop Entry]
Type=Application
Name=DexOS Video
Comment=Enable compositor sync and hardware video acceleration diagnostics
Exec=/usr/local/bin/dexos-video-init
OnlyShowIn=XFCE;
Terminal=false
NoDisplay=true
X-GNOME-Autostart-Delay=1
EOF_VIDEO_AUTOSTART

# Windows-like system utilities exposed as regular desktop applications.
mkdir -p "$tmp/usr/share/applications" "$tmp/etc/skel/Desktop"
makefile root:root 0644 "$tmp/usr/share/applications/dexos-boot-manager.desktop" <<'EOF_BOOT_DESKTOP'
[Desktop Entry]
Type=Application
Name=Orden de arranque
Comment=Elegir sistema predeterminado y escanear discos para GRUB
Exec=/usr/local/bin/dexos-boot-manager
Icon=drive-harddisk
Terminal=false
StartupNotify=true
Categories=Settings;System;
EOF_BOOT_DESKTOP
makefile root:root 0644 "$tmp/usr/share/applications/dexos-eye-protection.desktop" <<'EOF_EYE_DESKTOP'
[Desktop Entry]
Type=Application
Name=Protección de la vista
Comment=Reducir la luz azul con una temperatura de color cálida
Exec=/usr/local/bin/dexos-eye-protection
Icon=video-display
Terminal=false
StartupNotify=true
Categories=Settings;Utility;
EOF_EYE_DESKTOP
cp "$tmp/usr/share/applications/dexos-boot-manager.desktop" "$tmp/etc/skel/Desktop/Orden-de-arranque.desktop"
chmod 0755 "$tmp/etc/skel/Desktop/Orden-de-arranque.desktop"
makefile root:root 0644 "$tmp/etc/xdg/autostart/dexos-eye-protection.desktop" <<'EOF_EYE_AUTOSTART'
[Desktop Entry]
Type=Application
Name=DexOS Eye Protection
Exec=/usr/local/bin/dexos-eye-protection --startup
OnlyShowIn=XFCE;
Terminal=false
NoDisplay=true
X-GNOME-Autostart-Delay=2
EOF_EYE_AUTOSTART

makefile root:root 0644 "$tmp/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml" <<'EOF_PWR'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-power-manager" version="1.0"><property name="xfce4-power-manager" type="empty"><property name="show-tray-icon" type="int" value="1"/><property name="brightness-switch" type="int" value="1"/><property name="handle-brightness-keys" type="bool" value="true"/><property name="general-notification" type="bool" value="true"/></property></channel>
EOF_PWR

# Crea el usuario live antes de LightDM.
makefile root:root 0755 "$tmp/etc/init.d/dexos-live-user" <<'EOF_USER'
#!/sbin/openrc-run
name="DexOS Live user"
description="Create the unprivileged DexOS Live desktop account"
depend(){ need localmount; before lightdm; }
start(){
    if ! id dexos >/dev/null 2>&1; then
        adduser -D -h /home/dexos -s /bin/bash dexos
        for g in wheel audio video input netdev plugdev; do getent group "$g" >/dev/null 2>&1 && addgroup dexos "$g" || true; done
    fi
    passwd -d dexos >/dev/null 2>&1 || true
    # Live-only convenience: root has no password and wheel members may use
    # `su` without authentication. Installed systems keep the root password
    # explicitly chosen in the graphical installer.
    passwd -d root >/dev/null 2>&1 || true
    mkdir -p /home/dexos/Desktop /home/dexos/.config/autostart /home/dexos/.config/xfce4/xfconf/xfce-perchannel-xml
    if [ -f /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml ]; then
        cp -f /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml /home/dexos/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml
    fi
    if [ -f /usr/share/applications/dexos-installer.desktop ]; then
        install -m 0755 /usr/share/applications/dexos-installer.desktop /home/dexos/Desktop/Instalar-DexOS.desktop
    fi
    chown -R dexos:dexos /home/dexos
}
EOF_USER


# Sólo el backend validado puede elevarse. La interfaz GTK siempre corre como usuario Live.
makefile root:root 0600 "$tmp/etc/doas.d/20-dexos-live.conf" <<'EOF_DOAS'
# Live environment only: dexos may become root without a password.
permit nopass dexos as root
EOF_DOAS
mkdir -p "$tmp/usr/local/bin" "$tmp/usr/local/libexec" "$tmp/usr/share/dexos" "$tmp/usr/share/applications"
makefile root:root 0755 "$tmp/usr/local/bin/su" <<'EOF_SU_WRAPPER'
#!/bin/sh
# BusyBox su does not honor PAM on Alpine. For the DexOS Live account, use
# doas directly so `su` always opens a root shell without prompting.
if [ "$(id -un 2>/dev/null || true)" = "dexos" ]; then
    exec /usr/bin/doas /bin/bash -l
fi
exec /bin/busybox su "$@"
EOF_SU_WRAPPER
install -m 0755 "$INSTALLER_ASSETS/dexos-installer.py" "$tmp/usr/local/bin/dexos-installer"
install -m 0755 "$INSTALLER_ASSETS/dexos-installer-backend.py" "$tmp/usr/local/libexec/dexos-installer-backend"
install -m 0644 "$INSTALLER_ASSETS/installer-packages.txt" "$tmp/usr/share/dexos/installer-packages.txt"
mkdir -p "$tmp/usr/share/dexos/argon-grub-theme"
cp -a "$ARGON_ASSET/." "$tmp/usr/share/dexos/argon-grub-theme/"
makefile root:root 0644 "$tmp/usr/share/applications/dexos-installer.desktop" <<'EOF_DESKTOP'
[Desktop Entry]
Type=Application
Name=Instalar DexOS
Comment=Instalador gráfico seguro de DexOS
Exec=/usr/local/bin/dexos-installer
TryExec=/usr/local/bin/dexos-installer
Icon=drive-harddisk
Terminal=false
StartupNotify=true
X-GNOME-Autostart-enabled=true
Categories=System;
EOF_DESKTOP

# Eudev conforme a setup-devd udev: sin mdev/hwdrivers paralelos.
rc_add devfs sysinit
rc_add dmesg sysinit
rc_add modloop sysinit
rc_add udev sysinit
rc_add udev-trigger sysinit
rc_add udev-settle sysinit
rc_add udev-postmount default
rc_add swclock boot
rc_add modules boot
rc_add sysctl boot
rc_add hostname boot
rc_add bootmisc boot
rc_add syslog boot
rc_add dbus default
rc_add alsa default
rc_add dexos-backlight default
rc_add dexos-power default
rc_add elogind default
rc_add dexos-wifi-init boot
rc_add networkmanager default
rc_add dexos-wifi-refresh default
rc_add dexos-apk-refresh default
rc_add chronyd default
rc_add bluetooth default
rc_add dexos-live-user default
rc_add lightdm default
rc_add mount-ro shutdown
rc_add killprocs shutdown
rc_add savecache shutdown

# Explicit negative markers in overlay are not needed; mdev/hwdrivers are simply never enabled.
# acpid intentionally omitted: Alpine setup-desktop xfce removes it.

tar -c -C "$tmp" . | gzip -9n > "$HOSTNAME.apkovl.tar.gz"
