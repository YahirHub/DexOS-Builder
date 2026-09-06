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

## LightDM no debe fallar por timeout de XFCE 2026-09-05
- Evidencia runtime: OpenRC mostró `Starting Display Manager ... [ ok ]` y después `XFCE no quedó listo` seguido de `ERROR: lightdm failed to start`.
- Causa: `start_post()` esperaba síncronamente 80 iteraciones de 250 ms (20 s) y devolvía 1 si XFCE aún no tenía sesión, wm, desktop y panel. En TCG ese límite era demasiado corto y el propio hook hacía fallar el servicio.
- Solución: LightDM ahora retorna éxito inmediatamente después de arrancar y lanza `dexos-desktop-ready` desacoplado con `nohup`. El monitor espera hasta 180 s, cierra el splash sólo cuando `xfce4-session`, `xfwm4`, `xfdesktop` y `xfce4-panel` están vivos, y no modifica el estado OpenRC de LightDM por lentitud.
- Si el proceso LightDM realmente muere, el monitor retira el splash y muestra un diagnóstico en tty1.
- El instalador se simplificó a Desktop Entry estándar: `Terminal=true` + `Exec=doas /usr/local/sbin/dexos-install-root`, eliminando dependencia del wrapper/opciones de `xfce4-terminal`.
- Identidad de consola: se agregan `/etc/os-release`, `/etc/issue` y `/etc/motd` con nombre DexOS; el menú GRUB/Syslinux se renombra a `DexOS Live`.

## Tema rojo dinámico por monitor 2026-09-05
- La primera prueba runtime posterior al arreglo de LightDM mostró que XFCE sí abría, pero el escritorio usaba un fondo azul/verde del monitor detectado en lugar del `monitor0` preconfigurado.
- Causa: XFCE 4.20 crea propiedades de fondo por nombre real de salida (`VGA-*`, `Virtual-*`, `eDP-*`, etc.), por lo que una configuración estática bajo `monitor0` no cubre todas las máquinas.
- Solución: `dexos-apply-theme` se ejecuta por autostart, espera a que xfdesktop publique sus propiedades, enumera todos los `*/last-image` del canal `xfce4-desktop` y aplica `/usr/share/backgrounds/dexos.svg`, estilo de imagen y color. También refuerza tema/iconos y pinta rojo mate con xsetroot mientras se aplica.
- Se agregó invalidación inteligente del cache de kernel/initramfs basada en SHA-256 del parche de initramfs, para no rehacer el modloop cuando sólo cambia el APKoVL/tema.

## Instalador gráfico propio DexOS 2026-09-05
- Se elimina `setup-alpine` del flujo de instalación porque en runtime falló al llegar a timezone y reinició la sesión gráfica.
- Nuevo diseño: interfaz GTK3 no privilegiada (`/usr/local/bin/dexos-installer`) + backend root mínimo (`/usr/local/libexec/dexos-installer-backend`) autorizado únicamente mediante doas.
- El backend recibe configuración por stdin JSON; las contraseñas no se escriben en disco ni aparecen en la línea de comandos.
- Seguridad de disco: sólo enumera discos tipo `disk`, no read-only, >=8 GiB y sin montajes activos; el backend repite la validación antes de borrar. Requiere token exacto `BORRAR /dev/...`.
- Particionado completo GPT: 2 MiB BIOS Boot, 512 MiB ESP FAT32 y resto ext4 para raíz. Se instala GRUB i386-pc y x86_64-efi con fallback `EFI/BOOT/BOOTX64.EFI`.
- Instalación offline: `apk --root` usa exclusivamente el repositorio firmado incluido en la ISO durante el bootstrap. Luego el sistema instalado recibe los repos oficiales edge main/community.
- Timezone: se valida contra `/usr/share/zoneinfo` y se crea `/etc/localtime` directamente; no se llama a `setup-timezone` ni `setup-alpine`.
- Usuario instalado: cuenta normal en wheel/audio/video/input/netdev/plugdev, root bloqueado y administración mediante doas.
- El sistema instalado recibe branding DexOS, LightDM sin autologin, NetworkManager, eudev, XFCE y GRUB BIOS+UEFI.
- Dependencias nuevas del Live para la GUI: `python3` y `py3-gobject3`; GTK3 ya forma parte del stack XFCE.
- Pruebas: compilación Python, overlay, doas/launcher, symlink-safety, rutas SATA/NVMe, tabla GPT sobre archivo sparse de 9 GiB y disponibilidad de 80 paquetes del sistema destino en el APKINDEX offline.

## Corrección de arranque del sistema instalado 2026-09-05
- En la primera instalación real, GRUB y el kernel sí arrancaron, pero el initramfs cayó en recovery con: `mount: mounting /dev/vda3 on /sysroot failed: No such file or directory`.
- Causa: el arranque instalado dependía de que VirtIO se autodetectara a tiempo y GRUB había generado `root=/dev/vda3`, una ruta inestable.
- Corrección del backend:
  - feature `dexosroot` de mkinitfs que fuerza `virtio`, `virtio_ring`, `virtio_pci`, `virtio_blk` y `ext4` dentro del initramfs;
  - verificación previa de que esos módulos existen en el kernel instalado;
  - validación de que `initramfs-lts` fue realmente generado;
  - GRUB se reescribe después de `grub-mkconfig` para usar `root=UUID=<uuid>`;
  - se precargan `virtio,virtio_ring,virtio_pci,virtio_blk,ext4` mediante `modules=` y se fija `rootfstype=ext4`;
  - se rechaza la instalación si persiste un `root=/dev/...` en `grub.cfg`.
- Se añadió prueba de regresión que parte de un `linux ... root=/dev/vda3` y exige salida con UUID y módulos VirtIO.

## Wi-Fi real y wallpaper exacto 2026-09-06
- Se añadió `dexos-wifi-init` al Live y al sistema instalado, antes de NetworkManager.
- El servicio desbloquea RFKill, reenumera PCI/USB, carga drivers por modalias y añade fallback para Intel, Realtek, MediaTek, Atheros y Broadcom.
- Se añadieron `util-linux-misc` (provee `rfkill`) y `wireless-tools`; se mantienen NetworkManager Wi-Fi, iw, wpa_supplicant, wireless-regdb y linux-firmware completo.
- El wallpaper oficial fue descargado desde la URL dada por el usuario y guardado como `project/assets/dexos-wallpaper-user.png`.
- SHA-256 del wallpaper exacto: `573f997a56dbacdac4410a1a664277c2990107205e12af52de21b671ff8fbefd`.
- El build ahora falla si falta el wallpaper del usuario; no vuelve a sustituirlo silenciosamente por el generado.
- Se verificó byte a byte que `/usr/share/dexos/wallpaper` dentro de la ISO coincide con el archivo fuente.
- ISO resultante SHA-256: `c529655417d62bbbf85114c9ce4d0f5959aa71d29676e25e3eb350f271a6a291`.

## SU Live sin contraseña y Wi-Fi reforzado 2026-09-06
- El usuario Live `dexos` puede ejecutar `su` para convertirse en root sin contraseña mediante `pam_wheel.so trust` y root sin password sólo en el entorno Live.
- El sistema instalado NO hereda este bypass; conserva la contraseña root definida en el instalador.
- La detección Wi-Fi se dividió en dos fases:
  - `dexos-wifi-init` corre en `boot`, antes de NetworkManager, desbloquea rfkill, reenumera PCI/USB, carga drivers por modalias y hace dos pasadas.
  - `dexos-wifi-refresh` corre después de NetworkManager, fuerza radio Wi-Fi ON, rescan y registra el estado visto por NetworkManager.
- NetworkManager declara dependencia explícita `rc_need="dexos-wifi-init"`.
- Se genera `/var/log/dexos-wifi.log` con rfkill, iw, interfaces, PCI, USB y mensajes de kernel/firmware para diagnóstico en hardware real.
- ISO resultante SHA-256: `965ffdf11335de11517e23bd7e43de0a1be60e17e5e17ce8d1c986967c006656`.

## DexOS v001: SU Live robusto + firmware Wi-Fi real + kernel stable
- El `su` anterior fallaba porque Alpine Live resolvía `su` mediante BusyBox, que no usa la configuración PAM añadida.
- Se añadió `/usr/local/bin/su` sólo al Live. Para el usuario `dexos`, ejecuta `doas /bin/bash -l`; `/etc/doas.d/20-dexos-live.conf` permite `permit nopass dexos as root` sólo en el Live.
- Se detectó que el repositorio ISO contenía paquetes `linux-firmware-*`, pero `/etc/apk/world` del Live no los solicitaba, por lo que el Live podía arrancar drivers sin instalar los blobs de firmware.
- El Live ahora instala explícitamente firmware Wi-Fi para Intel, Realtek/rtlwifi/rtw88/rtw89, MediaTek, Atheros ath6k/9k_htc/10k/11k/12k, Broadcom/Cypress, Qualcomm, Marvell, TI, RSI y WFX.
- Live e instalado migraron de `linux-lts` a `linux-stable` (7.1.5 en el build actual) para ampliar soporte de hardware nuevo.
- Se deshabilitó el addon opcional `xtables-addons` para el flavor stable porque Alpine edge no publica `xtables-addons-stable`.
- La ISO se versiona como `DexOS-edge-x86_64-v001.iso`, volumen `DEXOS_V001`.
- SHA-256 v001: `d880a1ee05d2212567554096533f39d56f1ab0dba09446fff51f39219075de24`.
