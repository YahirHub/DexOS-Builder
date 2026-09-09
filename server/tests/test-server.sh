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
CAPTIVE="$ROOT/server/web/captive-redirect"
INSTALLED_ASSET="$ROOT/server/installed"
WIFI_TUI="$ROOT/server/wifi-tui/main.go"
WIFI_TUI_TEST="$ROOT/server/wifi-tui/main_test.go"
WIFI_BOOT_HELPER="$INSTALLED_ASSET/dexos-wifi-connect"
WIFI_BOOT_SERVICE="$INSTALLED_ASSET/dexos-wifi-autoconnect"
GRUB_THEME_GEN="$INSTALLED_ASSET/05_dexos_theme"
GRUB_PRIMARY="$INSTALLED_ASSET/09_dexos_linux"
DISKINFO="$INSTALLED_ASSET/diskinfo"
DISKINFO_PROFILE="$INSTALLED_ASSET/10-dexos-diskinfo.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

sh -n "$INSTALLER"
sh -n "$BOOT_ORDER"
sh -n "$GRUB_UPDATE"
sh -n "$GRUB_OTHER_OS"
sh -n "$OVERLAY"
sh -n "$LIVE_HELPER"
sh -n "$LIVE_SERVICE"
sh -n "$CAPTIVE"
sh -n "$WIFI_BOOT_HELPER"
sh -n "$WIFI_BOOT_SERVICE"
sh -n "$GRUB_THEME_GEN"
sh -n "$GRUB_PRIMARY"
sh -n "$DISKINFO"
[ -s "$WIFI_TUI" ] || fail "falta fuente del Wi-Fi TUI"
[ -s "$WIFI_TUI_TEST" ] || fail "faltan pruebas del Wi-Fi TUI"
if command -v go >/dev/null 2>&1; then (cd "$ROOT" && GO111MODULE=off go test ./server/wifi-tui >/dev/null); fi
for cgi in "$WEB_ROOT"/cgi-bin/*.cgi; do sh -n "$cgi"; done
if command -v node >/dev/null 2>&1; then node --check "$WEB_ROOT/app.js" >/dev/null; fi
bash -n "$BUILD"
grep -Fq "if '-comp xz' not in s" "$BUILD" || fail "build no fija SquashFS/XZ como invariante"
grep -Fq 'using cached APKINDEX after transient mirror failure' "$BUILD" || fail "build no tolera fallo transitorio del mirror con índice cacheado"
grep -Fq 'x86|x86_64) mksfs="-Xbcj x86"' "$ROOT/alpine-root/usr/sbin/update-kernel" || fail "modloop no usa filtro BCJ x86 con XZ"
pass "sintaxis shell, frontend y SquashFS/XZ"

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
grep -Fq 'http://dex.local/' "$WEB_ROOT/index.html" || fail "UI no publica dex.local"
if grep -Fq 'dexos-installer.local' "$WEB_ROOT/index.html" "$WEB_ROOT/app.js" "$LIVE_HELPER" "$OVERLAY" "$PROFILE"; then fail "quedó el dominio Live antiguo"; fi
grep -Fq 'sin formato' "$WEB_ROOT/index.html" || fail "UI no explica particiones sin formato"
grep -Fq 'overflow-x: hidden' "$WEB_ROOT/index.html" || fail "UI móvil no bloquea overflow horizontal"
grep -Fq 'sm:flex-row sm:items-center' "$WEB_ROOT/app.js" || fail "tarjetas de discos/particiones no se apilan en móvil"
grep -Fq '/cgi-bin/inventory.cgi' "$WEB_ROOT/app.js" || fail "frontend no consulta inventario"
grep -Fq "f[0] === 'FREE'" "$WEB_ROOT/app.js" || fail "frontend no interpreta espacio no asignado"
grep -Fq 'Espacio no asignado' "$WEB_ROOT/app.js" || fail "frontend no muestra huecos libres"
grep -Fq 'root_free_start' "$WEB_ROOT/app.js" || fail "frontend no envía inicio de espacio libre"
grep -Fq 'root_free_sectors' "$WEB_ROOT/app.js" || fail "frontend no envía tamaño de espacio libre"
grep -Fq '/cgi-bin/install.cgi' "$WEB_ROOT/app.js" || fail "frontend no ejecuta backend"
[ ! -e "$WEB_ROOT/cgi-bin/network.cgi" ] || fail "el Live todavía intenta conectar Wi-Fi desde el navegador"
[ -x "$WEB_ROOT/cgi-bin/reboot.cgi" ] || fail "falta CGI de reinicio"
grep -Fq 'id="install-wifi-ssid"' "$WEB_ROOT/index.html" || fail "UI no pide SSID para el sistema instalado"
grep -Fq 'id="install-wifi-password"' "$WEB_ROOT/index.html" || fail "UI no pide contraseña Wi-Fi"
grep -Fq 'después del primer reinicio' "$WEB_ROOT/index.html" || fail "UI no explica que Wi-Fi se conecta después de reiniciar"
grep -Fq 'id="reboot-btn"' "$WEB_ROOT/index.html" || fail "UI no ofrece reiniciar al finalizar"
grep -Fq '[hidden] { display: none !important; }' "$WEB_ROOT/index.html" || fail "atributo hidden puede ser anulado por clases Tailwind"
if grep -Fq '/cgi-bin/network.cgi' "$WEB_ROOT/app.js"; then fail "frontend aún intenta conectar el Live a Wi-Fi"; fi
grep -Fq 'wifi_ssid: v.wifiSsid' "$WEB_ROOT/app.js" || fail "frontend no envía SSID diferido"
grep -Fq 'wifi_password: v.wifiPassword' "$WEB_ROOT/app.js" || fail "frontend no envía contraseña diferida"
grep -Fq '/cgi-bin/reboot.cgi' "$WEB_ROOT/app.js" || fail "frontend no usa backend de reinicio"
grep -Fq "\$('wizard-footer').hidden = state.step === 4" "$WEB_ROOT/app.js" || fail "footer/siguiente sigue visible durante instalación"
grep -Fq 'window.setInterval(loadLiveStatus, 3000)' "$WEB_ROOT/app.js" || fail "frontend no refresca estado del hotspot"
grep -Fq 'ReadableStream' "$WEB_ROOT/app.js" >/dev/null 2>&1 || grep -Fq 'response.body.getReader()' "$WEB_ROOT/app.js" || fail "frontend no transmite progreso"
for endpoint in generate_204 gen_204 hotspot-detect.html connecttest.txt ncsi.txt check_network_status.txt redirect canonical.html success.txt library/test/success.html kindle-wifi/wifistub.html; do
    [ -x "$WEB_ROOT/$endpoint" ] || fail "endpoint cautivo no ejecutable: $endpoint"
done
grep -Fq 'Status: 302 Found' "$CAPTIVE" || fail "portal cautivo no responde con redirect HTTP"
grep -Fq 'Location: http://dex.local/' "$CAPTIVE" || fail "portal cautivo no redirige a dex.local"
grep -Fq '**generate_204' "$LIVE_HELPER" || fail "mini_httpd no ejecuta generate_204 como CGI"
pass "frontend offline multistep y portal cautivo HTTP"

for file in "$LIVE_WORLD" "$TARGET_PACKAGES"; do
    [ -s "$file" ] || fail "lista vacía: $file"
done

for pkg in networkmanager networkmanager-openrc networkmanager-wifi networkmanager-cli eudev eudev-openrc openssh avahi avahi-openrc dbus dbus-openrc wpa_supplicant iw wireless-regdb; do
    grep -qx "$pkg" "$LIVE_WORLD" || fail "$pkg falta en Live world"
    grep -qx "$pkg" "$TARGET_PACKAGES" || fail "$pkg falta en sistema instalado"
done
grep -qx doas "$TARGET_PACKAGES" || fail "doas falta en sistema instalado"
for file in "$LIVE_WORLD" "$TARGET_PACKAGES"; do grep -qx bash "$file" || fail "bash falta en $file"; done
grep -Fq 'busybox-extras bash ca-certificates' "$PROFILE" || fail "bash no está en el repositorio offline del perfil"
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
grep -Fq 'cp -a "$INSTALLED_ASSET/." "$tmp/usr/share/dexos/installed/"' "$OVERLAY" || fail "overlay no incluye herramientas del sistema instalado"
grep -Fq 'GENERATED_WIFI=/work/cache/generated-installed/wifi' "$OVERLAY" || fail "overlay no usa Wi-Fi TUI compilado"
grep -Fq 'cp "$GENERATED_WIFI" "$tmp/usr/share/dexos/installed/wifi"' "$OVERLAY" || fail "overlay no publica el binario wifi"
grep -Fq 'go build -trimpath' "$BUILD" || fail "build no compila el Wi-Fi TUI"
grep -Fq 'Instalar Alpine Linux' "$BUILD" || fail "GRUB Live no muestra la opción de instalación"
grep -Fq 'boot/grub/themes/argon' "$BUILD" || fail "GRUB Live no copia el tema Argon"
grep -Fq 'terminal_output gfxterm' "$BUILD" || fail "GRUB Live no fuerza salida gráfica"
grep -Fq 'set gfxmode=1920x1080,auto' "$BUILD" || fail "GRUB Live no usa la resolución Argon validada"
grep -Fq 'dex-installer-live sshd avahi-daemon' "$OVERLAY" || fail "servicio de instalador Live no arranca antes de SSH/Avahi"
grep -Fq 'hostname="dex"' "$PROFILE" || fail "Live no usa hostname dex"
grep -Fq 'udev udev-trigger udev-settle' "$OVERLAY" || fail "coldplug udev no habilitado en Live"
grep -Fq 'networkmanager dex-installer-live sshd avahi-daemon udev-postmount' "$OVERLAY" || fail "servicios Server no habilitados en Live"
grep -Fq 'rc-manager=file' "$OVERLAY" || fail "NetworkManager Live no administra resolv.conf"
grep -Fq 'dexos-wired.nmconnection' "$OVERLAY" || fail "Live no tiene Ethernet DHCP automático"
grep -Fq 'https://dl-cdn.alpinelinux.org/alpine/edge/main' "$OVERLAY" || fail "repositorio main falta en Live"
grep -Fq 'https://dl-cdn.alpinelinux.org/alpine/edge/community' "$OVERLAY" || fail "repositorio community falta en Live"
grep -Fq 'SSID=Dex-Installer' "$LIVE_HELPER" || fail "helper no define SSID temporal"
grep -Fq 'MDNS=dex.local' "$LIVE_HELPER" || fail "helper no publica dex.local"
grep -Fq 'AP_IP=10.42.0.1' "$LIVE_HELPER" || fail "helper no define IP cautiva"
grep -Fq '802-11-wireless.mode ap' "$LIVE_HELPER" || fail "helper no configura modo AP"
grep -Fq 'local=/#/' "$LIVE_HELPER" || fail "DNS cautivo puede rechazar consultas AAAA sin upstream"
grep -Fq 'address=/#/$AP_IP' "$LIVE_HELPER" || fail "DNS cautivo no redirige al instalador"
grep -Fq 'mini_httpd' "$LIVE_HELPER" || fail "helper no inicia servidor web"
grep -Fq 'list_wifi_devices' "$LIVE_HELPER" || fail "helper no inventaría Wi-Fi por nmcli+iw"
grep -Fq 'wifi_supports_ap' "$LIVE_HELPER" || fail "helper no valida capacidad AP"
grep -Fq 'rfkill unblock all' "$LIVE_HELPER" || fail "helper no desbloquea radio Wi-Fi"
grep -Fq 'start_hotspot_watch' "$LIVE_HELPER" || fail "helper no mantiene monitor de hotplug"
grep -Fq 'wpa_supplicant -B -u -P' "$LIVE_HELPER" || fail "Live no inicia wpa_supplicant D-Bus global para NetworkManager"
grep -Fq 'sleep 2' "$LIVE_HELPER" || fail "monitor Wi-Fi no reintenta"
grep -Fq 'NetworkManager no pudo activar el AP' "$LIVE_HELPER" || fail "hotspot no deja diagnóstico de activación"
if grep -Eq 'VIRTUAL_STA|dexsta0|WIFI_PROFILE="DexOS WiFi"' "$LIVE_HELPER"; then fail "Live conserva lógica AP+STA que ya no se usa"; fi
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
if grep -Fq 'nmcli device wifi connect' "$INSTALLER"; then fail "instalador Live todavía intenta conectarse a Wi-Fi"; fi
grep -Fq 'DEXOS_WIFI_SSID' "$INSTALLER" || fail "batch no recibe SSID diferido"
grep -Fq 'dexos-wifi.nmconnection' "$INSTALLER" || fail "instalador no crea perfil Wi-Fi persistente"
grep -Fq 'autoconnect=true' "$INSTALLER" || fail "perfil Wi-Fi no queda en autoconnect"
grep -Fq 'autoconnect-retries=0' "$INSTALLER" || fail "NetworkManager no reintenta Wi-Fi indefinidamente"
grep -Fq 'hidden=true' "$INSTALLER" || fail "perfil Wi-Fi no habilita sondeo activo"
grep -Fq 'rc-update add dexos-wifi-autoconnect default' "$INSTALLER" || fail "servicio de autoconexión Wi-Fi no se habilita"
grep -Fq 'key-mgmt=wpa-psk' "$INSTALLER" || fail "perfil Wi-Fi protegido no configura WPA-PSK"
if grep -Fq 'wifi-firstboot.conf' "$INSTALLER"; then fail "instalador conserva configuración Wi-Fi transitoria"; fi
if grep -Fq 'dexos-wifi-firstboot' "$INSTALLER"; then fail "instalador sigue habilitando servicio Wi-Fi de primer arranque"; fi
grep -Fq 'udev udev-trigger udev-settle' "$INSTALLER" || fail "coldplug udev no configurado en sistema instalado"
grep -Fq 'networkmanager sshd avahi-daemon udev-postmount' "$INSTALLER" || fail "servicios instalados no configurados"
grep -Fq 'rc-manager=file' "$INSTALLER" || fail "NetworkManager instalado no administra resolv.conf"
grep -Fq 'dexos-wired.nmconnection' "$INSTALLER" || fail "sistema instalado no tiene Ethernet DHCP automático"
grep -Fq 'rc_need="wpa_supplicant"' "$INSTALLER" || fail "NetworkManager instalado no espera wpa_supplicant"
grep -Fq 'rc-update add wpa_supplicant default' "$INSTALLER" || fail "wpa_supplicant no se habilita en el sistema instalado"
grep -Fq '/etc/apk/repositories' "$INSTALLER" || fail "repositorios instalados no configurados"
grep -Fq '/sbin/mkinitfs' "$INSTALLER" || fail "initramfs no se genera explícitamente"
grep -Fq 'root=UUID=$root_uuid' "$INSTALLER" || fail "GRUB no fija root por UUID"
grep -Fq 'mkfs.ext4 -F -L DexOS-Server' "$INSTALLER" || fail "raíz no se formatea explícitamente como ext4"
grep -Fq 'blkid -p -s TYPE -o value "$part"' "$INSTALLER" || fail "instalador no verifica el tipo ext4 después de formatear"
grep -Fq '[ "$root_fstype" = ext4 ]' "$INSTALLER" || fail "instalador no aborta si la raíz no queda ext4"
grep -Fq 'findmnt -nro FSTYPE "$TARGET"' "$INSTALLER" || fail "instalador no verifica ext4 después de montar"
grep -Fq 'system-connections' "$INSTALLER" || fail "perfiles NetworkManager no se preservan"
grep -Fq 'DexOS Wi-Fi TUI' "$WIFI_TUI" || fail "Wi-Fi no usa TUI interactivo"
grep -Fq '↑/↓ seleccionar' "$WIFI_TUI" || fail "TUI no documenta navegación por flechas"
grep -Fq 'device", "wifi", "connect"' "$WIFI_TUI" || fail "TUI no conecta mediante NetworkManager"
grep -Fq 'nmcliWithInput' "$WIFI_TUI" || fail "TUI no entrega secretos por stdin"
grep -Fq 'safeText' "$WIFI_TUI" || fail "TUI no neutraliza caracteres de control del SSID"
grep -Fq 'connection.autoconnect-retries 0' "$WIFI_BOOT_HELPER" || fail "helper de boot no fija reintentos infinitos"
grep -Fq 'nmcli --wait 35 connection up' "$WIFI_BOOT_HELPER" || fail "helper de boot no activa explícitamente el perfil"
grep -Fq 'nmcli connection load "$PROFILE_FILE"' "$WIFI_BOOT_HELPER" || fail "helper de boot no carga explícitamente el keyfile si NetworkManager lo omite"
grep -Fq 'nmcli general status' "$WIFI_BOOT_HELPER" || fail "helper de boot no espera a que NetworkManager esté realmente listo"
grep -Fq 'NetworkManager no respondió después de 30 s.' "$WIFI_BOOT_HELPER" || fail "helper de boot no limita la espera de NetworkManager"
grep -Fq 'PROFILE_FILE=/etc/NetworkManager/system-connections/dexos-wifi.nmconnection' "$WIFI_BOOT_HELPER" || fail "helper no apunta al keyfile instalado"
grep -Fq '/var/log/dexos-wifi-autoconnect.log' "$WIFI_BOOT_HELPER" || fail "helper de boot no deja diagnóstico"
grep -Fq 'need dbus wpa_supplicant networkmanager' "$WIFI_BOOT_SERVICE" || fail "servicio Wi-Fi no espera backend completo"

# Reproduce the physical-boot race: OpenRC has started the NetworkManager service,
# but nmcli still reports "NetworkManager is not running" for a few moments.
MOCK=$(mktemp -d)
trap 'rm -rf "$MOCK"' EXIT HUP INT TERM
mkdir -p "$MOCK/bin" "$MOCK/etc/NetworkManager/system-connections"
printf dummy > "$MOCK/etc/NetworkManager/system-connections/dexos-wifi.nmconnection"
cp "$WIFI_BOOT_HELPER" "$MOCK/helper"
python3 - "$MOCK/helper" "$MOCK/log" "$MOCK/bin" "$MOCK/etc/NetworkManager/system-connections/dexos-wifi.nmconnection" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); log=sys.argv[2]; bindir=sys.argv[3]; profile=sys.argv[4]
s=p.read_text()
s=s.replace('LOG=/var/log/dexos-wifi-autoconnect.log', f'LOG={log}')
s=s.replace('PROFILE_FILE=/etc/NetworkManager/system-connections/dexos-wifi.nmconnection', f'PROFILE_FILE={profile}')
s=s.replace('PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin', f'PATH={bindir}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin')
p.write_text(s)
PY
cat > "$MOCK/bin/nmcli" <<'EOF'
#!/bin/sh
case "$*" in
  'general status')
    n=0; [ ! -f "$MOCK_NM_STATE" ] || n=$(cat "$MOCK_NM_STATE")
    n=$((n + 1)); printf '%s\n' "$n" > "$MOCK_NM_STATE"
    [ "$n" -ge 4 ] && exit 0
    echo 'Error: NetworkManager is not running.' >&2
    exit 8
    ;;
  'connection reload') exit 0 ;;
  '-t -f NAME connection show') [ -f "$MOCK_PROFILE_LOADED" ] && printf 'DexOS WiFi\n'; exit 0 ;;
  connection\ load\ *) touch "$MOCK_PROFILE_LOADED"; exit 0 ;;
  '-g 802-11-wireless.ssid connection show DexOS WiFi') printf 'Casa-Test\n'; exit 0 ;;
  'connection modify DexOS WiFi connection.autoconnect yes connection.autoconnect-retries 0') exit 0 ;;
  'radio wifi on') exit 0 ;;
  '-t -f DEVICE,TYPE device status') printf 'wlan0:wifi\n'; exit 0 ;;
  '-t -f NAME,TYPE connection show --active') exit 0 ;;
  'device wifi rescan ifname wlan0 ssid Casa-Test') exit 0 ;;
  '--wait 35 connection up DexOS WiFi ifname wlan0') exit 0 ;;
  '-g GENERAL.STATE device show wlan0') printf '100 (connected)\n'; exit 0 ;;
  '-g GENERAL.CONNECTION device show wlan0') printf 'DexOS WiFi\n'; exit 0 ;;
  *) echo "unexpected nmcli call: $*" >&2; exit 3 ;;
esac
EOF
cat > "$MOCK/bin/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$MOCK/helper" "$MOCK/bin/nmcli" "$MOCK/bin/sleep"
MOCK_NM_STATE="$MOCK/nm-state" MOCK_PROFILE_LOADED="$MOCK/profile-loaded" "$MOCK/helper" > "$MOCK/stdout" 2>&1 || fail "helper Wi-Fi no supera la carrera de arranque de NetworkManager"
grep -Fq 'esperando a que NetworkManager acepte comandos' "$MOCK/stdout" || fail "helper Wi-Fi no informa la espera de NetworkManager"
grep -Fq 'NetworkManager listo tras 3s.' "$MOCK/stdout" || fail "helper Wi-Fi no reanuda cuando NetworkManager queda listo"
grep -Fq 'conectado: DexOS WiFi' "$MOCK/stdout" || fail "helper Wi-Fi no continúa hasta activar el perfil después de la carrera"
rm -rf "$MOCK"
trap - EXIT HUP INT TERM
pass "autoconexión Wi-Fi espera la disponibilidad real de NetworkManager"
grep -Fq 'insmod gfxmenu' "$GRUB_THEME_GEN" || fail "generador Argon no carga gfxmenu"
grep -Fq 'search --no-floppy --file --set=dex_theme_root /boot/grub/themes/argon/theme.txt' "$GRUB_THEME_GEN" || fail "generador Argon no localiza la partición del tema"
grep -Fq 'loadfont ($dex_theme_root)/boot/grub/themes/argon/Terminus_16.pf2' "$GRUB_THEME_GEN" || fail "generador Argon no carga fuente 16"
grep -Fq 'loadfont ($dex_theme_root)/boot/grub/themes/argon/Terminus_24.pf2' "$GRUB_THEME_GEN" || fail "generador Argon no carga fuente 24"
grep -Fq 'set theme=($dex_theme_root)/boot/grub/themes/argon/theme.txt' "$GRUB_THEME_GEN" || fail "generador Argon no fija el tema directamente"
grep -Fq 'terminal_output gfxterm' "$GRUB_THEME_GEN" || fail "generador Argon no fuerza gfxterm"
grep -Fq "menuentry 'DexOS Server (Alpine Linux)'" "$GRUB_PRIMARY" || fail "entrada GRUB principal no es explícita"
grep -Fq 'insmod part_msdos' "$GRUB_PRIMARY" || fail "entrada GRUB principal no contempla discos MBR"
grep -Fq 'diskinfo' "$DISKINFO_PROFILE" || fail "dashboard no se ejecuta en login interactivo"
grep -Fq 'ALMACENAMIENTO' "$DISKINFO" || fail "diskinfo no contiene dashboard solicitado"
grep -Fq '10-dexos-diskinfo.sh' "$INSTALLER" || fail "perfil de diskinfo no se instala"
grep -Fq 'Nombre del servidor/mDNS' "$INSTALLER" || fail "falta nombre .local inteligente"
grep -Fq 'case "$name" in *.local)' "$INSTALLER" || fail "no se evita duplicar .local"
grep -Fq '$7="/bin/bash"' "$INSTALLER" || fail "root no usa Bash"
grep -Fq 'adduser -D -s /bin/bash' "$INSTALLER" || fail "usuario administrador no usa Bash"
grep -Fq 'Enter = usar la de $admin_user' "$INSTALLER" || fail "root no puede heredar contraseña"
grep -Fq 'PermitRootLogin $ssh_root_login' "$INSTALLER" || fail "root SSH no es configurable"
grep -Fq 'Coexistir con otro sistema' "$INSTALLER" || fail "falta modo coexistencia"
grep -Fq 'select_root_partition' "$INSTALLER" || fail "falta selector de partición raíz"
grep -Fq 'select_efi_partition' "$INSTALLER" || fail "falta selector de ESP"
grep -Fq 'return 0' "$INSTALLER" || fail "selectores vacíos no garantizan éxito"
if grep -Fq 'set -- $row' "$INSTALLER"; then fail "selector de destino altera argumentos globales del instalador"; fi
grep -Fq 'target_kind target_a target_b target_c' "$INSTALLER" || fail "selector libre no parsea TSV sin tocar argumentos globales"
grep -Fq -- '--inventory' "$INSTALLER" || fail "falta inventario para frontend"
grep -Fq -- '--batch' "$INSTALLER" || fail "falta modo batch para frontend"
grep -Fq "fs='<sin formato>'" "$INSTALLER" || fail "terminal no etiqueta particiones sin formato"
grep -Fq "fs='sin-formato'" "$INSTALLER" || fail "inventario no etiqueta particiones sin formato"
grep -Fq 'partition_nodes_from_table' "$INSTALLER" || fail "selector no enumera la tabla GPT/MBR directamente"
grep -Fq 'partx -g -o NR "$disk"' "$INSTALLER" || fail "selector sigue dependiendo de filesystem/lsblk para descubrir particiones"
grep -Fq 'free_regions_from_table' "$INSTALLER" || fail "instalador no detecta espacio no asignado"
grep -Fq 'sfdisk --list-free "$disk"' "$INSTALLER" || fail "espacio no asignado no se lee desde tabla de particiones"
grep -Fq 'create_root_partition_from_free' "$INSTALLER" || fail "instalador no crea raíz desde espacio libre"
grep -Fq 'sfdisk --append --wipe never --wipe-partitions never' "$INSTALLER" || fail "creación en hueco puede alterar particiones existentes"
grep -Fq "printf 'FREE\\t%s" "$INSTALLER" || fail "inventario no publica huecos libres"
grep -Fq 'is_reserved_windows_guid' "$INSTALLER" || fail "selector no protege MSR/WinRE"
grep -Fq 'udevadm settle --timeout=5' "$INSTALLER" || fail "inventario no espera coldplug de particiones"
grep -Fq 'root_partition_reason' "$INSTALLER" || fail "batch no reutiliza reglas de selección"
grep -Fq 'DEXOS_CONFIRM=INSTALLAR' "$INSTALLER" || fail "batch no exige confirmación explícita"
grep -Fq '*dex-installer*) continue' "$INSTALLER" || fail "hotspot Live podría persistirse al target"
grep -Fq 'GRUB_DISABLE_OS_PROBER=false' "$INSTALLER" || fail "os-prober no está habilitado en GRUB"
grep -Fq 'GRUB_THEME="/boot/grub/themes/argon/theme.txt"' "$INSTALLER" || fail "GRUB instalado no usa tema Argon"
grep -Fq 'GRUB_TERMINAL_OUTPUT="gfxterm"' "$INSTALLER" || fail "GRUB instalado no fuerza gfxterm para Argon"
grep -Fq 'GRUB_GFXMODE="1920x1080,auto"' "$INSTALLER" || fail "GRUB instalado no conserva la resolución Argon validada"
grep -Fq 'GRUB_GFXPAYLOAD_LINUX=keep' "$INSTALLER" || fail "GRUB instalado no conserva gfxpayload"
grep -Fq '05_dexos_theme' "$INSTALLER" || fail "GRUB no instala generador directo del tema Argon"
grep -Fq '09_dexos_linux' "$INSTALLER" || fail "GRUB no instala entrada principal antes de otros sistemas"
grep -Fq 'chmod -x "$TARGET/etc/grub.d/10_linux"' "$INSTALLER" || fail "GRUB estándar duplicaría la entrada principal"
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
grep -Fq 'rm -f "$TARGET/usr/sbin/setup-alpine"' "$INSTALLER" || fail "setup-alpine queda instalado en el sistema final"
grep -Fq 'rm -f /usr/sbin/setup-alpine' "$LIVE_SERVICE" || fail "setup-alpine queda disponible en el Live"
grep -Fq 'grub-set-default' "$BOOT_ORDER" || fail "boot-order no cambia el arranque predeterminado"
grep -Fq 'REQUEST_METHOD' "$WEB_ROOT/cgi-bin/install.cgi" || fail "CGI no restringe método"
grep -Fq 'CONTENT_LENGTH' "$WEB_ROOT/cgi-bin/install.cgi" || fail "CGI no limita payload"
for cgi in "$WEB_ROOT/cgi-bin/install.cgi" "$WEB_ROOT/cgi-bin/inventory.cgi" "$WEB_ROOT/cgi-bin/status.cgi" "$WEB_ROOT/cgi-bin/reboot.cgi"; do
    grep -Fq 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' "$cgi" || fail "CGI sin PATH completo: $cgi"
done
grep -Fq 'DEXOS_WIFI_SSID' "$WEB_ROOT/cgi-bin/install.cgi" || fail "CGI no propaga SSID al instalador"
grep -Fq 'DEXOS_WIFI_PASSWORD' "$WEB_ROOT/cgi-bin/install.cgi" || fail "CGI no propaga contraseña Wi-Fi al instalador"
grep -Fq '/run/dexos-install-complete' "$INSTALLER" || fail "instalador no marca éxito para habilitar reinicio web"
grep -Fq '[ -f /run/dexos-install-complete ]' "$WEB_ROOT/cgi-bin/reboot.cgi" || fail "reinicio web no exige instalación completada"
grep -Fq '/sbin/reboot' "$WEB_ROOT/cgi-bin/reboot.cgi" || fail "CGI de reinicio no reinicia el Live"
grep -Fq 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' "$INSTALLER" || fail "instalador no normaliza PATH"
grep -Fq 'DEXOS_ROOT_FREE_START' "$WEB_ROOT/cgi-bin/install.cgi" || fail "CGI no propaga inicio de hueco libre"
grep -Fq 'DEXOS_ROOT_FREE_SECTORS' "$WEB_ROOT/cgi-bin/install.cgi" || fail "CGI no propaga tamaño de hueco libre"
grep -Fq '/usr/local/sbin/install --batch' "$WEB_ROOT/cgi-bin/install.cgi" || fail "CGI no delega al instalador validado"
grep -Fq '/usr/local/sbin/install --inventory' "$WEB_ROOT/cgi-bin/inventory.cgi" || fail "CGI no usa inventario común"
pass "flujo terminal/web, particiones sin formato, coexistencia y boot-order"

if grep -R -E 'Gtk|py3-gobject|xorg-server|xfce4|lightdm' "$ROOT/server" --exclude='test-server.sh' >/dev/null 2>&1; then
    fail "dependencia gráfica detectada dentro de server/"
fi
pass "server/ no depende de GUI"

echo "DexOS Server static tests: PASS"
