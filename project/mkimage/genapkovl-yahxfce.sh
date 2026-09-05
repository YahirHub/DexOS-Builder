#!/bin/sh -e
HOSTNAME="${1:-yah-live}"
tmp="$(mktemp -d)"
chmod 0755 "$tmp"
trap 'rm -rf "$tmp"' EXIT
makefile(){ owner="$1"; perms="$2"; path="$3"; mkdir -p "$(dirname "$path")"; cat >"$path"; chown "$owner" "$path"; chmod "$perms" "$path"; }
rc_add(){ mkdir -p "$tmp/etc/runlevels/$2"; ln -sf "/etc/init.d/$1" "$tmp/etc/runlevels/$2/$1"; }

mkdir -p "$tmp/etc/apk" "$tmp/etc/network" "$tmp/etc/NetworkManager/conf.d"
makefile root:root 0644 "$tmp/etc/hostname" <<EOF_HOST
$HOSTNAME
EOF_HOST
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
makefile root:root 0644 "$tmp/etc/NetworkManager/conf.d/10-yah-live.conf" <<'EOF_NMC'
[connection]
wifi.powersave=2
EOF_NMC

# Session Live: user normal + elogind + LightDM. Nunca se inicia XFCE como root.
mkdir -p "$tmp/etc/lightdm/lightdm.conf.d"
makefile root:root 0644 "$tmp/etc/lightdm/lightdm.conf.d/10-yah-live.conf" <<'EOF_LDM'
[LightDM]
logind-check-graphical=false

[Seat:*]
greeter-session=lightdm-gtk-greeter
user-session=xfce
autologin-user=yah
autologin-user-timeout=0
autologin-session=xfce
EOF_LDM
makefile root:root 0644 "$tmp/etc/lightdm/lightdm-gtk-greeter.conf" <<'EOF_GREETER'
[greeter]
background=/usr/share/backgrounds/yah-alpine.svg
theme-name=adw-gtk3-dark
icon-theme-name=Adwaita-Xfce
font-name=DejaVu Sans 11
clock-format=%A %d de %B  %H:%M
indicators=~host;~spacer;~clock;~spacer;~session;~language;~a11y;~power
user-background=false
EOF_GREETER

mkdir -p "$tmp/usr/share/backgrounds"
makefile root:root 0644 "$tmp/usr/share/backgrounds/yah-alpine.svg" <<'EOF_SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#102033"/><stop offset=".55" stop-color="#163a5f"/><stop offset="1" stop-color="#1f6f8b"/></linearGradient></defs><rect width="1920" height="1080" fill="url(#g)"/><path d="M0 880 L390 520 L620 735 L930 410 L1240 720 L1510 500 L1920 850 L1920 1080 L0 1080 Z" fill="#0a1624" opacity=".62"/><text x="110" y="170" font-family="DejaVu Sans" font-size="76" fill="#f2fbff" font-weight="600">Yah Alpine</text><text x="116" y="225" font-family="DejaVu Sans" font-size="28" fill="#b9ddec">XFCE • ligero • rápido</text></svg>
EOF_SVG

mkdir -p "$tmp/etc/xdg/xfce4/xfconf/xfce-perchannel-xml"
makefile root:root 0644 "$tmp/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" <<'EOF_XSET'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0"><property name="Net" type="empty"><property name="ThemeName" type="string" value="adw-gtk3-dark"/><property name="IconThemeName" type="string" value="Adwaita-Xfce"/></property><property name="Gtk" type="empty"><property name="FontName" type="string" value="DejaVu Sans 10"/></property></channel>
EOF_XSET
makefile root:root 0644 "$tmp/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml" <<'EOF_PWR'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-power-manager" version="1.0"><property name="xfce4-power-manager" type="empty"><property name="show-tray-icon" type="int" value="1"/><property name="brightness-switch" type="int" value="1"/><property name="handle-brightness-keys" type="bool" value="true"/><property name="general-notification" type="bool" value="true"/></property></channel>
EOF_PWR

# Crea el usuario live antes de LightDM.
makefile root:root 0755 "$tmp/etc/init.d/yah-live-user" <<'EOF_USER'
#!/sbin/openrc-run
name="Yah live user"
description="Create the unprivileged Yah Live desktop account"
depend(){ need localmount; before lightdm; }
start(){
    if ! id yah >/dev/null 2>&1; then
        adduser -D -h /home/yah -s /bin/ash yah
        for g in wheel audio video input netdev plugdev; do getent group "$g" >/dev/null 2>&1 && addgroup yah "$g" || true; done
    fi
    passwd -d yah >/dev/null 2>&1 || true
    mkdir -p /home/yah/Desktop /home/yah/.config/autostart
    chown -R yah:yah /home/yah
}
EOF_USER
makefile root:root 0600 "$tmp/etc/doas.d/20-yah-live.conf" <<'EOF_DOAS'
permit nopass yah as root cmd /usr/local/sbin/yah-install-root
EOF_DOAS

# Instalador pequeño: wrapper seguro hacia setup-alpine en terminal por ahora.
# deuda-tecnica: reemplazar por wizard Go completo cuando runtime XFCE esté validado, antes de release estable.
makefile root:root 0755 "$tmp/usr/local/bin/yah-installer" <<'EOF_INSTALLER'
#!/bin/sh
exec xfce4-terminal --title="Instalar Yah Alpine" --hold -e "doas /usr/local/sbin/yah-install-root"
EOF_INSTALLER
makefile root:root 0755 "$tmp/usr/local/sbin/yah-install-root" <<'EOF_INSTALLROOT'
#!/bin/sh
exec setup-alpine
EOF_INSTALLROOT
mkdir -p "$tmp/usr/share/applications"
makefile root:root 0644 "$tmp/usr/share/applications/yah-installer.desktop" <<'EOF_DESKTOP'
[Desktop Entry]
Type=Application
Name=Instalar Yah Alpine
Comment=Instalar el sistema en el disco
Exec=doas /usr/local/bin/yah-installer
Icon=drive-harddisk
Terminal=false
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
rc_add dbus default
rc_add elogind default
rc_add networkmanager default
rc_add bluetooth default
rc_add yah-live-user default
rc_add lightdm default
rc_add mount-ro shutdown
rc_add killprocs shutdown
rc_add savecache shutdown

# Explicit negative markers in overlay are not needed; mdev/hwdrivers are simply never enabled.
# acpid intentionally omitted: Alpine setup-desktop xfce removes it.

tar -c -C "$tmp" . | gzip -9n > "$HOSTNAME.apkovl.tar.gz"
