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
ISO="$OUT/DexOS-edge-x86_64-v006.iso"
VOLID="DEXOS_V006"
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
cp "$ROOT/project/mkimage/patch-initramfs-init.py" "$APORTS/scripts/patch-initramfs-init.py"
cp "$ROOT/project/installer/dexos-installer.py" "$APORTS/scripts/dexos-installer.py"
cp "$ROOT/project/installer/dexos-installer-backend.py" "$APORTS/scripts/dexos-installer-backend.py"
cp "$ROOT/project/installer/installer-packages.txt" "$APORTS/scripts/installer-packages.txt"
python3 "$ROOT/project/assets/generate-brand-assets.py"
cp "$ROOT/project/assets/dexos-boot.jpg" "$APORTS/scripts/dexos-boot.jpg"
cp "$ROOT/project/assets/dexos-boot.ppm" "$APORTS/scripts/dexos-boot.ppm"
rm -rf "$APORTS/scripts/argon-grub-theme"
cp -a "$ROOT/project/assets/argon-grub-theme" "$APORTS/scripts/argon-grub-theme"
# Preserve the user's wallpaper bytes exactly. The filename is intentionally
# extensionless because GTK/GdkPixbuf detects PNG/JPEG by file signature.
USER_WALLPAPER=""
for candidate in "$ROOT/project/assets/dexos-wallpaper-user" "$ROOT/project/assets/dexos-wallpaper-user.png" "$ROOT/project/assets/dexos-wallpaper-user.jpg" "$ROOT/project/assets/dexos-wallpaper-user.jpeg"; do
    if [[ -s "$candidate" ]]; then USER_WALLPAPER="$candidate"; break; fi
done
if [[ -z "$USER_WALLPAPER" ]]; then
    echo "Falta el wallpaper exacto del usuario: project/assets/dexos-wallpaper-user.(png|jpg|jpeg)" >&2
    echo "DexOS no se compila con un wallpaper sustituto." >&2
    exit 1
fi
cp "$USER_WALLPAPER" "$APORTS/scripts/dexos-wallpaper"
cp "$ROOT/project/installed/dexos-session-splash.py" "$APORTS/scripts/dexos-session-splash.py"
cp "$ROOT/project/installed/dexos-session" "$APORTS/scripts/dexos-session"
cp "$ROOT/project/installed/dexos-splash-keys" "$APORTS/scripts/dexos-splash-keys"
cp "$ROOT/project/installed/dexos-bootsplash" "$APORTS/scripts/dexos-bootsplash"
cp "$ROOT/project/installed/dexos-bootsplash-finish" "$APORTS/scripts/dexos-bootsplash-finish"
cp "$ROOT/project/installed/dexos-wifi-init" "$APORTS/scripts/dexos-wifi-init"
cp "$ROOT/project/installed/dexos-wifi-refresh" "$APORTS/scripts/dexos-wifi-refresh"
cp "$ROOT/project/installed/dexos-audio-init" "$APORTS/scripts/dexos-audio-init"
cp "$ROOT/project/installed/dexos-apk-refresh" "$APORTS/scripts/dexos-apk-refresh"
cp "$ROOT/project/installed/dexos-language.py" "$APORTS/scripts/dexos-language.py"
cp "$ROOT/project/installed/dexos-trust-launchers" "$APORTS/scripts/dexos-trust-launchers"
cp "$ROOT/project/installed/dexos-video-init" "$APORTS/scripts/dexos-video-init"
chmod +x "$APORTS/scripts/genapkovl-yahxfce.sh" "$APORTS/scripts/dexos-installer.py" "$APORTS/scripts/dexos-installer-backend.py"   "$APORTS/scripts/dexos-session-splash.py" "$APORTS/scripts/dexos-session" "$APORTS/scripts/dexos-splash-keys"   "$APORTS/scripts/dexos-bootsplash" "$APORTS/scripts/dexos-bootsplash-finish" "$APORTS/scripts/dexos-wifi-init" "$APORTS/scripts/dexos-wifi-refresh" "$APORTS/scripts/dexos-audio-init" "$APORTS/scripts/dexos-apk-refresh" "$APORTS/scripts/dexos-language.py" "$APORTS/scripts/dexos-trust-launchers" "$APORTS/scripts/dexos-video-init"

python3 - "$APORTS/scripts/mkimage.sh" "$APORTS/scripts/mkimg.base.sh" <<'PY'
from pathlib import Path
import sys
mk=Path(sys.argv[1]); s=mk.read_text(); s=s.replace('cp -Lrs $_fn $DESTDIR/', 'cp -Lr $_fn $DESTDIR/')
needle='\tlocal _dir="${args//[^a-zA-Z0-9]/_}"\n'
short='\tlocal _dir="${args//[^a-zA-Z0-9]/_}"\n\tif [ ${#_dir} -gt 180 ]; then _dir="${section}_$(printf %s "$args" | sha1sum | cut -c1-40)"; fi\n'
if short not in s:
    if needle not in s: raise SystemExit('build_section _dir anchor missing')
    s=s.replace(needle, short, 1)
mk.write_text(s)
base=Path(sys.argv[2]); b=base.read_text(); b=b.replace('_pkgs="linux-$_f linux-firmware wireless-regdb $modloop_addons"', '_pkgs="linux-$_f ${kernel_firmware_packages:-linux-firmware} wireless-regdb $modloop_addons"'); needle='\tif [ "$ARCH" = ppc64le ]; then\n'; marker='\t[ "${YAH_SKIP_XORRISO:-}" = "1" ] && return 0\n\n'
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
import sys
p=Path(sys.argv[1]); lines=p.read_text().splitlines()
out=[]
for line in lines:
    if line.lstrip().startswith('mksquashfs $MODLOOP "$STAGING/$MODIMG"'):
        line='mksquashfs $MODLOOP "$STAGING/$MODIMG" $MKSQUASHFS_OPTS -comp xz -b 1M -Xbcj x86 -Xdict-size 100% -exit-on-error'
    out.append(line)
p.write_text('\n'.join(out)+'\n')
PY
PATCH_HASH="$(cat "$ROOT/project/mkimage/patch-initramfs-init.py" "$ROOT/project/mkimage/mkimg.yahxfce.sh" "$ROOT/project/build-yah-iso.sh" | sha256sum | awk '{print $1}')"
PATCH_STAMP="$CACHE/.dexos-initramfs-patch.sha256"
if [[ ! -f "$PATCH_STAMP" ]] || [[ "$(cat "$PATCH_STAMP" 2>/dev/null || true)" != "$PATCH_HASH" ]]; then
  rm -rf "$CACHE"/kernel_*
  printf '%s\n' "$PATCH_HASH" > "$PATCH_STAMP"
fi
rm -rf "$CACHE"/apkovl_* "$CACHE"/image-*-x86_64-yahxfce "$ISO" "$ISO.sha256" "$ISO.sha512"
proot -i 1000:1000 -R "$ALPINE_ROOT" -b "$ROOT:/work" -w /work/project/mkimage \
  /usr/bin/env HOME=/work/build-home PACKAGER_PRIVKEY=/work/build-home/.config/abuild/yah-alpine.rsa PACKAGER_PUBKEY=/work/build-home/.config/abuild/yah-alpine.rsa.pub YAH_SKIP_XORRISO=1 \
  /bin/sh /work/aports/scripts/mkimage.sh --tag edge --outdir /work/out --workdir /work/cache --arch x86_64 --profile yahxfce \
  --repository https://dl-cdn.alpinelinux.org/alpine/edge/main --repository https://dl-cdn.alpinelinux.org/alpine/edge/community
IMG="$(find "$CACHE" -maxdepth 1 -type d -name 'image-*-x86_64-yahxfce' -print | sort | tail -1)"
[[ -n "$IMG" && -f "$IMG/boot/grub/efi.img" && -f "$IMG/boot/syslinux/isolinux.bin" ]]
cp "$ROOT/project/assets/dexos-boot.ppm" "$IMG/fbsplash.ppm"
# User-visible boot menu branding.
sed -i -E 's/menuentry "Linux (lts|stable)"/menuentry "DexOS Live"/g' "$IMG/boot/grub/grub.cfg"
sed -i -E 's/MENU LABEL Linux (lts|stable)/MENU LABEL DexOS Live/g' "$IMG/boot/syslinux/syslinux.cfg"
grep -q ' splash' "$IMG/boot/grub/grub.cfg"
grep -q ' splash' "$IMG/boot/syslinux/syslinux.cfg"
xorrisofs -output "$ISO" -full-iso9660-filenames -joliet -rational-rock -sysid LINUX -volid "$VOLID" \
  -isohybrid-mbr "$IMG/boot/syslinux/isohdpfx.bin" -eltorito-boot boot/syslinux/isolinux.bin -eltorito-catalog boot/syslinux/boot.cat \
  -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat -follow-links "$IMG"
sha256sum "$ISO" > "$ISO.sha256"
sha512sum "$ISO" > "$ISO.sha512"
ls -lh "$ISO"
cat "$ISO.sha256"
