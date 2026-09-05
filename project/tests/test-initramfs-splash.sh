#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
APK=$(find "$ROOT/cache" "$ROOT/alpine-root" -type f -name 'mkinitfs-*.apk' -print | sort | tail -1)
test -n "$APK"
tar -xOzf "$APK" usr/share/mkinitfs/initramfs-init > "$TMP/initramfs-init"
python3 "$ROOT/project/mkimage/patch-initramfs-init.py" "$TMP/initramfs-init"
sh -n "$TMP/initramfs-init"
grep -q 'YAH_SPLASH_PROGRESS_BEGIN' "$TMP/initramfs-init"
grep -q -- '--progress-fd 3' "$TMP/initramfs-init"
grep -q 'dexos_splash_keywatch' "$TMP/initramfs-init"
grep -q 'chvt 1' "$TMP/initramfs-init"
grep -q 'chvt 16' "$TMP/initramfs-init"
grep -q 'usr/share/dexos/fbsplash.ppm' "$TMP/initramfs-init"
grep -q 'dexos-splash-progress' "$TMP/initramfs-init"
grep -q 'BAR_R=170' "$TMP/initramfs-init"
grep -q 'BAR_G=72' "$TMP/initramfs-init"
grep -q 'BAR_B=76' "$TMP/initramfs-init"
test -s "$ROOT/project/boot/fbsplash.ppm"
head -c 2 "$ROOT/project/boot/fbsplash.ppm" | grep -q '^P6$'
echo 'test-initramfs-splash: OK'
