#!/bin/sh
set -eu
set -f
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

error() {
    printf 'Status: 400 Bad Request\r\n'
    printf 'Content-Type: text/plain; charset=utf-8\r\n'
    printf 'Cache-Control: no-store\r\n\r\n'
    printf 'ERROR: %s\n' "$1"
    exit 1
}

[ "${REQUEST_METHOD:-}" = POST ] || error 'Usa POST.'
[ -f /run/dexos-install-complete ] || error 'DexOS todavía no ha confirmado una instalación completa.'
length=${CONTENT_LENGTH:-0}
case "$length" in ''|*[!0-9]*) error 'CONTENT_LENGTH inválido.' ;; esac
[ "$length" -le 1024 ] || error 'Solicitud demasiado grande.'
body=$(dd bs=1 count="$length" 2>/dev/null || true)
[ "$body" = 'confirm=REBOOT' ] || error 'Falta confirmación de reinicio.'

printf 'Content-Type: text/plain; charset=utf-8\r\n'
printf 'Cache-Control: no-store\r\n'
printf 'Connection: close\r\n\r\n'
printf 'REBOOTING\n'

# Give mini_httpd/browser time to receive the response before the Live exits.
(
    sleep 2
    sync
    /sbin/reboot
) >/dev/null 2>&1 &
exit 0
