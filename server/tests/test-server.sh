#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PROFILE="$ROOT/server/mkimage/mkimg.dexserver.sh"
OVERLAY="$ROOT/server/mkimage/genapkovl-dexserver.sh"
INSTALLER="$ROOT/server/install"
BOOT_ORDER="$ROOT/server/boot-order"
LIVE_WORLD="$ROOT/server/live-world.txt"
TARGET_PACKAGES="$ROOT/server/packages.txt"
BUILD="$ROOT/server/build-dexos-server.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

sh -n "$INSTALLER"
sh -n "$BOOT_ORDER"
sh -n "$OVERLAY"
bash -n "$BUILD"
pass "sintaxis shell"

for file in "$LIVE_WORLD" "$TARGET_PACKAGES"; do
    [ -s "$file" ] || fail "lista vacía: $file"
done

for pkg in networkmanager networkmanager-openrc networkmanager-wifi networkmanager-cli openssh avahi avahi-openrc dbus dbus-openrc wpa_supplicant iw wireless-regdb; do
    grep -qx "$pkg" "$LIVE_WORLD" || fail "$pkg falta en Live world"
    grep -qx "$pkg" "$TARGET_PACKAGES" || fail "$pkg falta en sistema instalado"
done
grep -qx doas "$TARGET_PACKAGES" || fail "doas falta en sistema instalado"
for pkg in os-prober ntfs-3g; do
    grep -qx "$pkg" "$TARGET_PACKAGES" || fail "$pkg falta para detectar otros sistemas"
done
pass "red, SSH, Avahi, administración y dual boot presentes"

# Every explicit Live/installed package must exist in the ISO package repository profile.
for file in "$LIVE_WORLD" "$TARGET_PACKAGES"; do
    sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' "$file" | while IFS= read -r pkg; do
        grep -Fq "$pkg" "$PROFILE" || fail "$pkg no está incluido en el repositorio offline del perfil"
    done
done
pass "listas cubiertas por el repositorio offline"

for bad in xorg-server xfce4 lightdm firefox mesa-dri-gallium mesa-gl pipewire bluez pulseaudio vulkan-loader linux-firmware-amdgpu linux-firmware-i915 linux-firmware-nvidia linux-firmware-xe; do
    if grep -Fxq "$bad" "$LIVE_WORLD" || grep -Fxq "$bad" "$TARGET_PACKAGES"; then
        fail "paquete gráfico/no-server presente: $bad"
    fi
done
pass "sin stack gráfico, audio ni Bluetooth"

grep -Fq 'chmod 0755 "$tmp"' "$OVERLAY" || fail "el apkovl dejaría la raíz Live sin permisos de traversing"
grep -Fq 'cp /work/server/live-world.txt "$tmp/etc/apk/world"' "$OVERLAY" || fail "overlay no instala /etc/apk/world"
grep -Fq 'cp /work/server/install "$tmp/usr/local/sbin/install"' "$OVERLAY" || fail "overlay no instala el comando install"
grep -Fq 'cp /work/server/boot-order "$tmp/usr/local/sbin/boot-order"' "$OVERLAY" || fail "overlay no instala boot-order"
grep -Fq 'networkmanager sshd avahi-daemon' "$OVERLAY" || fail "servicios Server no habilitados en Live"
grep -Fq 'https://dl-cdn.alpinelinux.org/alpine/edge/main' "$OVERLAY" || fail "repositorio main falta en Live"
grep -Fq 'https://dl-cdn.alpinelinux.org/alpine/edge/community' "$OVERLAY" || fail "repositorio community falta en Live"
pass "overlay Live"

grep -Fq 'apk add --simulate --no-network --repositories-file /dev/null' "$INSTALLER" || fail "preflight offline estricto ausente"
grep -Fq 'apk add --root "$TARGET"' "$INSTALLER" || fail "instalación apk --root ausente"
grep -Fq -- '--no-network --repositories-file /dev/null' "$INSTALLER" || fail "instalación no aísla los repositorios online"
grep -Fq -- '--repository "$repo"' "$INSTALLER" || fail "instalación no usa el repositorio de la ISO"
grep -Fq 'nmcli device wifi connect' "$INSTALLER" || fail "asistente Wi-Fi no usa nmcli"
grep -Fq 'networkmanager sshd avahi-daemon' "$INSTALLER" || fail "servicios instalados no configurados"
grep -Fq '/etc/apk/repositories' "$INSTALLER" || fail "repositorios instalados no configurados"
grep -Fq '/sbin/mkinitfs' "$INSTALLER" || fail "initramfs no se genera explícitamente"
grep -Fq 'root=UUID=$root_uuid' "$INSTALLER" || fail "GRUB no fija root por UUID"
grep -Fq 'system-connections' "$INSTALLER" || fail "perfiles NetworkManager no se preservan"
grep -Fq 'Nombre del servidor/mDNS' "$INSTALLER" || fail "falta nombre .local inteligente"
grep -Fq 'case "$name" in *.local)' "$INSTALLER" || fail "no se evita duplicar .local"
grep -Fq 'Enter = usar la de $admin_user' "$INSTALLER" || fail "root no puede heredar contraseña"
grep -Fq 'PermitRootLogin $ssh_root_login' "$INSTALLER" || fail "root SSH no es configurable"
grep -Fq 'Coexistir con otro sistema' "$INSTALLER" || fail "falta modo coexistencia"
grep -Fq 'select_root_partition' "$INSTALLER" || fail "falta selector de partición raíz"
grep -Fq 'select_efi_partition' "$INSTALLER" || fail "falta selector de ESP"
grep -Fq 'GRUB_DISABLE_OS_PROBER=false' "$INSTALLER" || fail "os-prober no está habilitado en GRUB"
grep -Fq '/usr/bin/os-prober' "$INSTALLER" || fail "otros sistemas no se detectan"
grep -Fq 'ensure_block_node' "$INSTALLER" || fail "falta reparación robusta de nodos de partición"
grep -Fq 'mknod "$path"' "$INSTALLER" || fail "no se corrige el race de /dev/vda3"
if grep -Fq 'BORRAR $disk' "$INSTALLER"; then fail "el instalador aún exige escribir BORRAR"; fi
if grep -Fq 'setup-alpine' "$INSTALLER"; then fail "el instalador propio depende de setup-alpine"; fi
grep -Fq 'grub-set-default' "$BOOT_ORDER" || fail "boot-order no cambia el arranque predeterminado"
pass "flujo del instalador terminal, coexistencia y boot-order"

if grep -R -E 'Gtk|py3-gobject|xorg-server|xfce4|lightdm' "$ROOT/server" --exclude='test-server.sh' >/dev/null 2>&1; then
    fail "dependencia gráfica detectada dentro de server/"
fi
pass "server/ no depende de GUI"

echo "DexOS Server static tests: PASS"
