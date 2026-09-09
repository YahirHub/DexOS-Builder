#!/bin/sh
set -eu
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
set -f

reply_error() {
    printf 'Status: 400 Bad Request\r\n'
    printf 'Content-Type: text/plain; charset=utf-8\r\n'
    printf 'Cache-Control: no-store\r\n\r\n'
    printf 'ERROR: %s\n' "$1"
    exit 1
}

[ "${REQUEST_METHOD:-}" = POST ] || reply_error 'Usa POST.'
length=${CONTENT_LENGTH:-0}
case "$length" in ''|*[!0-9]*) reply_error 'CONTENT_LENGTH inválido.' ;; esac
[ "$length" -le 32768 ] || reply_error 'Solicitud demasiado grande.'

body=$(dd bs=1 count="$length" 2>/dev/null || true)

urldecode() {
    encoded=$(printf '%s' "$1" | sed 's/+/ /g; s/%/\\x/g')
    printf '%b' "$encoded"
}

hostname=''
admin_user=''
admin_password=''
root_password=''
ssh_root_login='no'
timezone='UTC'
wifi_ssid=''
wifi_password=''
wifi_has_password='no'
install_mode=''
disk=''
root_part=''
root_free_start=''
root_free_sectors=''
efi_part=''
confirm=''

oldifs=$IFS
IFS='&'
set -- $body
IFS=$oldifs
for pair in "$@"; do
    key=${pair%%=*}
    value=${pair#*=}
    [ "$pair" != "$key" ] || value=''
    key=$(urldecode "$key")
    value=$(urldecode "$value")
    case "$key" in
        hostname) hostname=$value ;;
        admin_user) admin_user=$value ;;
        admin_password) admin_password=$value ;;
        root_password) root_password=$value ;;
        ssh_root_login) ssh_root_login=$value ;;
        timezone) timezone=$value ;;
        wifi_ssid) wifi_ssid=$value ;;
        wifi_password) wifi_password=$value ;;
        wifi_has_password) wifi_has_password=$value ;;
        install_mode) install_mode=$value ;;
        disk) disk=$value ;;
        root_part) root_part=$value ;;
        root_free_start) root_free_start=$value ;;
        root_free_sectors) root_free_sectors=$value ;;
        efi_part) efi_part=$value ;;
        confirm) confirm=$value ;;
    esac
done

for value in "$hostname" "$admin_user" "$admin_password" "$root_password" "$ssh_root_login" "$timezone" "$wifi_ssid" "$wifi_password" "$wifi_has_password" "$install_mode" "$disk" "$root_part" "$root_free_start" "$root_free_sectors" "$efi_part" "$confirm"; do
    if printf '%s' "$value" | LC_ALL=C grep -q '[[:cntrl:]]'; then
        reply_error 'La solicitud contiene caracteres de control.'
    fi
done

[ "$confirm" = INSTALLAR ] || reply_error 'Confirma la instalación desde el último paso.'
case "$wifi_has_password" in yes|no) ;; *) reply_error 'Estado de contraseña Wi-Fi inválido.' ;; esac
if [ -z "$wifi_ssid" ] && [ -n "$wifi_password" ]; then reply_error 'Escribe el nombre de la red Wi-Fi o borra la contraseña.'; fi
if [ "$wifi_has_password" = yes ] && [ -z "$wifi_password" ]; then reply_error 'La contraseña Wi-Fi se perdió antes de iniciar la instalación. Vuelve al primer paso y escríbela de nuevo.'; fi
if [ "$wifi_has_password" = no ] && [ -n "$wifi_password" ]; then reply_error 'El estado de la contraseña Wi-Fi no coincide con el formulario.'; fi
if [ -n "$wifi_ssid" ]; then
    [ "$(printf '%s' "$wifi_ssid" | wc -c | tr -d ' ')" -le 32 ] || reply_error 'El SSID Wi-Fi supera 32 bytes.'
    if [ -n "$wifi_password" ]; then
        pwlen=${#wifi_password}
        [ "$pwlen" -ge 8 ] && [ "$pwlen" -le 64 ] || reply_error 'La contraseña Wi-Fi debe tener entre 8 y 64 caracteres.'
        if [ "$pwlen" -eq 64 ]; then printf '%s' "$wifi_password" | grep -Eq '^[0-9A-Fa-f]{64}$' || reply_error 'Una clave Wi-Fi de 64 caracteres debe ser hexadecimal.'; fi
    fi
fi
case "$disk" in /dev/[[:alnum:]_.-]*) ;; *) reply_error 'Disco inválido.' ;; esac
case "$root_part" in ''|/dev/[[:alnum:]_.-]*) ;; *) reply_error 'Partición raíz inválida.' ;; esac
case "$root_free_start:$root_free_sectors" in
    :) ;;
    *[!0-9:]*|:*|*:) reply_error 'Espacio no asignado inválido.' ;;
esac
if [ -n "$root_part" ] && { [ -n "$root_free_start" ] || [ -n "$root_free_sectors" ]; }; then
    reply_error 'Elige una partición existente o espacio no asignado, no ambos.'
fi
case "$efi_part" in ''|none|/dev/[[:alnum:]_.-]*) ;; *) reply_error 'ESP inválida.' ;; esac

printf 'Content-Type: text/plain; charset=utf-8\r\n'
printf 'Cache-Control: no-store\r\n'
printf 'X-Content-Type-Options: nosniff\r\n'
printf 'X-Frame-Options: DENY\r\n\r\n'
printf 'DexOS Web Installer\n'
printf 'Validando configuración...\n\n'

export DEXOS_CONFIRM=INSTALLAR
export DEXOS_HOSTNAME="$hostname"
export DEXOS_ADMIN_USER="$admin_user"
export DEXOS_ADMIN_PASSWORD="$admin_password"
export DEXOS_ROOT_PASSWORD="$root_password"
export DEXOS_SSH_ROOT_LOGIN="$ssh_root_login"
export DEXOS_TIMEZONE="$timezone"
export DEXOS_WIFI_SSID="$wifi_ssid"
export DEXOS_WIFI_PASSWORD="$wifi_password"
export DEXOS_INSTALL_MODE="$install_mode"
export DEXOS_DISK="$disk"
export DEXOS_ROOT_PART="$root_part"
export DEXOS_ROOT_FREE_START="$root_free_start"
export DEXOS_ROOT_FREE_SECTORS="$root_free_sectors"
export DEXOS_EFI_PART="$efi_part"

exec /usr/local/sbin/install --batch 2>&1
