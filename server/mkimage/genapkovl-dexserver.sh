#!/bin/sh
set -eu
HOSTNAME="${1:-dexos-server}"
apkovl="${DESTDIR:-.}/${HOSTNAME}.apkovl.tar.gz"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p \
  "$tmp/etc/ssh/sshd_config.d" \
  "$tmp/etc/avahi" \
  "$tmp/etc/NetworkManager/system-connections" \
  "$tmp/etc/runlevels/default" \
  "$tmp/etc/runlevels/boot" \
  "$tmp/etc/apk" \
  "$tmp/usr/local/sbin"

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
cat > "$tmp/etc/motd" <<'EOF'
DexOS Server
Ultra-light Alpine Linux server edition.

Install to disk: install
Network/Wi-Fi:   nmcli
SSH and Avahi are enabled at boot.
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
host-name=dexos-server
use-ipv4=yes
use-ipv6=yes
[wide-area]
enable-wide-area=no
[publish]
publish-addresses=yes
publish-workstation=no
EOF

cp /work/server/install "$tmp/usr/local/sbin/install"
chmod 0755 "$tmp/usr/local/sbin/install"

for svc in dbus networkmanager sshd avahi-daemon; do
    ln -s "/etc/init.d/$svc" "$tmp/etc/runlevels/default/$svc"
done
for svc in hostname modules sysctl bootmisc syslog; do
    ln -s "/etc/init.d/$svc" "$tmp/etc/runlevels/boot/$svc"
done

# Do not ship static SSH host keys. OpenSSH will generate unique keys on boot.
rm -f "$tmp"/etc/ssh/ssh_host_* 2>/dev/null || true

( cd "$tmp" && tar -czf "$apkovl" . )
