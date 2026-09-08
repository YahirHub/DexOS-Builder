#!/bin/sh
set -eu
printf 'Content-Type: text/plain; charset=utf-8\r\n'
printf 'Cache-Control: no-store\r\n'
printf 'X-Content-Type-Options: nosniff\r\n\r\n'

if [ -f /run/dex-installer-live.status ]; then
    sed 's/^/LIVE\t/' /run/dex-installer-live.status
fi
printf 'SSH\tuser=root\n'
printf 'SSH\tpassword=root\n'
if command -v ip >/dev/null 2>&1; then
    ip -o -4 addr show scope global 2>/dev/null | awk '{split($4,a,"/"); print "IP\t" $2 "\t" a[1]}'
fi
