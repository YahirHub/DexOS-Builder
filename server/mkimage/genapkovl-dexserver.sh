#!/bin/sh
set -eu

HOSTNAME="${1:-dex}"
ARGON_ASSET=/work/server/assets/argon-grub-theme
WEB_ASSET=/work/server/web
INSTALLED_ASSET=/work/server/installed
LIVE_HELPER=/work/server/dex-installer-live
LIVE_SERVICE=/work/server/openrc/dex-installer-live
[ -f "$ARGON_ASSET/theme.txt" ] || { echo "Falta tema Argon de GRUB" >&2; exit 1; }
[ -f "$ARGON_ASSET/background.png" ] || { echo "Falta background.png del tema Argon" >&2; exit 1; }
[ -f "$ARGON_ASSET/LICENCE.txt" ] || { echo "Falta LICENCE.txt del tema Argon" >&2; exit 1; }
[ -f "$WEB_ASSET/index.html" ] || { echo "Falta instalador web" >&2; exit 1; }
[ -x "$WEB_ASSET/cgi-bin/install.cgi" ] || { echo "Falta CGI de instalación" >&2; exit 1; }
[ -x "$LIVE_HELPER" ] || { echo "Falta helper Dex-Installer Live" >&2; exit 1; }
[ -x "$LIVE_SERVICE" ] || { echo "Falta servicio OpenRC Dex-Installer Live" >&2; exit 1; }
[ -x "$INSTALLED_ASSET/dexos-wifi-firstboot" ] || { echo "Falta servicio Wi-Fi instalado" >&2; exit 1; }
[ -x "$INSTALLED_ASSET/wifi" ] || { echo "Falta herramienta wifi" >&2; exit 1; }
[ -x "$INSTALLED_ASSET/diskinfo" ] || { echo "Falta diskinfo" >&2; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# The archive contains `.` itself. mktemp creates it as 0700; if preserved,
# Alpine applies that mode to the Live root and non-root daemons cannot traverse /.
chmod 0755 "$tmp"

mkdir -p \
  "$tmp/etc/ssh/sshd_config.d" \
  "$tmp/etc/avahi" \
  "$tmp/etc/NetworkManager/conf.d" \
  "$tmp/etc/NetworkManager/system-connections" \
  "$tmp/etc/apk" \
  "$tmp/etc/runlevels/sysinit" \
  "$tmp/etc/runlevels/default" \
  "$tmp/etc/runlevels/boot" \
  "$tmp/etc/runlevels/shutdown" \
  "$tmp/etc/profile.d" \
  "$tmp/etc/init.d" \
  "$tmp/usr/local/sbin" \
  "$tmp/usr/share/dexos/grub.d" \
  "$tmp/usr/share/dexos/argon-grub-theme" \
  "$tmp/usr/share/dexos/installer-web" \
  "$tmp/usr/share/dexos/installed"

printf '%s\n' "$HOSTNAME" > "$tmp/etc/hostname"
cat > "$tmp/etc/hosts" <<EOF
127.0.0.1 localhost localhost.localdomain
127.0.1.1 $HOSTNAME $HOSTNAME.localdomain
::1 localhost localhost.localdomain
EOF
cat > "$tmp/etc/apk/repositories" <<'EOF'
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
EOF
cat > "$tmp/etc/NetworkManager/conf.d/10-dexos-network.conf" <<'EOF'
[main]
plugins=keyfile
rc-manager=file
dns=default

[ifupdown]
managed=true
EOF
cat > "$tmp/etc/NetworkManager/system-connections/dexos-wired.nmconnection" <<'EOF'
[connection]
id=DexOS Wired
uuid=7ef3663e-bd07-4eb2-8cd6-2be94a6a6391
type=ethernet
autoconnect=true
autoconnect-priority=100

[ethernet]

[ipv4]
method=auto

[ipv6]
method=auto
addr-gen-mode=default

[proxy]
EOF
chmod 0600 "$tmp/etc/NetworkManager/system-connections/dexos-wired.nmconnection"
cat > "$tmp/etc/resolv.conf" <<'EOF'
# Fallback DNS; NetworkManager replaces this after DHCP/Wi-Fi connects.
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

# Packages in the ISO repository are not automatically installed in the Live.
# world makes nmcli, firmware and the disk installer available before networking.
cp /work/server/live-world.txt "$tmp/etc/apk/world"
sed -i -e 's/#.*$//' -e '/^[[:space:]]*$/d' "$tmp/etc/apk/world"
cp /work/server/packages.txt "$tmp/usr/share/dexos/server-packages.txt"
cp -a "$ARGON_ASSET/." "$tmp/usr/share/dexos/argon-grub-theme/"
cp -a "$WEB_ASSET/." "$tmp/usr/share/dexos/installer-web/"
cp -a "$INSTALLED_ASSET/." "$tmp/usr/share/dexos/installed/"

cat > "$tmp/etc/motd" <<'EOF'
DexOS Server
Ultra-light Alpine Linux server edition.

Web installer: http://dex.local/
Wi-Fi installer: Dex-Installer (si la tarjeta soporta modo AP)
SSH temporal Live: root / root
Terminal installer: install
Network tools: nmcli
EOF
cat > "$tmp/etc/issue" <<'EOF'
DexOS Server \n (Alpine Linux) \l
EOF
cat > "$tmp/etc/os-release" <<'EOF'
NAME="DexOS Server"
PRETTY_NAME="DexOS Server"
ID=dexos-server
ID_LIKE=alpine
VERSION_ID="edge"
VERSION="edge"
EOF
cat > "$tmp/etc/ssh/sshd_config.d/10-dexos-server.conf" <<'EOF'
PasswordAuthentication yes
PermitRootLogin yes
PermitEmptyPasswords no
UseDNS no
EOF
cat > "$tmp/etc/avahi/avahi-daemon.conf" <<'EOF'
[server]
use-ipv4=yes
use-ipv6=yes
[wide-area]
enable-wide-area=no
[publish]
publish-addresses=yes
publish-workstation=no
EOF
cat > "$tmp/etc/profile.d/00-dexos-path.sh" <<'EOF'
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EOF

cp /work/server/install "$tmp/usr/local/sbin/install"
cp /work/server/boot-order "$tmp/usr/local/sbin/boot-order"
cp "$LIVE_HELPER" "$tmp/usr/local/sbin/dex-installer-live"
cp "$LIVE_SERVICE" "$tmp/etc/init.d/dex-installer-live"
cp /work/server/grub-update "$tmp/usr/local/sbin/grub-update"
ln -s grub-update "$tmp/usr/local/sbin/update-grub"
cp /work/server/grub-other-os "$tmp/usr/share/dexos/grub.d/31_dexos_other_os"
chmod 0755 \
  "$tmp/usr/local/sbin/install" \
  "$tmp/usr/local/sbin/boot-order" \
  "$tmp/usr/local/sbin/grub-update" \
  "$tmp/usr/local/sbin/dex-installer-live" \
  "$tmp/etc/init.d/dex-installer-live" \
  "$tmp/usr/share/dexos/grub.d/31_dexos_other_os" \
  "$tmp/usr/share/dexos/installer-web/cgi-bin/"*.cgi \
  "$tmp/usr/share/dexos/installed/dexos-wifi-firstboot" \
  "$tmp/usr/share/dexos/installed/wifi" \
  "$tmp/usr/share/dexos/installed/diskinfo"
chmod 0644 "$tmp/usr/share/dexos/installed/10-dexos-diskinfo.sh"

for svc in devfs dmesg udev udev-trigger udev-settle hwdrivers modloop; do
    ln -s "/etc/init.d/$svc" "$tmp/etc/runlevels/sysinit/$svc"
done
for svc in dbus networkmanager dex-installer-live sshd avahi-daemon udev-postmount; do
    ln -s "/etc/init.d/$svc" "$tmp/etc/runlevels/default/$svc"
done
for svc in hostname modules sysctl bootmisc syslog; do
    ln -s "/etc/init.d/$svc" "$tmp/etc/runlevels/boot/$svc"
done
for svc in mount-ro killprocs savecache; do
    ln -s "/etc/init.d/$svc" "$tmp/etc/runlevels/shutdown/$svc"
done

# OpenSSH generates unique host keys when the Live boots; never bake keys into ISO.
rm -f "$tmp"/etc/ssh/ssh_host_* 2>/dev/null || true

# mkimage invokes this script from the section destination directory. Write the
# archive there (not inside $tmp, which is removed by the EXIT trap).
tar -c -C "$tmp" . | gzip -9n > "$HOSTNAME.apkovl.tar.gz"
