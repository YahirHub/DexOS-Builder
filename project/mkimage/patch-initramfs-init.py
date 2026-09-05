#!/usr/bin/env python3
"""Patch Alpine initramfs-init for Yah Live bootsplash progress and ESC log toggle."""
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
yah_splash_progress_reader() {
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
					last=$pct
					if [ -e "$sysroot/.yah-show-boot-log" ]; then
						printf 'Cargando sistema Live: %s%%\n' "$pct" > /dev/tty1
					fi
				fi
				;;
		esac
	done
}

yah_splash_keywatch() {
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
			touch "$sysroot/.yah-show-boot-log"
			printf '\033[H\033[2JYah Alpine — detalles del arranque (ESC para volver)\n\n' > /dev/tty1
			dmesg > /dev/tty1 2>/dev/null || true
			chvt 1
			current=1
		else
			rm -f "$sysroot/.yah-show-boot-log"
			chvt 16
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
BAR_R=68
BAR_G=181
BAR_B=230
EOF_YAH_SPLASH
'''
if old_cfg not in s:
    raise SystemExit("fbsplash config anchor not found")
s = s.replace(old_cfg, new_cfg, 1)

old_start = '''\tsetsid fbsplash -T 16 -s "$fbsplash" -i "$config" -f "$sysroot/$splashfile" &
\teend 0
'''
new_start = '''\tsetsid fbsplash -T 16 -s "$fbsplash" -i "$config" -f "$sysroot/$splashfile" &
\t# ESC toggles between splash (tty16) and real boot details (tty1).
\tyah_splash_keywatch &
\techo $! > "$sysroot/.yah-initramfs-splash-key.pid"
\teend 0
'''
if old_start not in s:
    raise SystemExit("fbsplash start anchor not found")
s = s.replace(old_start, new_start, 1)

old_bind = '''$MOCK mount -o bind /sys "$sysroot"/sys
$MOCK mount -o bind /proc "$sysroot"/proc
$MOCK mount -o bind /dev "$sysroot"/dev
'''
new_bind = old_bind + '''yah_progress_fifo=
if [ "$KOPT_splash" != no ] && [ -p "$sysroot/$splashfile" ]; then
\tyah_progress_fifo=/tmp/.yah-apk-progress
\trm -f "$yah_progress_fifo"
\tmkfifo "$yah_progress_fifo"
\tyah_splash_progress_reader < "$yah_progress_fifo" &
\tyah_progress_pid=$!
\texec 3>"$yah_progress_fifo"
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
if [ -n "$yah_progress_fifo" ]; then
\texec 3>&-
\twait "$yah_progress_pid" 2>/dev/null || true
\tprintf '90\\n' > "$sysroot/$splashfile" 2>/dev/null || true
\trm -f "$yah_progress_fifo"
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
if [ -r "$sysroot/.yah-initramfs-splash-key.pid" ]; then
\tkill "$(cat "$sysroot/.yah-initramfs-splash-key.pid")" 2>/dev/null || true
\trm -f "$sysroot/.yah-initramfs-splash-key.pid"
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
