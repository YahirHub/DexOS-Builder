#!/bin/sh
set -eu
printf 'Content-Type: text/plain; charset=utf-8\r\n'
printf 'Cache-Control: no-store\r\n'
printf 'X-Content-Type-Options: nosniff\r\n\r\n'
exec /usr/local/sbin/install --inventory
