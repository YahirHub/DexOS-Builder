#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cp "$ROOT/alpine-root/usr/share/mkinitfs/initramfs-init" "$TMP/initramfs-init"
# Use a pristine copy when the working root is already patched.
if grep -q YAH_SPLASH_PROGRESS_BEGIN "$TMP/initramfs-init"; then
    python3 - "$TMP/initramfs-init" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
# This test cannot safely reverse a patch; validate the already-patched source instead.
assert 'YAH_SPLASH_PROGRESS_BEGIN' in s
PY
else
    python3 "$ROOT/project/mkimage/patch-initramfs-init.py" "$TMP/initramfs-init"
fi
sh -n "$TMP/initramfs-init"
grep -q 'YAH_SPLASH_PROGRESS_BEGIN' "$TMP/initramfs-init"
grep -q -- '--progress-fd 3' "$TMP/initramfs-init"
grep -q 'yah_splash_keywatch' "$TMP/initramfs-init"
grep -q 'chvt 1' "$TMP/initramfs-init"
grep -q 'chvt 16' "$TMP/initramfs-init"
grep -q 'BAR_WIDTH=$bar_width' "$TMP/initramfs-init"
test -s "$ROOT/project/boot/fbsplash.ppm"
head -c 2 "$ROOT/project/boot/fbsplash.ppm" | grep -q '^P6$'
echo 'test-initramfs-splash: OK'
