#!/bin/sh
set -eu
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
printf 'Content-Type: text/plain; charset=utf-8\r\n'
printf 'Cache-Control: no-store\r\n'
printf 'X-Content-Type-Options: nosniff\r\n\r\n'

if [ -f /run/dex-installer-live.status ]; then
    sed 's/^/LIVE\t/' /run/dex-installer-live.status
fi
printf 'SSH\tuser=root\n'
printf 'SSH\tpassword=root\n'
if command -v nmcli > /dev/null 2>&1; then
    connectivity=$(nmcli -t -f CONNECTIVITY general 2>/dev/null | head -n1 || true)
    [ -n "$connectivity" ] && printf 'NET\tconnectivity\t%s\n' "$connectivity"
fi
if command -v ip >/dev/null 2>&1; then
    ip -o -4 addr show scope global 2>/dev/null | awk '{split($4,a,"/"); print "IP\t" $2 "\t" a[1]}'
fi
