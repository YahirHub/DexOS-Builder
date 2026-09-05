#!/usr/bin/env python3
"""Patch Alpine initramfs-init for DexOS Live bootsplash progress and ESC log toggle."""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-initramfs-init.py PATH")
p = Path(sys.argv[1])
s = p.read_text()
if "YAH_SPLASH_PROGRESS_BEGIN" in s:
    raise SystemExit(0)

needle = 'splashfile=/.splash.ctrl\n'
helpers = r'''splashfile=/.splash.ctrl

# YAH_SPLASH_PROGRESS_BEGIN
# Feed BusyBox fbsplash with real apk-tools progress and allow ESC to toggle tty1 logs.
dexos_splash_progress_reader() {
	[ -p "$sysroot/$splashfile" ] || return 0
	exec 4>"$sysroot/$splashfile" || return 0
	printf '3\n' >&4
	last=3
	while read -r progress _phase; do
		case "$progress" in
			*/*)
				current=${progress%/*}
				total=${progress#*/}
				case "$current:$total" in *[!0-9:]*) continue;; esac
				[ "$total" -gt 0 ] 2>/dev/null || continue
				pct=$((5 + (current * 83 / total)))
				[ "$pct" -gt 88 ] && pct=88
				if [ "$pct" -gt "$last" ]; then
					printf '%s\n' "$pct" >&4
					printf '%s\n' "$pct" > "$sysroot/.dexos-splash-progress"
					last=$pct
					if [ -e "$sysroot/.dexos-show-boot-log" ]; then
						printf 'Cargando sistema Live: %s%%\n' "$pct" > /dev/tty1
					fi
				fi
				;;
		esac
	done
}

dexos_splash_keywatch() {
	esc="$(printf '\033')"
	current=16
	while [ -p "$sysroot/$splashfile" ]; do
		dev="/dev/tty$current"
		[ -c "$dev" ] || { sleep 1; continue; }
		stty -F "$dev" -echo -icanon min 1 time 0 2>/dev/null || return 0
		key=
		IFS= read -r -n 1 key < "$dev" || continue
		[ "$key" = "$esc" ] || continue
		if [ "$current" -eq 16 ]; then
			touch "$sysroot/.dexos-show-boot-log"
			printf '\033[H\033[2JDexOS — detalles del arranque (ESC para volver)\n\n' > /dev/tty1
			dmesg > /dev/tty1 2>/dev/null || true
			chvt 1
			current=1
		else
			rm -f "$sysroot/.dexos-show-boot-log"
			chvt 16
			sleep 0.05
			if [ -r "$sysroot/usr/share/dexos/fbsplash.ppm" ] && [ -r "$sysroot/etc/dexos/fbsplash.cfg" ]; then
				fbsplash -s "$sysroot/usr/share/dexos/fbsplash.ppm" -d /dev/fb0 -i "$sysroot/etc/dexos/fbsplash.cfg" >/dev/null 2>&1 || true
			fi
			if [ -r "$sysroot/.dexos-splash-progress" ]; then
				pct=$(cat "$sysroot/.dexos-splash-progress" 2>/dev/null || echo 3)
				printf '%s\n' "$pct" > "$sysroot/$splashfile" 2>/dev/null || true
			fi
			current=16
		fi
	done
}
# YAH_SPLASH_PROGRESS_END
'''
if needle not in s:
    raise SystemExit("splashfile anchor not found")
s = s.replace(needle, helpers, 1)

old_cfg = '''if [ "$KOPT_splash" != "no" ]; then
\techo "IMG_ALIGN=CM" > /tmp/fbsplash.cfg
'''
new_cfg = '''if [ "$KOPT_splash" != "no" ]; then
\t# Build a resolution-aware progress bar; image stays centered on any framebuffer.
\tfbsize=$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null || echo 720,400)
\txres=${fbsize%,*}; yres=${fbsize#*,}
\tcase "$xres:$yres" in *[!0-9:]*) xres=720; yres=400;; esac
\tbar_width=$((xres * 55 / 100))
\t[ "$bar_width" -gt 560 ] && bar_width=560
\t[ "$bar_width" -lt 220 ] && bar_width=220
\tbar_left=$(((xres - bar_width) / 2))
\t[ "$bar_left" -lt 0 ] && bar_left=0
\tbar_top=$((yres * 86 / 100))
\tcat > /tmp/fbsplash.cfg <<EOF_YAH_SPLASH
IMG_ALIGN=CM
BAR_LEFT=$bar_left
BAR_TOP=$bar_top
BAR_WIDTH=$bar_width
BAR_HEIGHT=8
BAR_R=170
BAR_G=72
BAR_B=76
EOF_YAH_SPLASH
'''
if old_cfg not in s:
    raise SystemExit("fbsplash config anchor not found")
s = s.replace(old_cfg, new_cfg, 1)

old_start = '''\tsetsid fbsplash -T 16 -s "$fbsplash" -i "$config" -f "$sysroot/$splashfile" &
\teend 0
'''
new_start = '''\tmkdir -p "$sysroot/usr/share/dexos" "$sysroot/etc/dexos"
\tcp "$fbsplash" "$sysroot/usr/share/dexos/fbsplash.ppm" 2>/dev/null || true
\tcp "$config" "$sysroot/etc/dexos/fbsplash.cfg" 2>/dev/null || true
\tprintf '3\n' > "$sysroot/.dexos-splash-progress"
\tsetsid fbsplash -T 16 -s "$fbsplash" -i "$config" -f "$sysroot/$splashfile" &
\t# ESC toggles between splash (tty16) and real boot details (tty1).
\tdexos_splash_keywatch &
\techo $! > "$sysroot/.dexos-initramfs-splash-key.pid"
\teend 0
'''
if old_start not in s:
    raise SystemExit("fbsplash start anchor not found")
s = s.replace(old_start, new_start, 1)

old_bind = '''$MOCK mount -o bind /sys "$sysroot"/sys
$MOCK mount -o bind /proc "$sysroot"/proc
$MOCK mount -o bind /dev "$sysroot"/dev
'''
new_bind = old_bind + '''dexos_progress_fifo=
if [ "$KOPT_splash" != no ] && [ -p "$sysroot/$splashfile" ]; then
\tdexos_progress_fifo=/tmp/.dexos-apk-progress
\trm -f "$dexos_progress_fifo"
\tmkfifo "$dexos_progress_fifo"
\tdexos_splash_progress_reader < "$dexos_progress_fifo" &
\tdexos_progress_pid=$!
\texec 3>"$dexos_progress_fifo"
\tapkflags="$apkflags --progress-fd 3"
fi
'''
if old_bind not in s:
    raise SystemExit("apk progress start anchor not found")
s = s.replace(old_bind, new_bind, 1)

old_after = '''fi
$MOCK umount "$sysroot"/sys "$sysroot"/proc "$sysroot"/dev
eend 0
'''
new_after = '''fi
if [ -n "$dexos_progress_fifo" ]; then
\texec 3>&-
\twait "$dexos_progress_pid" 2>/dev/null || true
\tprintf '90\n' > "$sysroot/.dexos-splash-progress"
\tprintf '90\\n' > "$sysroot/$splashfile" 2>/dev/null || true
\trm -f "$dexos_progress_fifo"
fi
$MOCK umount "$sysroot"/sys "$sysroot"/proc "$sysroot"/dev
eend 0
'''
if old_after not in s:
    raise SystemExit("apk progress end anchor not found")
s = s.replace(old_after, new_after, 1)

old_switch = '''[ "$KOPT_splash" = "init" ] && echo exit > "$sysroot/$splashfile"
echo ""
'''
new_switch = '''# Stop the initramfs ESC watcher; OpenRC starts a new one after switch_root.
if [ -r "$sysroot/.dexos-initramfs-splash-key.pid" ]; then
\tkill "$(cat "$sysroot/.dexos-initramfs-splash-key.pid")" 2>/dev/null || true
\trm -f "$sysroot/.dexos-initramfs-splash-key.pid"
fi
stty -F /dev/tty1 sane 2>/dev/null || true
stty -F /dev/tty16 sane 2>/dev/null || true
[ "$KOPT_splash" = "init" ] && echo exit > "$sysroot/$splashfile"
echo ""
'''
if old_switch not in s:
    raise SystemExit("switch_root splash anchor not found")
s = s.replace(old_switch, new_switch, 1)

p.write_text(s)
