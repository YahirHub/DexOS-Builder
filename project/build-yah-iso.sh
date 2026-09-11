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
ISO="$OUT/DexOS-edge-x86_64-v015.iso"
VOLID="DEXOS_V015"
mkdir -p "$CACHE" "$OUT" "$KEY_DIR"
for cmd in proot xorrisofs openssl sha256sum sha512sum gzip xz; do command -v "$cmd" >/dev/null || { echo "Falta $cmd" >&2; exit 1; }; done
[[ -x "$APORTS/scripts/mkimage.sh" ]]
[[ -x "$ALPINE_ROOT/sbin/apk" ]]
# Reuse the sandbox resolver inside PRoot. Docker's embedded DNS may be the
# only reachable resolver even when public resolvers are blocked upstream.
cp /etc/resolv.conf "$ALPINE_ROOT/etc/resolv.conf"
if [[ ! -f "$PRIVKEY" ]]; then
  openssl genrsa -out "$PRIVKEY" 4096 >/dev/null 2>&1
  chmod 0600 "$PRIVKEY"
  openssl rsa -in "$PRIVKEY" -pubout -out "$PUBKEY" >/dev/null 2>&1
fi
mkdir -p "$ALPINE_ROOT/etc/apk/keys"
cp "$PUBKEY" "$ALPINE_ROOT/etc/apk/keys/yah-alpine.rsa.pub"
cp "$ROOT/project/mkimage/mkimg.yahxfce.sh" "$APORTS/scripts/mkimg.yahxfce.sh"
cp "$ROOT/project/mkimage/genapkovl-yahxfce.sh" "$APORTS/scripts/genapkovl-yahxfce.sh"
cp "$ROOT/project/installer/dexos-installer.py" "$APORTS/scripts/dexos-installer.py"
cp "$ROOT/project/installer/dexos-installer-backend.py" "$APORTS/scripts/dexos-installer-backend.py"
cp "$ROOT/project/installer/installer-packages.txt" "$APORTS/scripts/installer-packages.txt"
rm -rf "$APORTS/scripts/argon-grub-theme"
cp -a "$ROOT/project/assets/argon-grub-theme" "$APORTS/scripts/argon-grub-theme"
rm -rf "$APORTS/scripts/dexos-windows-cursor"
cp -a "$ROOT/project/assets/dexos-windows-cursor" "$APORTS/scripts/dexos-windows-cursor"
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
cp "$ROOT/project/installed/dexos-session" "$APORTS/scripts/dexos-session"
cp "$ROOT/project/installed/dexos-wifi-init" "$APORTS/scripts/dexos-wifi-init"
cp "$ROOT/project/installed/dexos-wifi-refresh" "$APORTS/scripts/dexos-wifi-refresh"
cp "$ROOT/project/installed/dexos-audio-init" "$APORTS/scripts/dexos-audio-init"
cp "$ROOT/project/installed/dexos-apk-refresh" "$APORTS/scripts/dexos-apk-refresh"
cp "$ROOT/project/installed/dexos-language.py" "$APORTS/scripts/dexos-language.py"
cp "$ROOT/project/installed/dexos-trust-launchers" "$APORTS/scripts/dexos-trust-launchers"
cp "$ROOT/project/installed/dexos-video-init" "$APORTS/scripts/dexos-video-init"
cp "$ROOT/project/installed/dexos-prepare-desktop" "$APORTS/scripts/dexos-prepare-desktop"
cp "$ROOT/project/installed/dexos-boot-manager.py" "$APORTS/scripts/dexos-boot-manager.py"
cp "$ROOT/project/installed/dexos-eye-protection.py" "$APORTS/scripts/dexos-eye-protection.py"
cp "$ROOT/project/installed/dexos-power-init" "$APORTS/scripts/dexos-power-init"
cp "$ROOT/project/installed/dexos-power-apply" "$APORTS/scripts/dexos-power-apply"
cp "$ROOT/project/installed/dexos-backlight-state" "$APORTS/scripts/dexos-backlight-state"
cp "$ROOT/project/installed/org.dexos.boot-manager.policy" "$APORTS/scripts/org.dexos.boot-manager.policy"
cp "$ROOT/project/installed/boot-order" "$APORTS/scripts/boot-order"
cp "$ROOT/project/installed/grub-update" "$APORTS/scripts/grub-update"
cp "$ROOT/project/installed/grub-other-os" "$APORTS/scripts/grub-other-os"
cp "$ROOT/project/installed/05_dexos_theme" "$APORTS/scripts/05_dexos_theme"
cp "$ROOT/project/installed/09_dexos_linux" "$APORTS/scripts/09_dexos_linux"
chmod +x "$APORTS/scripts/genapkovl-yahxfce.sh" "$APORTS/scripts/dexos-installer.py" "$APORTS/scripts/dexos-installer-backend.py"   "$APORTS/scripts/dexos-session" "$APORTS/scripts/dexos-wifi-init" "$APORTS/scripts/dexos-wifi-refresh" "$APORTS/scripts/dexos-audio-init" "$APORTS/scripts/dexos-apk-refresh" "$APORTS/scripts/dexos-language.py" "$APORTS/scripts/dexos-trust-launchers" "$APORTS/scripts/dexos-video-init" "$APORTS/scripts/dexos-prepare-desktop" "$APORTS/scripts/dexos-boot-manager.py" "$APORTS/scripts/dexos-eye-protection.py" "$APORTS/scripts/dexos-power-init" "$APORTS/scripts/dexos-power-apply" "$APORTS/scripts/dexos-backlight-state" "$APORTS/scripts/boot-order" "$APORTS/scripts/grub-update" "$APORTS/scripts/grub-other-os" "$APORTS/scripts/05_dexos_theme" "$APORTS/scripts/09_dexos_linux"

python3 - "$APORTS/scripts/mkimage.sh" "$APORTS/scripts/mkimg.base.sh" <<'PY'
from pathlib import Path
import sys
mk=Path(sys.argv[1]); s=mk.read_text(); s=s.replace('cp -Lrs $_fn $DESTDIR/', 'cp -Lr $_fn $DESTDIR/')
old_update = '\tapk update --root "$APKROOT"\n'
cache_update = '\tapk update --root "$APKROOT" || { echo "WARNING: using cached APKINDEX after transient mirror failure" >&2; [ -n "$(find "$APKROOT/etc/apk/cache" -name \"APKINDEX.*.tar.gz\" -print -quit 2>/dev/null)" ] || exit 1; }\n'
if old_update in s:
    s=s.replace(old_update, cache_update, 1)
elif cache_update not in s:
    raise SystemExit('mkimage.sh apk update anchor not found')
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
python3 - "$ALPINE_ROOT/usr/sbin/update-kernel" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); text=p.read_text()
old_fw='PACKAGES="$PACKAGES linux-$FLAVOR linux-firmware"'
new_fw='PACKAGES="$PACKAGES linux-$FLAVOR"'
if old_fw in text:
    text=text.replace(old_fw,new_fw,1)
elif new_fw not in text:
    raise SystemExit('update-kernel linux-firmware anchor not found')
lines=text.splitlines()
out=[]
for line in lines:
    if line.lstrip().startswith('mksquashfs $MODLOOP "$STAGING/$MODIMG"'):
        line='mksquashfs $MODLOOP "$STAGING/$MODIMG" $MKSQUASHFS_OPTS -comp xz -b 1M -Xbcj x86 -Xdict-size 100% -tailends -exit-on-error'
    out.append(line)
p.write_text('\n'.join(out)+'\n')
PY
PATCH_HASH="$( { grep -E '^[[:space:]]*(initfs_cmdline|kernel_addons|kernel_flavors|kernel_firmware_packages|boot_addons|initrd_ucode)=' "$ROOT/project/mkimage/mkimg.yahxfce.sh"; cat "$ALPINE_ROOT/usr/sbin/update-kernel"; } | sha256sum | awk '{print $1}')"
PATCH_STAMP="$CACHE/.dexos-initramfs-patch.sha256"
if [[ ! -f "$PATCH_STAMP" ]] || [[ "$(cat "$PATCH_STAMP" 2>/dev/null || true)" != "$PATCH_HASH" ]]; then
  rm -rf "$CACHE"/kernel_*
  printf '%s\n' "$PATCH_HASH" > "$PATCH_STAMP"
fi
rm -rf "$CACHE"/apkovl_* "$CACHE"/image-*-x86_64-yahxfce "$ISO" "$ISO.sha256" "$ISO.sha512"

# Prefer the largest complete signed package cache from a previous successful
# Desktop build. This makes rebuilds deterministic and avoids a mirror update
# changing the kernel underneath an otherwise unchanged ISO.
LOCAL_REPO=""
LOCAL_COUNT=0
for candidate in "$CACHE"/apks_x86_64_*/apks/x86_64; do
  [[ -f "$candidate/APKINDEX.tar.gz" ]] || continue
  compgen -G "$candidate/linux-lts-*.apk" >/dev/null || continue
  count=$(find "$candidate" -maxdepth 1 -type f -name '*.apk' | wc -l)
  if (( count > LOCAL_COUNT )); then LOCAL_REPO="$candidate"; LOCAL_COUNT=$count; fi
done
if [[ -n "$LOCAL_REPO" ]]; then
  repo_root="${LOCAL_REPO%/x86_64}"
  repo_arg="file:///work/${repo_root#$ROOT/}"
  echo "Usando repositorio APK local firmado: $repo_arg ($LOCAL_COUNT paquetes)"
  # mkimage reuses apkroot between builds. Replace stale mirror repositories and
  # indexes so package resolution is fully offline and cannot select a newer
  # kernel that is not present in the signed local cache.
  mkdir -p "$CACHE/apkroot-x86_64/etc/apk/cache" "$CACHE/apkroot-x86_64/etc/apk"
  cat > "$CACHE/apkroot-x86_64/etc/apk/repositories" <<EOF_REPOS
$repo_arg
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
EOF_REPOS
  rm -f "$CACHE/apkroot-x86_64/etc/apk/cache"/APKINDEX.*.tar.gz
  # Prefer cached packages but keep official mirrors as a supplement for newly
  # added userland packages and microcode boot addons.
  REPOSITORIES=(--repository "$repo_arg" --repository https://dl-cdn.alpinelinux.org/alpine/edge/main --repository https://dl-cdn.alpinelinux.org/alpine/edge/community)
else
  echo "No hay cache APK firmado reutilizable; usando mirrors Alpine."
  mkdir -p "$CACHE/apkroot-x86_64/etc/apk/cache" "$CACHE/apkroot-x86_64/etc/apk"
  cat > "$CACHE/apkroot-x86_64/etc/apk/repositories" <<'EOF_REPOS'
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
EOF_REPOS
  rm -f "$CACHE/apkroot-x86_64/etc/apk/cache"/APKINDEX.*.tar.gz
  REPOSITORIES=(--repository https://dl-cdn.alpinelinux.org/alpine/edge/main --repository https://dl-cdn.alpinelinux.org/alpine/edge/community)
fi

proot -i 1000:1000 -R "$ALPINE_ROOT" -b "$ROOT:/work" -w /work/project/mkimage \
  /usr/bin/env HOME=/work/build-home PACKAGER_PRIVKEY=/work/build-home/.config/abuild/yah-alpine.rsa PACKAGER_PUBKEY=/work/build-home/.config/abuild/yah-alpine.rsa.pub YAH_SKIP_XORRISO=1 \
  /bin/sh /work/aports/scripts/mkimage.sh --tag edge --outdir /work/out --workdir /work/cache --arch x86_64 --profile yahxfce "${REPOSITORIES[@]}"
IMG="$(find "$CACHE" -maxdepth 1 -type d -name 'image-*-x86_64-yahxfce' -print | sort | tail -1)"
[[ -n "$IMG" && -f "$IMG/boot/grub/efi.img" && -f "$IMG/boot/syslinux/isolinux.bin" ]]
# Maximum safe boot compression: preserve the exact initramfs payload but
# recompress gzip -> XZ using extreme LZMA2. Linux LTS supports CONFIG_RD_XZ.
initramfs="$IMG/boot/initramfs-lts"
gzip -t "$initramfs"
initramfs_tmp="$initramfs.xz.tmp"
old_initrd_hash="$(gzip -dc "$initramfs" | sha256sum | awk '{print $1}')"
gzip -dc "$initramfs" | xz -C crc32 -T1 -9e > "$initramfs_tmp"
new_initrd_hash="$(xz -dc "$initramfs_tmp" | sha256sum | awk '{print $1}')"
[[ "$old_initrd_hash" == "$new_initrd_hash" ]] || { echo "initramfs XZ payload mismatch" >&2; exit 1; }
mv "$initramfs_tmp" "$initramfs"
rm -f "$IMG/fbsplash.ppm"
# User-visible boot menu branding.
sed -i -E 's/menuentry "Linux (lts|stable)"/menuentry "DexOS Live"/g' "$IMG/boot/grub/grub.cfg"
sed -i -E 's/MENU LABEL Linux (lts|stable)/MENU LABEL DexOS Live/g' "$IMG/boot/syslinux/syslinux.cfg"
xorrisofs -output "$ISO" -full-iso9660-filenames -joliet -rational-rock -sysid LINUX -volid "$VOLID" \
  -isohybrid-mbr "$IMG/boot/syslinux/isohdpfx.bin" -eltorito-boot boot/syslinux/isolinux.bin -eltorito-catalog boot/syslinux/boot.cat \
  -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat -follow-links "$IMG"
sha256sum "$ISO" > "$ISO.sha256"
sha512sum "$ISO" > "$ISO.sha512"
ls -lh "$ISO"
cat "$ISO.sha256"
