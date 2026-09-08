#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PROFILE="$ROOT/server/mkimage/mkimg.dexserver.sh"
OVERLAY="$ROOT/server/mkimage/genapkovl-dexserver.sh"
INSTALLER="$ROOT/server/install"
BOOT_ORDER="$ROOT/server/boot-order"
GRUB_UPDATE="$ROOT/server/grub-update"
GRUB_OTHER_OS="$ROOT/server/grub-other-os"
LIVE_WORLD="$ROOT/server/live-world.txt"
TARGET_PACKAGES="$ROOT/server/packages.txt"
BUILD="$ROOT/server/build-dexos-server.sh"
ARGON_THEME="$ROOT/server/assets/argon-grub-theme"
WEB_ROOT="$ROOT/server/web"
LIVE_HELPER="$ROOT/server/dex-installer-live"
LIVE_SERVICE="$ROOT/server/openrc/dex-installer-live"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

sh -n "$INSTALLER"
sh -n "$BOOT_ORDER"
sh -n "$GRUB_UPDATE"
sh -n "$GRUB_OTHER_OS"
sh -n "$OVERLAY"
sh -n "$LIVE_HELPER"
sh -n "$LIVE_SERVICE"
for cgi in "$WEB_ROOT"/cgi-bin/*.cgi; do sh -n "$cgi"; done
if command -v node >/dev/null 2>&1; then node --check "$WEB_ROOT/app.js" >/dev/null; fi
bash -n "$BUILD"
pass "sintaxis shell y frontend"

[ -f "$ARGON_THEME/theme.txt" ] || fail "falta theme.txt de Argon"
[ -f "$ARGON_THEME/background.png" ] || fail "falta background.png de Argon"
[ -f "$ARGON_THEME/LICENCE.txt" ] || fail "falta licencia de Argon"
grep -Fq 'desktop-image: "background.png"' "$ARGON_THEME/theme.txt" || fail "tema Argon no referencia su fondo"
grep -Fq '+ boot_menu {' "$ARGON_THEME/theme.txt" || fail "tema Argon no define menú gráfico"
pass "assets Argon de GRUB"

[ -s "$WEB_ROOT/index.html" ] || fail "falta UI web"
[ -s "$WEB_ROOT/app.js" ] || fail "falta lógica multistep"
[ -s "$WEB_ROOT/vendor/tailwindcss-3.4.17.js" ] || fail "Tailwind local ausente"
[ -s "$WEB_ROOT/vendor/lucide-0.468.0.min.js" ] || fail "Lucide local ausente"
[ -s "$WEB_ROOT/vendor/TAILWIND-LICENSE.txt" ] || fail "licencia Tailwind ausente"
[ -s "$WEB_ROOT/vendor/LUCIDE-LICENSE.txt" ] || fail "licencia Lucide ausente"
grep -Fq 'src="/vendor/tailwindcss-3.4.17.js"' "$WEB_ROOT/index.html" || fail "UI no usa Tailwind local"
grep -Fq 'src="/vendor/lucide-0.468.0.min.js"' "$WEB_ROOT/index.html" || fail "UI no usa iconos locales"
if grep -Eq 'src="https?://|href="https?://' "$WEB_ROOT/index.html"; then fail "UI depende de CDN remoto"; fi
for step in 0 1 2 3 4; do grep -Fq "data-step-panel=\"$step\"" "$WEB_ROOT/index.html" || fail "falta paso web $step"; done
grep -Fq 'Dex-Installer' "$WEB_ROOT/index.html" || fail "UI no documenta hotspot"
grep -Fq 'sin formato' "$WEB_ROOT/index.html" || fail "UI no explica particiones sin formato"
grep -Fq '/cgi-bin/inventory.cgi' "$WEB_ROOT/app.js" || fail "frontend no consulta inventario"
grep -Fq '/cgi-bin/install.cgi' "$WEB_ROOT/app.js" || fail "frontend no ejecuta backend"
grep -Fq 'window.setInterval(loadLiveStatus, 3000)' "$WEB_ROOT/app.js" || fail "frontend no refresca estado del hotspot"
grep -Fq 'ReadableStream' "$WEB_ROOT/app.js" >/dev/null 2>&1 || grep -Fq 'response.body.getReader()' "$WEB_ROOT/app.js" || fail "frontend no transmite progreso"
pass "frontend offline multistep"

for file in "$LIVE_WORLD" "$TARGET_PACKAGES"; do
    [ -s "$file" ] || fail "lista vacía: $file"
done

for pkg in networkmanager networkmanager-openrc networkmanager-wifi networkmanager-cli eudev eudev-openrc openssh avahi avahi-openrc dbus dbus-openrc wpa_supplicant iw wireless-regdb; do
    grep -qx "$pkg" "$LIVE_WORLD" || fail "$pkg falta en Live world"
    grep -qx "$pkg" "$TARGET_PACKAGES" || fail "$pkg falta en sistema instalado"
done
grep -qx doas "$TARGET_PACKAGES" || fail "doas falta en sistema instalado"
for pkg in os-prober ntfs-3g; do
    grep -qx "$pkg" "$TARGET_PACKAGES" || fail "$pkg falta para detectar otros sistemas"
done
for pkg in dnsmasq mini_httpd; do
    grep -qx "$pkg" "$LIVE_WORLD" || fail "$pkg falta en Live para instalador web"
    if grep -qx "$pkg" "$TARGET_PACKAGES"; then fail "$pkg no debe instalarse en el sistema final"; fi
done
for pkg in linux-firmware-intel linux-firmware-airoha linux-firmware-atmel linux-firmware-mrvl linux-firmware-nxp linux-firmware-other; do
    grep -qx "$pkg" "$LIVE_WORLD" || fail "$pkg falta para ampliar soporte Wi-Fi Live"
    grep -qx "$pkg" "$TARGET_PACKAGES" || fail "$pkg falta para Wi-Fi del sistema instalado"
done
pass "red, SSH, Avahi, administración, instalador web y dual boot presentes"

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
grep -Fq 'cp /work/server/grub-update "$tmp/usr/local/sbin/grub-update"' "$OVERLAY" || fail "overlay no instala grub-update"
grep -Fq 'ln -s grub-update "$tmp/usr/local/sbin/update-grub"' "$OVERLAY" || fail "overlay no ofrece alias update-grub"
grep -Fq 'cp /work/server/grub-other-os "$tmp/usr/share/dexos/grub.d/31_dexos_other_os"' "$OVERLAY" || fail "overlay no incluye detector GRUB fallback"
grep -Fq 'cp -a "$ARGON_ASSET/." "$tmp/usr/share/dexos/argon-grub-theme/"' "$OVERLAY" || fail "overlay no incluye el tema Argon"
grep -Fq 'cp -a "$WEB_ASSET/." "$tmp/usr/share/dexos/installer-web/"' "$OVERLAY" || fail "overlay no incluye frontend web"
grep -Fq 'dex-installer-live sshd avahi-daemon' "$OVERLAY" || fail "servicio de instalador Live no arranca antes de SSH/Avahi"
grep -Fq 'hostname="dexos-installer"' "$PROFILE" || fail "Live no usa hostname dexos-installer"
grep -Fq 'udev udev-trigger udev-settle' "$OVERLAY" || fail "coldplug udev no habilitado en Live"
grep -Fq 'networkmanager dex-installer-live sshd avahi-daemon udev-postmount' "$OVERLAY" || fail "servicios Server no habilitados en Live"
grep -Fq 'rc-manager=file' "$OVERLAY" || fail "NetworkManager Live no administra resolv.conf"
grep -Fq 'dexos-wired.nmconnection' "$OVERLAY" || fail "Live no tiene Ethernet DHCP automático"
grep -Fq 'https://dl-cdn.alpinelinux.org/alpine/edge/main' "$OVERLAY" || fail "repositorio main falta en Live"
grep -Fq 'https://dl-cdn.alpinelinux.org/alpine/edge/community' "$OVERLAY" || fail "repositorio community falta en Live"
grep -Fq 'SSID=Dex-Installer' "$LIVE_HELPER" || fail "helper no define SSID temporal"
grep -Fq 'AP_IP=10.42.0.1' "$LIVE_HELPER" || fail "helper no define IP cautiva"
grep -Fq '802-11-wireless.mode ap' "$LIVE_HELPER" || fail "helper no configura modo AP"
grep -Fq 'address=/#/$AP_IP' "$LIVE_HELPER" || fail "DNS cautivo no redirige al instalador"
grep -Fq 'mini_httpd' "$LIVE_HELPER" || fail "helper no inicia servidor web"
grep -Fq 'list_wifi_devices' "$LIVE_HELPER" || fail "helper no inventaría Wi-Fi por nmcli+iw"
grep -Fq 'wifi_supports_ap' "$LIVE_HELPER" || fail "helper no valida capacidad AP"
grep -Fq 'rfkill unblock all' "$LIVE_HELPER" || fail "helper no desbloquea radio Wi-Fi"
grep -Fq 'start_hotspot_watch' "$LIVE_HELPER" || fail "helper no mantiene monitor de hotplug"
grep -Fq 'wpa_supplicant -B -u -P' "$LIVE_HELPER" || fail "Live no inicia wpa_supplicant D-Bus global para NetworkManager"
grep -Fq 'sleep 2' "$LIVE_HELPER" || fail "monitor Wi-Fi no reintenta"
grep -Fq 'NetworkManager no pudo activar el AP' "$LIVE_HELPER" || fail "hotspot no deja diagnóstico de activación"
grep -Fq "printf 'root:root" "$LIVE_SERVICE" || fail "Live no establece credencial temporal root/root"
grep -Fq 'before networkmanager sshd avahi-daemon' "$LIVE_SERVICE" || fail "supplicant/portal no se preparan antes de NetworkManager/SSH"
# Exercise the hotspot path with a fake Wi-Fi adapter. QEMU does not emulate
# mac80211 hardware, so this validates detection/AP orchestration deterministically.
MOCK=$(mktemp -d)
trap 'rm -rf "$MOCK" /run/dex-installer-live.status /run/dex-installer-dnsmasq.pid /run/dex-installer-dnsmasq.conf' EXIT HUP INT TERM
cat > "$MOCK/nmcli" <<'EOF'
#!/bin/sh
case "$*" in
  *'-t -f DEVICE,TYPE device status'*) echo 'wlan-test:wifi' ;;
  *'general status'*) echo 'STATE:connected' ;;
esac
exit 0
EOF
cat > "$MOCK/iw" <<'EOF'
#!/bin/sh
if [ "$1" = dev ] && [ $# -eq 1 ]; then
  printf 'phy#0\n\tInterface wlan-test\n'
elif [ "$1" = dev ] && [ "$2" = wlan-test ] && [ "$3" = info ]; then
  printf 'Interface wlan-test\n\twiphy 0\n\ttype AP\n'
elif [ "$1" = phy ]; then
  printf 'Wiphy phy0\n\tSupported interface modes:\n\t\t * managed\n\t\t * AP\n\tBand 1:\n'
fi
EOF
cat > "$MOCK/ip" <<'EOF'
#!/bin/sh
case "$*" in
  '-4 addr show dev wlan-test') echo '3: wlan-test    inet 10.42.0.1/24 brd 10.42.0.255 scope global wlan-test' ;;
esac
exit 0
EOF
cat > "$MOCK/dnsmasq" <<'EOF'
#!/bin/sh
for arg in "$@"; do
  case "$arg" in --pid-file=*) printf '%s\n' "$$" > "${arg#--pid-file=}" ;; esac
done
exit 0
EOF
cat > "$MOCK/rfkill" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$MOCK"/*
rm -f /run/dex-installer-live.status /run/dex-installer-dnsmasq.pid /run/dex-installer-dnsmasq.conf
PATH="$MOCK:$PATH" "$LIVE_HELPER" retry >/dev/null 2>&1 || fail "hotspot simulado no pudo activarse"
grep -Fq 'HOTSPOT=active' /run/dex-installer-live.status || fail "hotspot simulado no queda activo"
grep -Fq 'WIFI_DEVICE=wlan-test' /run/dex-installer-live.status || fail "hotspot simulado no conserva adaptador"
rm -rf "$MOCK" /run/dex-installer-live.status /run/dex-installer-dnsmasq.pid /run/dex-installer-dnsmasq.conf
trap - EXIT HUP INT TERM
pass "overlay Live y hotspot temporal con detección/reintento"

grep -Fq 'apk add --simulate --no-network --repositories-file /dev/null' "$INSTALLER" || fail "preflight offline estricto ausente"
grep -Fq 'apk add --root "$TARGET"' "$INSTALLER" || fail "instalación apk --root ausente"
grep -Fq -- '--no-network --repositories-file /dev/null' "$INSTALLER" || fail "instalación no aísla los repositorios online"
grep -Fq -- '--repository "$repo"' "$INSTALLER" || fail "instalación no usa el repositorio de la ISO"
grep -Fq 'nmcli device wifi connect' "$INSTALLER" || fail "asistente Wi-Fi no usa nmcli"
grep -Fq 'udev udev-trigger udev-settle' "$INSTALLER" || fail "coldplug udev no configurado en sistema instalado"
grep -Fq 'networkmanager sshd avahi-daemon udev-postmount' "$INSTALLER" || fail "servicios instalados no configurados"
grep -Fq 'rc-manager=file' "$INSTALLER" || fail "NetworkManager instalado no administra resolv.conf"
grep -Fq 'dexos-wired.nmconnection' "$INSTALLER" || fail "sistema instalado no tiene Ethernet DHCP automático"
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
grep -Fq -- '--inventory' "$INSTALLER" || fail "falta inventario para frontend"
grep -Fq -- '--batch' "$INSTALLER" || fail "falta modo batch para frontend"
grep -Fq "fs='<sin formato>'" "$INSTALLER" || fail "terminal no etiqueta particiones sin formato"
grep -Fq "fs='sin-formato'" "$INSTALLER" || fail "inventario no etiqueta particiones sin formato"
grep -Fq 'never require FSTYPE' "$INSTALLER" || fail "selector no documenta independencia de FSTYPE"
grep -Fq 'udevadm settle --timeout=5' "$INSTALLER" || fail "inventario no espera coldplug de particiones"
grep -Fq 'root_partition_reason' "$INSTALLER" || fail "batch no reutiliza reglas de selección"
grep -Fq 'DEXOS_CONFIRM=INSTALLAR' "$INSTALLER" || fail "batch no exige confirmación explícita"
grep -Fq '*dex-installer*) continue' "$INSTALLER" || fail "hotspot Live podría persistirse al target"
grep -Fq 'GRUB_DISABLE_OS_PROBER=false' "$INSTALLER" || fail "os-prober no está habilitado en GRUB"
grep -Fq 'GRUB_THEME="/boot/grub/themes/argon/theme.txt"' "$INSTALLER" || fail "GRUB instalado no usa tema Argon"
grep -Fq 'GRUB_GFXMODE="1920x1080,auto"' "$INSTALLER" || fail "GRUB instalado no usa resolución Argon"
grep -Fq 'GRUB_GFXPAYLOAD_LINUX=keep' "$INSTALLER" || fail "GRUB instalado no conserva gfxpayload"
grep -Fq 'install_grub_theme' "$INSTALLER" || fail "instalador no copia tema Argon al target"
grep -Fq 'cp -a "$src/." "$dst/"' "$INSTALLER" || fail "instalador no copia todos los assets Argon"
grep -Fq '/usr/bin/os-prober' "$INSTALLER" || fail "otros sistemas no se detectan"
grep -Fq '/etc/grub.d/31_dexos_other_os' "$INSTALLER" || fail "instalador no instala detector GRUB fallback"
grep -Fq '/usr/local/sbin/grub-update' "$INSTALLER" || fail "instalador no usa grub-update"
grep -Fq 'ln -sf grub-update "$TARGET/usr/local/sbin/update-grub"' "$INSTALLER" || fail "instalador no ofrece alias update-grub"
grep -Fq 'linux-boot-prober' "$GRUB_OTHER_OS" || fail "fallback no comprueba si os-prober ya generará Linux"
grep -Fq 'configfile $cfg' "$GRUB_OTHER_OS" || fail "fallback no reutiliza el GRUB propio de otros Linux"
grep -Fq 'bootmgfw.efi' "$GRUB_OTHER_OS" || fail "fallback no detecta Windows UEFI"
grep -Fq 'chainloader $path' "$GRUB_OTHER_OS" || fail "fallback no genera chainloader EFI"
grep -Fq 'root=UUID=$root_uuid' "$GRUB_OTHER_OS" || fail "fallback Linux no usa UUID de raíz"
grep -Fq 'mount -o ro,noload' "$GRUB_OTHER_OS" || fail "fallback no monta ext de otros SO de forma segura"
grep -Fq 'grub-mkconfig -o "$tmp"' "$GRUB_UPDATE" || fail "grub-update no regenera grub.cfg de forma atómica"
grep -Fq 'grub-script-check "$tmp"' "$GRUB_UPDATE" || fail "grub-update no valida la sintaxis antes de publicar grub.cfg"
grep -Fq 'ensure_block_node' "$INSTALLER" || fail "falta reparación robusta de nodos de partición"
grep -Fq 'mknod "$path"' "$INSTALLER" || fail "no se corrige el race de /dev/vda3"
if grep -Fq 'BORRAR $disk' "$INSTALLER"; then fail "el instalador aún exige escribir BORRAR"; fi
if grep -Fq 'setup-alpine' "$INSTALLER"; then fail "el instalador propio depende de setup-alpine"; fi
grep -Fq 'grub-set-default' "$BOOT_ORDER" || fail "boot-order no cambia el arranque predeterminado"
grep -Fq 'REQUEST_METHOD' "$WEB_ROOT/cgi-bin/install.cgi" || fail "CGI no restringe método"
grep -Fq 'CONTENT_LENGTH' "$WEB_ROOT/cgi-bin/install.cgi" || fail "CGI no limita payload"
grep -Fq '/usr/local/sbin/install --batch' "$WEB_ROOT/cgi-bin/install.cgi" || fail "CGI no delega al instalador validado"
grep -Fq '/usr/local/sbin/install --inventory' "$WEB_ROOT/cgi-bin/inventory.cgi" || fail "CGI no usa inventario común"
pass "flujo terminal/web, particiones sin formato, coexistencia y boot-order"

if grep -R -E 'Gtk|py3-gobject|xorg-server|xfce4|lightdm' "$ROOT/server" --exclude='test-server.sh' >/dev/null 2>&1; then
    fail "dependencia gráfica detectada dentro de server/"
fi
pass "server/ no depende de GUI"

echo "DexOS Server static tests: PASS"
