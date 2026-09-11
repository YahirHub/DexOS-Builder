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

## DexOS v002: compatibilidad Ventoy/USB
- En hardware físico, DexOS v001 con kernel stable 7.1.5 falló dentro del entorno de Ventoy antes de entrar al Live (`mounting /dev/loop0 on /ventoy/mnt failed`, BusyBox de Ventoy, initramfs emergency shell).
- Se volvió al kernel LTS 6.18.48, que ya había arrancado correctamente con el Ventoy del usuario.
- Se conservaron las correcciones de v001: firmware Wi-Fi realmente instalado en el Live, servicios de detección/refresh de Wi-Fi y `su` Live sin contraseña mediante doas.
- Se añadieron módulos tempranos `uas`, `sr-mod` e `isofs` además de `loop,squashfs,sd-mod,usb-storage` en GRUB y Syslinux para mejorar compatibilidad con Ventoy/USB/ISO loop.
- El sistema instalado también vuelve a `linux-lts`.
- Nueva ISO: `DexOS-edge-x86_64-v002.iso`.
- SHA-256: `f793ab1c0f21dc1521a8400f167d9df993ed0ed4cc7ae1773338b9f6902bc194`.

## DexOS v005: wallpaper Live y cursor del selector de idioma
- Se corrigió el wallpaper del Live para evitar que XFCE vuelva a su fondo predeterminado.
- El wallpaper exacto se instala con extensión PNG en `/usr/share/dexos/dexos-wallpaper.png`, `/usr/share/backgrounds/xfce/DexOS.png` y `/usr/share/xfce4/backdrops/DexOS.png` conservando bytes exactos.
- El usuario Live recibe una copia directa de `xfce4-desktop.xml` en su configuración antes del primer inicio de sesión.
- `dexos-apply-theme` crea/actualiza propiedades para cada monitor conectado detectado por `xrandr` y recarga `xfdesktop`.
- Se añadió `breeze-cursors`; LightDM/Xorg fija `left_ptr` y la sesión exporta `XCURSOR_THEME=Breeze`, `XCURSOR_SIZE=24` antes del selector de idioma.
- El selector GTK también fuerza explícitamente un cursor visible mediante GDK.
- ISO v005: `/workspace/yah-alpine/out/DexOS-edge-x86_64-v005.iso`.
- SHA-256: `20f81f30a90d5b5a5cef84f69d3f7aef37f5096a4bd185911a87153b6f6354cc`.

## DexOS v006: branding instalado, splash y flujo final del instalador
- Se corrigió la persistencia del branding desde el Live al sistema instalado: wallpaper DexOS en `/usr/share/dexos/dexos-wallpaper.png`, `/usr/share/backgrounds/xfce/DexOS.png` y `/usr/share/xfce4/backdrops/DexOS.png`.
- LightDM instalado usa explícitamente el wallpaper DexOS, tema oscuro, cursor Breeze y `user-background=false`.
- El usuario instalado recibe `xfce4-desktop.xml` en su HOME para evitar que XFCE vuelva al fondo predeterminado en el primer login.
- La sesión DexOS lanza `dexos-apply-theme` directamente antes de XFCE como waiter, además de la entrada XDG autostart.
- El lanzador del instalador usa el mecanismo de confianza de XFCE mediante `metadata::xfce-exe-checksum` con SHA-256, no sólo chmod/metadata::trusted.
- El instalador muestra al finalizar un diálogo con `Reiniciar ahora` / `Más tarde`.
- El sistema instalado copia y aplica el parche DexOS de initramfs, incluye `boot.ppm`, habilita `dexos-bootsplash` y oculta cursor de consola con `vt.global_cursor_default=0`.
- ISO v006: `/workspace/yah-alpine/out/DexOS-edge-x86_64-v006.iso`.
- SHA-256: `748cb713d130b3ae158476e68e15839d73cb99d1ea447e6f76863ce4b9d214c2`.
- VM de prueba reiniciada con QCOW totalmente nuevo de 24 GiB: `/workspace/yah-alpine/runtime/dexos-v006-clean.qcow2`.

## DexOS v007: wallpaper XFCE aplicado en sesión real y splash instalado autocontenido
- Se inspeccionó la instalación v006 real desde el QCOW y se confirmó que el XML de XFCE sí apuntaba a DexOS, pero `dexos-apply-theme` podía ejecutarse sin el DBus correcto de la sesión.
- v007 espera a `xfdesktop` e importa `DBUS_SESSION_BUS_ADDRESS`, `DISPLAY` y `XAUTHORITY` desde `/proc/<pid>/environ` antes de usar `xfconf-query`.
- Reaplica el wallpaper a propiedades existentes, monitor real y `monitor0`, recarga `xfdesktop` y repite después de la migración inicial de XFCE.
- Se inspeccionó el initramfs instalado v006 y se detectó que contenía `/usr/share/dexos/boot.ppm` pero no lo seleccionaba como fallback, y faltaban los enlaces BusyBox usados por el splash.
- v007 añade fallback explícito `fbsplash=/usr/share/dexos/boot.ppm`, feature `kms` y los archivos `/sbin/fbsplash`, `/usr/bin/setsid`, `/usr/bin/chvt`, `/bin/stty` al initramfs instalado.
- ISO v007: `/workspace/yah-alpine/out/DexOS-edge-x86_64-v007.iso`.
- SHA-256: `41f2d211888586fb574e758cc52af08da5cf63c8b11a048addf3faf40ef9bbca`.
- VM v007 arrancada con QCOW nuevo `/workspace/yah-alpine/runtime/dexos-v007-clean.qcow2` y túnel noVNC validado.

# 2026-09-09 — Paridad del instalador Desktop con DexOS Server
## Objetivo
Tras estabilizar el instalador Server en hardware real, aplicar al instalador gráfico Desktop las mismas garantías de coexistencia y arranque: detección de particiones sin formato, huecos no asignados, Windows/Linux, ESP reutilizable, GPT/MBR, BIOS/UEFI y GRUB conservador.

## Decisiones tomadas
- Mantener el frontend GTK3 existente y reforzar el backend Python, evitando reescribir el instalador desde cero.
- El modo actualmente llamado `alongside` evolucionará a coexistencia genérica con Windows/Linux.
- Coexistencia podrá usar una partición existente elegible o crear una nueva exclusivamente dentro de un hueco no asignado.
- La ESP nunca se formatea en coexistencia/manual; sólo el modo borrar disco crea/formatea una nueva ESP.
- Si el Live arrancó en UEFI, una ESP válida del disco seleccionado será obligatoria. En BIOS podrá omitirse si el disco admite instalación GRUB BIOS.
- La raíz se formatea explícitamente ext4 sólo después de una revalidación inmediata del destino.
- Se conservarán las características Desktop ya implementadas: XFCE, branding, splash, Wi-Fi, audio y tema Argon.

## Arquitectura actual
- UI: `project/installer/dexos-installer.py` (Gtk.Assistant).
- Backend privilegiado: `project/installer/dexos-installer-backend.py`.
- Tests: `project/tests/test-installer.py`.
- Referencia funcional: instalador DexOS Server respaldado en `YahirHub/DexOS-Builder`.

## Problemas encontrados
El Desktop ya tenía borrado completo, un modo "junto a Windows" y manual, pero el modo de coexistencia dependía de `parted`, sólo ofrecía discos detectados como Windows, exigía ESP incluso en BIOS y no permitía seleccionar una partición existente dentro del flujo de coexistencia.

## Próximos pasos
Implementar la paridad funcional, ejecutar tests, construir ISO y validar instalación/coexistencia en QEMU antes de marcar la tarea como completada.

## 2026-09-10 — DexOS Desktop v010: UX, energía y gestor gráfico de arranque

Se preparó `DexOS-edge-x86_64-v010.iso` con los siguientes cambios de escritorio:

- Se corrigió la resolución del tema `Adwaita-Xfce` creando el alias de ruta esperado y se añadió el icono `applications` usado por Whisker para «Todas las aplicaciones». Las categorías Configuración e Internet vuelven a resolver sus iconos del tema `adwaita-xfce`.
- Se añadió el tema de cursor `DexOS-Windows`, generado de forma propia con flecha blanca y borde oscuro, y se aplica tanto en LightDM como en la sesión XFCE a 32 px. Los cursores no definidos heredan de Adwaita.
- Se añadió `power-profiles-daemon` y el servicio `dexos-power`, que pide perfil `balanced`, EPP `balance_power`/`balance_performance`, gobernador `schedutil`/`powersave` y `platform_profile=balanced` cuando el hardware lo ofrece.
- Se redujo carga innecesaria al iniciar: `dexos-video-init` ya no ejecuta `glxinfo`, `vainfo` ni `vdpauinfo` en cada login; `dexos-apk-refresh` limita `apk update` a una vez cada 24 h y lo ejecuta con prioridad baja.
- Se añadió `Protección de la vista`, interfaz GTK basada en `redshift`, con interruptor persistente y temperatura de 3000–6500 K. La selección se reaplica al iniciar sesión.
- `boot-order` ahora expone `--list` y `--set` para ser usado por una interfaz gráfica sin sacrificar el modo terminal.
- Se añadió `Orden de arranque`, aplicación GTK de escritorio que permite elegir el sistema predeterminado y ejecutar «Escanear discos y actualizar GRUB». El escaneo llama `grub-update`, que combina `os-prober` con `31_dexos_other_os` y revisa otros discos/particiones para Windows, Linux y cargadores EFI.
- El acceso administrativo del gestor gráfico usa `pkexec` cuando está disponible y conserva `doas` como fallback.

Validación realizada:

- `test-config: OK`
- `test-installer: OK`
- `git diff --check`: sin errores.
- ISO v010 generada correctamente, 1,395,523,584 bytes.
- SHA-256: `99fbb237b15a608263365cd73f1c227d43ae6dbf1745f4bde4a26a189a162379`.
- El initramfs de la ISO mantiene compresión XZ y el overlay incluye gestor de arranque, protección de vista, perfil de energía, cursor y lanzadores.

## 2026-09-10 — DexOS Desktop v012: GeoClue2 y credenciales del instalador

- Se añadió `geoclue` 2.x (`geoclue` + `geoclue-lang` en Alpine) a Live y al sistema instalado.
- Redshift vuelve a usar `location-provider=geoclue2` para ajuste automático por amanecer/atardecer; DexOS autoriza el cliente `redshift` mediante `/etc/geoclue/conf.d/90-dexos-redshift.conf`.
- Protección de la vista permite elegir ajuste automático por GeoClue2 o temperatura manual, y tiene opción persistente «Iniciar protección automáticamente al entrar a DexOS». El autostart global sólo aplica Redshift cuando el usuario marcó esa opción.
- El instalador marca por defecto «Usar la misma contraseña para root»; al desmarcarlo se habilitan los dos campos de contraseña root independiente.
- El nombre de usuario acepta mayúsculas en la interfaz y se normaliza a minúsculas antes de enviarlo al backend; el backend vuelve a normalizar por seguridad antes de crear la cuenta.
- ISO final: `DexOS-edge-x86_64-v012.iso`, 1,395,523,584 bytes, SHA-256 `b7a19d1fc34d647ea8dc60bc15b23065a7747e2716071fb516cf5037cc5fb73f`.
- `test-config: OK`, `test-installer: OK`, checksum ISO verificado.

## 2026-09-10 — DexOS Desktop v013: persistencia de volumen/brillo y autenticación GRUB

Se corrigieron dos regresiones observadas después de instalar v012:

- `dexos-audio-init` ya no ejecuta `wpctl set-volume ... 1.0` ni fuerza mute/unmute al iniciar sesión. WirePlumber mantiene su perfil `main` stateful y conserva volumen/mute del usuario. Se añadió `alsa-utils-openrc` y se habilitó el servicio `alsa`, que guarda `/var/lib/alsa/asound.state` al detenerse y lo restaura al arrancar para conservar también el mezclador ALSA de hardware. `alsactl init` queda limitado al primer arranque, cuando todavía no existe estado guardado.
- Se añadió `dexos-backlight`, servicio OpenRC que guarda el brillo actual de cada dispositivo de `/sys/class/backlight` en `/var/lib/dexos/backlight` durante apagado/reinicio y restaura esos valores en el siguiente arranque, con límites según `max_brightness`.
- El gestor gráfico `Orden de arranque` ahora solicita elevación mediante `pkexec` antes de crear su ventana. Una política PolicyKit de DexOS (`org.dexos.boot-manager.policy`) usa `auth_admin_keep` y permite el contexto gráfico X11. Una vez autenticado, toda la aplicación corre con privilegios y puede leer `/boot/grub/grub.cfg`, cambiar la entrada predeterminada y ejecutar `grub-update` sin el error previo de `sed: Permission denied`.
- Se añadió `polkit-common` explícitamente para garantizar que `pkexec` esté disponible además del agente XFCE ya incluido.

Validación v013:

- ISO: `/workspace/yah-alpine/out/DexOS-edge-x86_64-v013.iso`
- Tamaño: ~1.3 GiB.
- SHA-256: `8246cf4ae3eee41ccabbbf905161bec89d3bf0eb76c5cdcfdee8eec89cbde6c3`.
- `sha256sum -c`: OK.
- Overlay inspeccionado: servicios `alsa` y `dexos-backlight` habilitados; política PolicyKit y gestor GRUB presentes; no quedan comandos que fuercen volumen/mute.
- XML de PolicyKit parseado correctamente.
- `test-config: OK`, `test-installer: OK`, `git diff --check`: OK.

## 2026-09-10 — DexOS Desktop v014: brillo persistente y Redshift sin Internet

Se corrigió la persistencia de brillo de v013. La causa estaba en `dexos-backlight-state`: la validación usaba un patrón POSIX `''*` dentro de `case`, que equivale a `*` y por tanto coincidía con cualquier valor. Como resultado, `restore_backlights()` saltaba siempre todas las interfaces y nunca escribía el brillo guardado aunque el estado sí se hubiese almacenado correctamente.

Cambios v014:

- La validación de `brightness` y `max_brightness` ahora se hace por separado y sólo descarta valores vacíos/no numéricos.
- La restauración espera hasta 5 segundos por la aparición de `/sys/class/backlight/*` para equipos cuyos drivers de retroiluminación aparecen tarde.
- Se registra en syslog cada restauración efectiva con `dexos-backlight` para facilitar diagnóstico en hardware real.
- Redshift automático ahora se ejecuta mediante un pequeño supervisor de DexOS: con Internet usa GeoClue2; si NetworkManager no reporta conectividad completa o GeoClue2 falla, aplica una temperatura basada en la hora local y continúa funcionando sin red.
- El fallback horario usa 6500 K durante el día, la temperatura nocturna configurada entre 20:00 y 06:00, y transiciones graduales 06:00–08:00 y 18:00–20:00.
- Si vuelve Internet, el supervisor reintenta GeoClue2 aproximadamente una vez por minuto.
- El modo manual sigue disponible y aplica exactamente la temperatura elegida, sin depender de red ni ubicación.

Validación v014:

- ISO: `/workspace/yah-alpine/out/DexOS-edge-x86_64-v014.iso`
- Tamaño: 1,395,523,584 bytes.
- SHA-256: `94ece08a58497bcdfc0fd2a7b10df39f007e3688fcb68a8e217c3583c280e9f3`.
- `sha256sum -c`: OK.
- Overlay final inspeccionado: contiene la validación corregida del brillo y el supervisor/fallback horario de Redshift.
- `test-config: OK`, `test-installer: OK`, `git diff --check`: OK.
- La corrección exacta del brillo está validada por código/pruebas; queda pendiente comprobar la persistencia en un portátil físico con v014 después de reiniciar.

## 2026-09-11 — DexOS Desktop v015: Night Light persistente, arranque limpio y touchpad tipo Windows

Cambios solicitados tras validar v014 en hardware real:

- Protección de la vista / Redshift ahora persiste con el mismo modelo que otras distros: el estado `enabled` es la fuente de verdad. Si el usuario deja la protección activada, `/etc/xdg/autostart/dexos-eye-protection.desktop` ejecuta `--startup` en la siguiente sesión y reaplica automáticamente el modo manual o automático. Ya no existe un segundo checkbox de «iniciar automáticamente» que pudiera quedar desmarcado mientras la protección estaba activa.
- Se endureció el manejo del PID del supervisor de Redshift para que un PID guardado antes de reiniciar nunca mate por accidente a otro proceso que haya reutilizado ese número.
- Se eliminaron las imágenes y splash personalizados de arranque/sesión de DexOS: no se incluye `boot.jpg`, `boot.ppm`, `fbsplash.ppm`, `dexos-session-splash`, `dexos-bootsplash`, `dexos-bootsplash-finish`, `dexos-splash-keys` ni el parche de fbsplash del initramfs. Los argumentos `splash` también fueron retirados de GRUB, Syslinux y de la entrada Linux instalada.
- Se conserva el wallpaper DexOS como fondo inicial. `dexos-prepare-desktop` lo siembra una sola vez y crea `~/.config/dexos/wallpaper-initialized`; desde ahí XFCE es dueño del estado. Si el usuario cambia el wallpaper, DexOS ya no modifica `last-image` ni vuelve a cargar el fondo predeterminado en sesiones posteriores.
- `dexos-apply-theme` queda limitado a tema GTK/iconos/cursor y no toca el fondo de escritorio.
- Touchpad ajustado al comportamiento estable más cercano a Windows Precision Touchpad disponible con libinput/Xorg: aceleración adaptativa, velocidad base neutra, tap, arrastre por tap, clic derecho de dos dedos / áreas de botón, scroll de dos dedos horizontal y vertical, scroll no invertido, rechazo mientras se escribe y distancia de scroll de 15 px. No se afirma equivalencia exacta con la curva privada de Windows.

Validación v015:

- ISO: `/workspace/yah-alpine/out/DexOS-edge-x86_64-v015.iso`
- Tamaño: 1,395,523,584 bytes.
- SHA-256: `996270f945b8d581002865f40bf504bf08de758cd60d820a30ac67c5d5ec46af`.
- `sha256sum -c`: OK.
- GRUB Live y Syslinux inspeccionados: sin argumento `splash`.
- ISO inspeccionada: no existe `fbsplash.ppm`.
- Overlay final inspeccionado: no contiene imágenes/splash personalizados; Night Light restaura según `enabled`; wallpaper sólo se siembra una vez; configuración touchpad incluida.
- `test-config: OK`, `test-installer: OK`, `git diff --check`: OK.
- Queda pendiente validar en hardware real el tacto final del touchpad y confirmar visualmente que Night Light reaparece tras reiniciar v015.
