#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALPINE_ROOT="$ROOT/alpine-root"
APORTS="$ROOT/aports"
CACHE="$ROOT/cache"
OUT="$ROOT/out"
BUILD_HOME="$ROOT/build-home"
KEY_DIR="$BUILD_HOME/.config/abuild"
PRIVKEY="$KEY_DIR/yah-alpine.rsa"
PUBKEY="$PRIVKEY.pub"
ISO="$OUT/DexOS-edge-x86_64.iso"
VOLID="alpine-dexos edge x86_64"
mkdir -p "$CACHE" "$OUT" "$KEY_DIR"
for cmd in proot xorrisofs openssl sha256sum sha512sum; do command -v "$cmd" >/dev/null || { echo "Falta $cmd" >&2; exit 1; }; done
[[ -x "$APORTS/scripts/mkimage.sh" ]]
[[ -x "$ALPINE_ROOT/sbin/apk" ]]
if [[ ! -f "$PRIVKEY" ]]; then
  openssl genrsa -out "$PRIVKEY" 4096 >/dev/null 2>&1
  chmod 0600 "$PRIVKEY"
  openssl rsa -in "$PRIVKEY" -pubout -out "$PUBKEY" >/dev/null 2>&1
fi
mkdir -p "$ALPINE_ROOT/etc/apk/keys"
cp "$PUBKEY" "$ALPINE_ROOT/etc/apk/keys/yah-alpine.rsa.pub"
cp "$ROOT/project/mkimage/mkimg.yahxfce.sh" "$APORTS/scripts/mkimg.yahxfce.sh"
cp "$ROOT/project/mkimage/genapkovl-yahxfce.sh" "$APORTS/scripts/genapkovl-yahxfce.sh"
chmod +x "$APORTS/scripts/genapkovl-yahxfce.sh"

python3 - "$APORTS/scripts/mkimage.sh" "$APORTS/scripts/mkimg.base.sh" <<'PY'
from pathlib import Path
import sys
mk=Path(sys.argv[1]); s=mk.read_text(); s=s.replace('cp -Lrs $_fn $DESTDIR/', 'cp -Lr $_fn $DESTDIR/'); mk.write_text(s)
base=Path(sys.argv[2]); b=base.read_text(); needle='\tif [ "$ARCH" = ppc64le ]; then\n'; marker='\t[ "${YAH_SKIP_XORRISO:-}" = "1" ] && return 0\n\n'
if 'YAH_SKIP_XORRISO' not in b:
    idx=b.find(needle,b.find('create_image_iso()'))
    if idx<0: raise SystemExit('create_image_iso insertion point not found')
    b=b[:idx]+marker+b[idx:]
base.write_text(b)
PY
# Restore a pristine mkinitfs init script from the cached Alpine package on every build,
# then apply the DexOS splash patch. This makes splash changes reproducible/idempotent.
MKINITFS_APK="$(find "$CACHE" "$ALPINE_ROOT" -type f -name 'mkinitfs-*.apk' -print | sort | tail -1)"
[[ -n "$MKINITFS_APK" ]]
tar -xOzf "$MKINITFS_APK" usr/share/mkinitfs/initramfs-init > "$ALPINE_ROOT/usr/share/mkinitfs/initramfs-init"
chmod 0755 "$ALPINE_ROOT/usr/share/mkinitfs/initramfs-init"
python3 "$ROOT/project/mkimage/patch-initramfs-init.py" "$ALPINE_ROOT/usr/share/mkinitfs/initramfs-init"
sh -n "$ALPINE_ROOT/usr/share/mkinitfs/initramfs-init"

python3 - "$ALPINE_ROOT/usr/sbin/update-kernel" <<'PY'
from pathlib import Path
import re,sys
p=Path(sys.argv[1]); s=p.read_text()
s=re.sub(r'mksquashfs \$MODLOOP "\$STAGING/\$MODIMG" \$MKSQUASHFS_OPTS -comp (?:xz|zstd)(?: -Xcompression-level 15)? -exit-on-error(?: \$mksfs)?','mksquashfs $MODLOOP "$STAGING/$MODIMG" $MKSQUASHFS_OPTS -comp zstd -Xcompression-level 15 -exit-on-error',s)
p.write_text(s)
PY
PATCH_HASH="$(sha256sum "$ROOT/project/mkimage/patch-initramfs-init.py" | awk '{print $1}')"
PATCH_STAMP="$CACHE/.dexos-initramfs-patch.sha256"
if [[ ! -f "$PATCH_STAMP" ]] || [[ "$(cat "$PATCH_STAMP" 2>/dev/null || true)" != "$PATCH_HASH" ]]; then
  rm -rf "$CACHE"/kernel_x86_64_lts_*
  printf '%s\n' "$PATCH_HASH" > "$PATCH_STAMP"
fi
rm -rf "$CACHE"/apkovl_* "$CACHE"/image-*-x86_64-yahxfce "$ISO" "$ISO.sha256" "$ISO.sha512"
proot -i 1000:1000 -R "$ALPINE_ROOT" -b "$ROOT:/work" -w /work/project/mkimage \
  /usr/bin/env HOME=/work/build-home PACKAGER_PRIVKEY=/work/build-home/.config/abuild/yah-alpine.rsa PACKAGER_PUBKEY=/work/build-home/.config/abuild/yah-alpine.rsa.pub YAH_SKIP_XORRISO=1 \
  /bin/sh /work/aports/scripts/mkimage.sh --tag edge --outdir /work/out --workdir /work/cache --arch x86_64 --profile yahxfce \
  --repository https://dl-cdn.alpinelinux.org/alpine/edge/main --repository https://dl-cdn.alpinelinux.org/alpine/edge/community
IMG="$(find "$CACHE" -maxdepth 1 -type d -name 'image-*-x86_64-yahxfce' -print | sort | tail -1)"
[[ -n "$IMG" && -f "$IMG/boot/grub/efi.img" && -f "$IMG/boot/syslinux/isolinux.bin" ]]
cp "$ROOT/project/boot/fbsplash.ppm" "$IMG/fbsplash.ppm"
# User-visible boot menu branding.
sed -i 's/menuentry "Linux lts"/menuentry "DexOS Live"/g' "$IMG/boot/grub/grub.cfg"
sed -i 's/MENU LABEL Linux lts/MENU LABEL DexOS Live/g' "$IMG/boot/syslinux/syslinux.cfg"
grep -q ' splash' "$IMG/boot/grub/grub.cfg"
grep -q ' splash' "$IMG/boot/syslinux/syslinux.cfg"
xorrisofs -output "$ISO" -full-iso9660-filenames -joliet -rational-rock -sysid LINUX -volid "$VOLID" \
  -isohybrid-mbr "$IMG/boot/syslinux/isohdpfx.bin" -eltorito-boot boot/syslinux/isolinux.bin -eltorito-catalog boot/syslinux/boot.cat \
  -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat -follow-links "$IMG"
sha256sum "$ISO" > "$ISO.sha256"
sha512sum "$ISO" > "$ISO.sha512"
ls -lh "$ISO"
cat "$ISO.sha256"
