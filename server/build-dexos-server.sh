#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALPINE_ROOT="$ROOT/alpine-root"
APORTS="$ROOT/aports"
CACHE="$ROOT/cache"
OUT="$ROOT/out"
BUILD_HOME="$ROOT/build-home"
KEY_DIR="$BUILD_HOME/.config/abuild"
PRIVKEY="$KEY_DIR/dexos-server.rsa"
PUBKEY="$PRIVKEY.pub"
mkdir -p "$CACHE" "$OUT" "$KEY_DIR"
GENERATED_INSTALLED="$CACHE/generated-installed"
mkdir -p "$GENERATED_INSTALLED"
for cmd in proot xorrisofs openssl sha256sum go; do command -v "$cmd" >/dev/null || { echo "Missing $cmd" >&2; exit 1; }; done
[ -x "$ALPINE_ROOT/sbin/apk" ]
[ -x "$APORTS/scripts/mkimage.sh" ]
(cd "$ROOT" && GO111MODULE=off go test ./server/wifi-tui)
(cd "$ROOT" && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 GO111MODULE=off \
  go build -trimpath -ldflags='-s -w' -o "$GENERATED_INSTALLED/wifi" ./server/wifi-tui)
chmod 0755 "$GENERATED_INSTALLED/wifi"
if [ ! -f "$PRIVKEY" ]; then
  openssl genrsa -out "$PRIVKEY" 3072 >/dev/null 2>&1
  chmod 0600 "$PRIVKEY"
  openssl rsa -in "$PRIVKEY" -pubout -out "$PUBKEY" >/dev/null 2>&1
fi
mkdir -p "$ALPINE_ROOT/etc/apk/keys"
cp "$PUBKEY" "$ALPINE_ROOT/etc/apk/keys/dexos-server.rsa.pub"
cp "$ROOT/server/mkimage/mkimg.dexserver.sh" "$APORTS/scripts/mkimg.dexserver.sh"
cp "$ROOT/server/mkimage/genapkovl-dexserver.sh" "$APORTS/scripts/genapkovl-dexserver.sh"
chmod +x "$APORTS/scripts/genapkovl-dexserver.sh"
python3 - "$APORTS/scripts/mkimg.base.sh" "$APORTS/scripts/mkimage.sh" <<'PY'
from pathlib import Path
import sys
base = Path(sys.argv[1])
s = base.read_text()
old = '_pkgs="linux-$_f linux-firmware wireless-regdb $modloop_addons"'
new = '_pkgs="linux-$_f ${kernel_firmware_packages:-linux-firmware} wireless-regdb $modloop_addons"'
if old in s:
    s = s.replace(old, new, 1)
elif new not in s:
    raise SystemExit('mkimg.base.sh firmware anchor not found')
# Skip xorriso inside proot; it cannot reliably follow the generated tree there.
needle_iso='\tif [ "$ARCH" = ppc64le ]; then\n'
marker='\t[ "${YAH_SKIP_XORRISO:-}" = "1" ] && return 0\n\n'
if 'YAH_SKIP_XORRISO' not in s:
    idx=s.find(needle_iso, s.find('create_image_iso()'))
    if idx < 0:
        raise SystemExit('create_image_iso insertion point not found')
    s=s[:idx]+marker+s[idx:]
base.write_text(s)
mk = Path(sys.argv[2])
m = mk.read_text()
m = m.replace('cp -Lrs $_fn $DESTDIR/', 'cp -Lr $_fn $DESTDIR/')
# mkimage can continue with its cached signed APKINDEX when a mirror update has
# a transient DNS failure. Missing packages still make apk fetch fail normally.
old_update = '\tapk update --root "$APKROOT"\n'
cache_update = '\tapk update --root "$APKROOT" || { echo "WARNING: using cached APKINDEX after transient mirror failure" >&2; [ -n "$(find "$APKROOT/etc/apk/cache" -name \"APKINDEX.*.tar.gz\" -print -quit 2>/dev/null)" ] || exit 1; }\n'
if old_update in m:
    m = m.replace(old_update, cache_update, 1)
elif cache_update not in m:
    raise SystemExit('mkimage.sh apk update anchor not found')
needle = '\tlocal _dir="${args//[^a-zA-Z0-9]/_}"\n'
short = needle + '\tif [ ${#_dir} -gt 180 ]; then _dir="${section}_$(printf %s "$args" | sha1sum | cut -c1-40)"; fi\n'
if short not in m:
    if needle not in m:
        raise SystemExit('mkimage.sh build_section anchor not found')
    m = m.replace(needle, short, 1)
mk.write_text(m)
PY
python3 - "$ALPINE_ROOT/usr/sbin/update-kernel" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = 'PACKAGES="$PACKAGES linux-$FLAVOR linux-firmware"'
new = 'PACKAGES="$PACKAGES linux-$FLAVOR"'
if old in s:
    s = s.replace(old, new, 1)
elif new not in s:
    raise SystemExit('update-kernel firmware anchor not found')
# Alpine already builds modloop as SquashFS/XZ. Make it an explicit build
# invariant so a future Alpine change cannot silently fall back to gzip.
if '-comp xz' not in s:
    raise SystemExit('update-kernel no usa SquashFS con compresión XZ')
if 'x86|x86_64) mksfs="-Xbcj x86"' not in s:
    raise SystemExit('update-kernel no aplica filtro BCJ x86 al SquashFS XZ')
p.write_text(s)
PY
rm -rf "$CACHE"/apkovl_* "$CACHE"/image-*-x86_64-dexserver "$OUT"/DexOS-Server-edge-x86_64.iso*
proot -i 1000:1000 -R "$ALPINE_ROOT" -b "$ROOT:/work" -w /work/server/mkimage \
  /usr/bin/env HOME=/work/build-home PACKAGER_PRIVKEY=/work/build-home/.config/abuild/dexos-server.rsa PACKAGER_PUBKEY=/work/build-home/.config/abuild/dexos-server.rsa.pub YAH_SKIP_XORRISO=1 \
  /bin/sh /work/aports/scripts/mkimage.sh --tag edge --outdir /work/out --workdir /work/cache --arch x86_64 --profile dexserver \
  --repository https://dl-cdn.alpinelinux.org/alpine/edge/main \
  --repository https://dl-cdn.alpinelinux.org/alpine/edge/community

IMG="$(find "$CACHE" -maxdepth 1 -type d -name 'image-*-x86_64-dexserver' -print | sort | tail -1)"
[ -n "$IMG" ] && [ -f "$IMG/boot/grub/efi.img" ] && [ -f "$IMG/boot/syslinux/isolinux.bin" ]

# The stock Alpine UEFI menu is intentionally replaced: DexOS uses the same
# Argon theme as the installed GRUB and puts the installer first.
mkdir -p "$IMG/boot/grub/themes/argon"
cp -a "$ROOT/server/assets/argon-grub-theme/." "$IMG/boot/grub/themes/argon/"
cat > "$IMG/boot/grub/grub.cfg" <<'EOF'
set timeout=8
set default=0

insmod all_video
insmod gfxterm
insmod png
loadfont /boot/grub/themes/argon/Terminus_16.pf2
loadfont /boot/grub/themes/argon/Terminus_24.pf2
set gfxmode=1920x1080,auto
set gfxpayload=keep
terminal_output gfxterm
set theme=/boot/grub/themes/argon/theme.txt
export theme

menuentry "Instalar Alpine Linux" --class alpine --class gnu-linux --class gnu --class os {
    linux /boot/vmlinuz-lts modules=loop,squashfs,sd-mod,usb-storage quiet
    initrd /boot/intel-ucode.img /boot/amd-ucode.img /boot/initramfs-lts
}

# Windows can be detected safely before boot because its UEFI loader has a
# stable path that is not present on the ISO itself.
if search --no-floppy --file --set=winroot /EFI/Microsoft/Boot/bootmgfw.efi; then
    menuentry "Windows Boot Manager" --class windows --class os {
        insmod chain
        search --no-floppy --file --set=root /EFI/Microsoft/Boot/bootmgfw.efi
        chainloader /EFI/Microsoft/Boot/bootmgfw.efi
    }
fi

# For Linux, detect a foreign root by /etc/fstab. The entry delegates to that
# installation's own GRUB when /boot is part of the same filesystem.
if search --no-floppy --file --set=linuxroot /etc/fstab; then
    menuentry "Otro Linux detectado" --class gnu-linux --class gnu --class os {
        search --no-floppy --file --set=root /etc/fstab
        if [ -f /boot/grub/grub.cfg ]; then
            configfile /boot/grub/grub.cfg
        elif [ -f /boot/grub2/grub.cfg ]; then
            configfile /boot/grub2/grub.cfg
        else
            echo "Se detectó Linux, pero su GRUB está en otra partición /boot."
            sleep 5
        fi
    }
fi
EOF

iso="$OUT/DexOS-Server-edge-x86_64.iso"
xorrisofs \
  -output "$iso" \
  -full-iso9660-filenames -joliet -rational-rock \
  -sysid LINUX -volid DEXOS_SERVER \
  -isohybrid-mbr "$IMG/boot/syslinux/isohdpfx.bin" \
  -eltorito-boot boot/syslinux/isolinux.bin \
  -eltorito-catalog boot/syslinux/boot.cat \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
  -isohybrid-gpt-basdat -follow-links "$IMG"
sha256sum "$iso" > "$iso.sha256"
ls -lh "$iso"
cat "$iso.sha256"
