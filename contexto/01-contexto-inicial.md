# Fecha
2026-09-04
# Objetivo
Reconstruir Yah Alpine XFCE corrigiendo el escritorio visible pero no interactivo observado tanto en QEMU como VirtualBox.
# Diagnóstico
La versión anterior arrancaba XFCE como root mediante startx y sólo habilitaba parcialmente eudev. Alpine oficial `setup-xorg-base` usa `setup-devd udev`, que deshabilita mdev/mdevd y habilita udev, udev-trigger, udev-settle y udev-postmount. `setup-desktop xfce` además usa elogind/LightDM y elimina acpid.
# Decisiones
- Live con usuario normal `yah` UID 1000.
- LightDM autologin sólo en Live; sistema instalado usa greeter normal.
- eudev exclusivo, sin mdev/hwdrivers.
- Habilitar udev, udev-trigger, udev-settle y udev-postmount.
- dbus + elogind + NetworkManager + LightDM.
- No habilitar acpid en escritorio.
- Instalador Go se ejecuta vía regla doas limitada.
# Arquitectura actual
Pendiente de reconstrucción.
# Librerías
Go + github.com/jezek/xgb.
# Archivos importantes modificados
Pendiente.
# Problemas
Workspace anterior fue limpiado; reconstrucción desde cero.
# Soluciones
Pendiente.
# Pendientes
Build ISO, QEMU runtime, interacción real, instalación y reboot.
# Próximos pasos
Implementar apkovl corregido y pruebas que detecten doble gestor de dispositivos.

## Diagnóstico runtime 2026-09-04
- Se confirmó que el APKoVL heredaba modo 0700 del directorio `mktemp -d`, por lo que al aplicarse sobre `/` dejaba la raíz como `drwx------ root:root`. Resultado: usuarios `yah` y `lightdm` no podían atravesar `/`, causando `Permission denied` al ejecutar `/bin/sh`, `startxfce4` y escribir `.Xauthority`.
- Se confirmó además que en QEMU std VGA `elogind` reporta `CanGraphical=no` por ausencia de DRM, aunque `seat0` sí contiene teclado/tablet. LightDM no creaba el seat por su filtro gráfico por defecto.
- Solución validada en caliente: `chmod 755 /` + `logind-check-graphical=false`; Xorg inicia, LightDM autentica `yah` y `xfce4-session` permanece activo.

## Corrección de entrada 2026-09-04
- Síntoma: XFCE dibujaba escritorio, pero mouse/teclado no respondían en QEMU ni VirtualBox.
- Diagnóstico: `/proc/bus/input/devices` detectaba teclado/tablet, pero no existía `/dev/input/event*`; Xorg indicaba que dependía de udev y no agregaba ningún input.
- El `modloop-lts` sí contiene `evdev.ko`, `usbhid.ko` y demás módulos, pero el APKoVL personalizado no habilitaba el servicio OpenRC `modloop`, por lo que `/lib/modules` nunca se enlazaba al modloop.
- Prueba en caliente: `rc-service modloop start` + `modprobe evdev` creó event0/event1/event2 y Xorg los agregó con `libinput`. La prueba `Ctrl+Alt+F2`/`Ctrl+Alt+F7` cambió correctamente entre VT y escritorio.
- Solución permanente: `modloop` en runlevel `sysinit` y `evdev` en `/etc/modules`, cargado por el servicio `modules` antes del runlevel default/LightDM.

## Splash y estabilización del escritorio 2026-09-05
- Se investigó Alpine edge actual: existen `plymouth` y `plymouth-openrc-plugin`, pero el gran retraso del Live ocurre dentro de initramfs antes de OpenRC.
- Alpine `mkinitfs` ya integra BusyBox `fbsplash` y cambia a tty16, redirigiendo mensajes a tty1. Se usa esta ruta nativa porque cubre la instalación diskless desde el inicio y evita agregar otra dependencia al Live.
- `apk-tools 3` soporta `--progress-fd`; se comprobó que emite líneas `actual/total install`. El initramfs se parchea para convertir ese progreso real a 5–88% y enviarlo al FIFO `/.splash.ctrl`.
- ESC alterna entre tty16 (splash) y tty1 (detalles reales). Antes de `switch_root` hay un watcher en initramfs; OpenRC toma el relevo con `yah-splash-keys`.
- LightDM se sobrescribe en el APKoVL con una compuerta de readiness: necesita localmount, D-Bus, elogind, NetworkManager y `yah-live-user`; espera `udevadm settle`, inicia Xorg y sólo retira el splash cuando detecta `xfce4-session`.
- Si XFCE no queda listo dentro del límite, se retira el splash y se cambia a tty1 para mostrar el error en vez de dejar una pantalla negra.

## DexOS: correcciones de splash, transición e instalador 2026-09-05
- Feedback runtime: ESC mostraba logs correctamente, pero al volver sólo se repintaba la barra sobre el framebuffer con texto. Causa: `fbsplash` recupera el VT pero no redibuja la imagen completa al re-adquirirlo.
- Solución: el initramfs copia la imagen/config de splash al root Live, conserva el porcentaje actual y tanto el watcher de initramfs como el de OpenRC ejecutan un repintado one-shot de `fbsplash` al volver a tty16, luego restauran la barra al porcentaje vigente.
- Feedback runtime: existía un intervalo negro entre el splash y el primer frame completo de XFCE. Solución: LightDM ejecuta `dexos-xsetup` con `xsetroot -solid '#6b2a2e'` inmediatamente al crear Xorg; además espera `xfce4-session`, `xfwm4`, `xfdesktop` y `xfce4-panel` antes de considerar listo el escritorio.
- Feedback runtime: el instalador no abría. Causa: el `.desktop` usaba `Exec=doas /usr/local/bin/dexos-installer`, pero doas sólo autorizaba el comando root final. Solución: el acceso directo ejecuta el wrapper como usuario; el wrapper abre `xfce4-terminal --command="doas /usr/local/sbin/dexos-install-root"`; sólo `setup-alpine` se eleva.
- Rebranding solicitado: sistema visible `DexOS`, hostname `dexos-live`, usuario Live `dexos`, ISO `DexOS-edge-x86_64.iso`, volumen `alpine-dexos edge x86_64`, splash/fondo/acento en rojo mate.
- Para evitar parches acumulativos del initramfs, cada build restaura `initramfs-init` desde el APK cacheado de `mkinitfs` y después aplica el parche DexOS.
