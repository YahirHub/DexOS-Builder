#!/bin/sh -e
HOSTNAME="${1:-dexos-live}"
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

makefile root:root 0644 "$tmp/etc/apk/world" <<'EOF_WORLD'
alpine-base
alpine-conf
doas
bash
shadow
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
xfce-polkit
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
wpa_supplicant
wireless-regdb
bluez
bluez-openrc
pipewire
pipewire-pulse
pipewire-alsa
wireplumber
alsa-utils
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
pciutils
usbutils
tzdata
ca-certificates
curl
EOF_WORLD

# evdev crea /dev/input/event*; Xorg/libinput depende de estos nodos.
makefile root:root 0644 "$tmp/etc/modules" <<'EOF_MODULES'
evdev
EOF_MODULES

makefile root:root 0644 "$tmp/etc/network/interfaces" <<'EOF_NET'
auto lo
iface lo inet loopback
EOF_NET
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

# Session Live: user normal + elogind + LightDM. Nunca se inicia XFCE como root.
mkdir -p "$tmp/etc/lightdm/lightdm.conf.d"
makefile root:root 0644 "$tmp/etc/lightdm/lightdm.conf.d/10-dexos-live.conf" <<'EOF_LDM'
[LightDM]
logind-check-graphical=false

[Seat:*]
display-setup-script=/usr/local/sbin/dexos-xsetup
greeter-session=lightdm-gtk-greeter
user-session=xfce
autologin-user=dexos
autologin-user-timeout=0
autologin-session=xfce
EOF_LDM
makefile root:root 0644 "$tmp/etc/lightdm/lightdm-gtk-greeter.conf" <<'EOF_GREETER'
[greeter]
background=/usr/share/backgrounds/dexos.svg
theme-name=adw-gtk3-dark
icon-theme-name=Adwaita-Xfce
font-name=DejaVu Sans 11
clock-format=%A %d de %B  %H:%M
indicators=~host;~spacer;~clock;~spacer;~session;~language;~a11y;~power
user-background=false
EOF_GREETER

mkdir -p "$tmp/usr/share/backgrounds"
makefile root:root 0644 "$tmp/usr/share/backgrounds/dexos.svg" <<'EOF_SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#2b1719"/><stop offset=".58" stop-color="#512629"/><stop offset="1" stop-color="#6b2a2e"/></linearGradient></defs><rect width="1920" height="1080" fill="url(#g)"/><path d="M0 880 L390 520 L620 735 L930 410 L1240 720 L1510 500 L1920 850 L1920 1080 L0 1080 Z" fill="#1d1012" opacity=".72"/><circle cx="1680" cy="180" r="120" fill="#8f3e42" opacity=".15"/><text x="110" y="170" font-family="DejaVu Sans" font-size="82" fill="#f0e5e5" font-weight="600">DexOS</text><text x="116" y="226" font-family="DejaVu Sans" font-size="28" fill="#d1a8aa">XFCE • ligero • estable</text></svg>
EOF_SVG

# Xorg pinta rojo mate inmediatamente, antes de que XFCE termine su primer frame.
makefile root:root 0755 "$tmp/usr/local/sbin/dexos-xsetup" <<'EOF_XSETUP'
#!/bin/sh
exec /usr/bin/xsetroot -solid '#6b2a2e'
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

mkdir -p "$tmp/etc/xdg/xfce4/xfconf/xfce-perchannel-xml"
makefile root:root 0644 "$tmp/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" <<'EOF_XSET'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0"><property name="Net" type="empty"><property name="ThemeName" type="string" value="adw-gtk3-dark"/><property name="IconThemeName" type="string" value="Adwaita-Xfce"/></property><property name="Gtk" type="empty"><property name="FontName" type="string" value="DejaVu Sans 10"/></property></channel>
EOF_XSET
makefile root:root 0644 "$tmp/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml" <<'EOF_DESKTOP_XFCE'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0"><property name="backdrop" type="empty"><property name="screen0" type="empty"><property name="monitor0" type="empty"><property name="workspace0" type="empty"><property name="last-image" type="string" value="/usr/share/backgrounds/dexos.svg"/><property name="image-style" type="int" value="5"/><property name="color-style" type="int" value="0"/><property name="rgba1" type="array"><value type="double" value="0.1686"/><value type="double" value="0.0902"/><value type="double" value="0.0980"/><value type="double" value="1"/></property></property></property></property></property></channel>
EOF_DESKTOP_XFCE

# Aplica la identidad DexOS al monitor real que XFCE detecte (VGA-1, Virtual-1, eDP-1, etc.).
makefile root:root 0755 "$tmp/usr/local/bin/dexos-apply-theme" <<'EOF_APPLY_THEME'
#!/bin/sh
wall=/usr/share/backgrounds/dexos.svg
/usr/bin/xsetroot -solid '#6b2a2e' 2>/dev/null || true

i=0
while [ "$i" -lt 40 ]; do
    props=$(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep '/last-image$' || true)
    [ -n "$props" ] && break
    sleep 0.25
    i=$((i + 1))
done

printf '%s\n' "$props" | while IFS= read -r prop; do
    [ -n "$prop" ] || continue
    xfconf-query -c xfce4-desktop -p "$prop" -s "$wall" 2>/dev/null || true
    base=${prop%/last-image}
    xfconf-query -c xfce4-desktop -p "$base/image-style" -s 5 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p "$base/color-style" -s 0 2>/dev/null || true
done

# Reaplicar tema/acento después de que xfsettingsd esté activo.
xfconf-query -c xsettings -p /Net/ThemeName -s adw-gtk3-dark 2>/dev/null || true
xfconf-query -c xsettings -p /Net/IconThemeName -s Adwaita-Xfce 2>/dev/null || true
exit 0
EOF_APPLY_THEME
mkdir -p "$tmp/etc/xdg/autostart"
makefile root:root 0644 "$tmp/etc/xdg/autostart/dexos-branding.desktop" <<'EOF_BRAND_AUTOSTART'
[Desktop Entry]
Type=Application
Name=DexOS Branding
Comment=Apply DexOS matte-red desktop identity
Exec=/usr/local/bin/dexos-apply-theme
OnlyShowIn=XFCE;
Terminal=false
StartupNotify=false
NoDisplay=true
EOF_BRAND_AUTOSTART

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
        adduser -D -h /home/dexos -s /bin/ash dexos
        for g in wheel audio video input netdev plugdev; do getent group "$g" >/dev/null 2>&1 && addgroup dexos "$g" || true; done
    fi
    passwd -d dexos >/dev/null 2>&1 || true
    mkdir -p /home/dexos/Desktop /home/dexos/.config/autostart
    if [ -f /usr/share/applications/dexos-installer.desktop ]; then
        install -m 0755 /usr/share/applications/dexos-installer.desktop /home/dexos/Desktop/Instalar-DexOS.desktop
    fi
    chown -R dexos:dexos /home/dexos
}
EOF_USER

# Mantiene el splash visible durante OpenRC y permite ESC para alternar detalles.
makefile root:root 0755 "$tmp/usr/local/sbin/dexos-splash-keys" <<'EOF_SPLASH_KEYS'
#!/bin/sh
esc="$(printf '\033')"
current=16
case "$(cat /sys/class/tty/tty0/active 2>/dev/null || true)" in
    *tty1*) current=1 ;;
esac
while [ -p /.splash.ctrl ]; do
    dev="/dev/tty$current"
    [ -c "$dev" ] || { sleep 1; continue; }
    stty -F "$dev" -echo -icanon min 1 time 0 2>/dev/null || exit 0
    key=
    IFS= read -r -n 1 key < "$dev" || continue
    [ "$key" = "$esc" ] || continue
    if [ "$current" -eq 16 ]; then
        touch /.dexos-show-boot-log
        printf '\033[H\033[2JDexOS — detalles del arranque (ESC para volver)\n\n' > /dev/tty1
        dmesg > /dev/tty1 2>/dev/null || true
        rc-status -a > /dev/tty1 2>/dev/null || true
        chvt 1
        current=1
    else
        rm -f /.dexos-show-boot-log
        chvt 16
        sleep 0.05
        if [ -r /usr/share/dexos/fbsplash.ppm ] && [ -r /etc/dexos/fbsplash.cfg ]; then
            fbsplash -s /usr/share/dexos/fbsplash.ppm -d /dev/fb0 -i /etc/dexos/fbsplash.cfg >/dev/null 2>&1 || true
        fi
        if [ -r /.dexos-splash-progress ] && [ -p /.splash.ctrl ]; then
            pct=$(cat /.dexos-splash-progress 2>/dev/null || echo 91)
            timeout 1 sh -c "printf '%s\n' '$pct' > /.splash.ctrl" 2>/dev/null || true
        fi
        current=16
    fi
done
EOF_SPLASH_KEYS

makefile root:root 0755 "$tmp/etc/init.d/dexos-splash-keys" <<'EOF_SPLASH_SERVICE'
#!/sbin/openrc-run
name="DexOS boot detail toggle"
description="Allow ESC to toggle between splash and boot details"
depend(){ need localmount; before lightdm; }
start(){
    [ -p /.splash.ctrl ] || return 0
    printf '91\n' > /.dexos-splash-progress
    printf '91\n' > /.splash.ctrl 2>/dev/null || true
    /usr/local/sbin/dexos-splash-keys &
    echo $! > /run/dexos-splash-keys.pid
}
stop(){
    if [ -r /run/dexos-splash-keys.pid ]; then
        kill "$(cat /run/dexos-splash-keys.pid)" 2>/dev/null || true
        rm -f /run/dexos-splash-keys.pid
    fi
    stty -F /dev/tty1 sane 2>/dev/null || true
    stty -F /dev/tty16 sane 2>/dev/null || true
}
EOF_SPLASH_SERVICE

# Monitor desacoplado: no hace fallar LightDM si XFCE tarda en TCG/equipos lentos.
makefile root:root 0755 "$tmp/usr/local/sbin/dexos-desktop-ready" <<'EOF_DESKTOP_READY'
#!/bin/sh
finish_splash() {
    if [ -r /run/dexos-splash-keys.pid ]; then
        kill "$(cat /run/dexos-splash-keys.pid)" 2>/dev/null || true
        rm -f /run/dexos-splash-keys.pid
    fi
    stty -F /dev/tty1 sane 2>/dev/null || true
    stty -F /dev/tty16 sane 2>/dev/null || true
    if [ -p /.splash.ctrl ]; then
        timeout 2 sh -c "printf 'exit\n' > /.splash.ctrl" 2>/dev/null || true
        rm -f /.splash.ctrl
    fi
    rm -f /.dexos-show-boot-log /.dexos-splash-progress
}
progress() {
    printf '%s\n' "$1" > /.dexos-splash-progress
    [ -p /.splash.ctrl ] || return 0
    timeout 1 sh -c "printf '%s\n' '$1' > /.splash.ctrl" 2>/dev/null || true
}

progress 97
i=0
# Hasta 180 s: máquinas sin KVM o hardware lento pueden tardar mucho en iniciar XFCE.
while [ "$i" -lt 720 ]; do
    if pidof xfce4-session >/dev/null 2>&1 \
       && pidof xfwm4 >/dev/null 2>&1 \
       && pidof xfdesktop >/dev/null 2>&1 \
       && pidof xfce4-panel >/dev/null 2>&1; then
        progress 100
        sleep 0.75
        finish_splash
        exit 0
    fi
    # Si LightDM realmente murió, no ocultar el diagnóstico detrás del splash.
    if [ "$i" -gt 20 ] && ! pidof lightdm >/dev/null 2>&1; then
        finish_splash
        printf '\033[H\033[2JDexOS: LightDM terminó inesperadamente. Revise /var/log/lightdm/.\n' > /dev/tty1
        chvt 1 2>/dev/null || true
        exit 1
    fi
    sleep 0.25
    i=$((i + 1))
done

# El timeout del monitor nunca cambia el estado OpenRC de LightDM.
finish_splash
printf '\033[H\033[2JDexOS: XFCE tardó más de 180 segundos en quedar listo.\n' > /dev/tty1
chvt 1 2>/dev/null || true
exit 1
EOF_DESKTOP_READY

# LightDM espera a dependencias críticas, pero la espera de XFCE ocurre aparte.
makefile root:root 0755 "$tmp/etc/init.d/lightdm" <<'EOF_LIGHTDM_INIT'
#!/sbin/openrc-run
supervisor=supervise-daemon
name="Display Manager"
description="Lightweight Display Manager with DexOS Live readiness gate"
command=/usr/bin/lightdm

depend() {
    provide display-manager
    need localmount dbus elogind networkmanager dexos-live-user
    after udev-postmount dexos-splash-keys
}

splash_progress() {
    printf '%s\n' "$1" > /.dexos-splash-progress
    [ -p /.splash.ctrl ] || return 0
    timeout 2 sh -c "printf '%s\n' '$1' > /.splash.ctrl" 2>/dev/null || true
}

splash_finish() {
    if [ -r /run/dexos-splash-keys.pid ]; then
        kill "$(cat /run/dexos-splash-keys.pid)" 2>/dev/null || true
        rm -f /run/dexos-splash-keys.pid
    fi
    stty -F /dev/tty1 sane 2>/dev/null || true
    stty -F /dev/tty16 sane 2>/dev/null || true
    if [ -p /.splash.ctrl ]; then
        timeout 2 sh -c "printf 'exit\n' > /.splash.ctrl" 2>/dev/null || true
        rm -f /.splash.ctrl
    fi
    rm -f /.dexos-show-boot-log /.dexos-splash-progress
}

start_pre() {
    splash_progress 94
    udevadm settle --timeout=15 >/dev/null 2>&1 || true
    sleep 1
    checkpath --owner lightdm:lightdm --directory /run/lightdm
}

start_post() {
    splash_progress 97
    rm -f /run/dexos-desktop-ready.pid
    nohup /usr/local/sbin/dexos-desktop-ready >/run/dexos-desktop-ready.log 2>&1 &
    echo $! > /run/dexos-desktop-ready.pid
    return 0
}
EOF_LIGHTDM_INIT

makefile root:root 0600 "$tmp/etc/doas.d/20-dexos-live.conf" <<'EOF_DOAS'
permit nopass dexos as root cmd /usr/local/sbin/dexos-install-root
EOF_DOAS

# Instalador pequeño: wrapper seguro hacia setup-alpine en terminal por ahora.
# deuda-tecnica: reemplazar por wizard Go completo cuando runtime XFCE esté validado, antes de release estable.
makefile root:root 0755 "$tmp/usr/local/sbin/dexos-install-root" <<'EOF_INSTALLROOT'
#!/bin/sh
exec setup-alpine
EOF_INSTALLROOT
mkdir -p "$tmp/usr/share/applications"
makefile root:root 0644 "$tmp/usr/share/applications/dexos-installer.desktop" <<'EOF_DESKTOP'
[Desktop Entry]
Type=Application
Name=Instalar DexOS
Comment=Instalar DexOS en el disco
Exec=doas /usr/local/sbin/dexos-install-root
TryExec=doas
Icon=drive-harddisk
Terminal=true
StartupNotify=false
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
rc_add hwclock boot
rc_add modules boot
rc_add sysctl boot
rc_add hostname boot
rc_add bootmisc boot
rc_add syslog boot
rc_add dexos-splash-keys boot
rc_add dbus default
rc_add elogind default
rc_add networkmanager default
rc_add bluetooth default
rc_add dexos-live-user default
rc_add lightdm default
rc_add mount-ro shutdown
rc_add killprocs shutdown
rc_add savecache shutdown

# Explicit negative markers in overlay are not needed; mdev/hwdrivers are simply never enabled.
# acpid intentionally omitted: Alpine setup-desktop xfce removes it.

tar -c -C "$tmp" . | gzip -9n > "$HOSTNAME.apkovl.tar.gz"
