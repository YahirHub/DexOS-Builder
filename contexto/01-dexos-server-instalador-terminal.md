# Fecha
2026-09-08

# Objetivo
Convertir DexOS Server en una ISO terminal offline con instalador propio `install`, Wi-Fi mediante NetworkManager/nmcli y repositorios listos tanto en Live como en el sistema instalado.

# Decisiones tomadas
- No usar `setup-alpine` para la instalación principal: su resolución de dependencias puede requerir paquetes que no estén en el repositorio offline reducido.
- Reutilizar las ideas seguras del backend del instalador gráfico DexOS: validación del disco, confirmación destructiva, `apk --root --no-network`, bind mounts del runtime, generación explícita de initramfs y GRUB BIOS/UEFI.
- Mantener el instalador Server en POSIX shell para no añadir Python/GTK al Live.
- Usar NetworkManager + `networkmanager-cli` para que `nmcli` exista en Live e instalado.
- La instalación soportará inicialmente borrado de disco completo. Se evita portar el modo dualboot del instalador gráfico porque requeriría más herramientas y superficie de error en una edición Server ultraligera.
- El Live debe tener `/etc/apk/world`; incluir paquetes en el repositorio ISO no basta para que estén instalados durante la sesión Live.
- Las conexiones Wi-Fi creadas en el Live se preservan en `/etc/NetworkManager/system-connections` del sistema instalado.

# Arquitectura actual
- `server/mkimage/mkimg.dexserver.sh`: perfil mkimage y repositorio APK offline.
- `server/mkimage/genapkovl-dexserver.sh`: overlay de Live, servicios, repositorios, world y comando `install`.
- `server/install`: asistente terminal y lógica de instalación.
- `server/build-dexos-server.sh`: build reproducible, parches necesarios de mkimage/update-kernel y ensamblado ISO fuera de proot.
- `project/installer/`: instalador gráfico anterior conservado como referencia, no se incluye en DexOS Server.

# Librerías usadas
Ninguna librería de aplicación nueva. Se usan BusyBox/POSIX shell y herramientas Alpine: apk, util-linux, e2fsprogs, dosfstools, GRUB, NetworkManager/nmcli, OpenSSH y Avahi.

# Archivos importantes modificados
Pendiente durante esta tarea: `server/install`, `server/mkimage/mkimg.dexserver.sh`, `server/mkimage/genapkovl-dexserver.sh`, lista de paquetes y pruebas Server.

# Problemas encontrados
- La ISO probada mostraba el asistente estándar `setup-alpine`, que intentaba resolver `openssl` y `kbd-bkeymaps` y podía necesitar Internet.
- El overlay Server no tenía `/etc/apk/world`; por tanto, paquetes presentes en la ISO como NetworkManager/nmcli no estaban garantizados en el root Live.
- El instalador shell preliminar no regeneraba ni verificaba explícitamente el initramfs instalado.

# Soluciones implementadas
En progreso.

# Pendientes
- Implementar world Live mínimo.
- Endurecer `install`.
- Añadir pruebas estáticas.
- Recompilar ISO.
- Validar contenido y arranque.

# Próximos pasos
Modificar los archivos Server, validar sintaxis y cierre de paquetes offline, compilar ISO y comprobar que el Live contiene `install`, `nmcli`, repositorios y servicios esperados.


# Resultado final 2026-09-08
Se completó la evolución del instalador terminal tras las pruebas reales en QEMU/KVM.

## Cambios finales del asistente
- Confirmación destructiva simplificada a s/y; se eliminó la frase `BORRAR <disco>`.
- El medio Live se excluye automáticamente del selector de discos.
- Selección numerada de disco, partición raíz y ESP.
- Modo coexistencia: reutiliza ESP sin formatear, formatea únicamente la raíz seleccionada y preserva otras particiones.
- Corrección robusta del race de `/dev/vdaN`: `refresh_partition_nodes`, `partx`, `mdev` y fallback `mknod` usando `/sys/class/block/<part>/dev`.
- Corrección del montaje: primero se monta la raíz y después se crea/monta `/boot/efi`.
- Compatibilidad con util-linux 2.42: no se combina `lsblk --list` con `--raw`.
- Nombre mDNS: acepta `foo` o `foo.local`, normaliza ambos a hostname `foo` y anuncio `foo.local`.
- Enter en contraseña root reutiliza la contraseña del administrador.
- Pregunta independiente para `PermitRootLogin yes/no`.
- `os-prober` y `ntfs-3g` incluidos; GRUB se genera con `GRUB_DISABLE_OS_PROBER=false`.
- Nueva herramienta `/usr/local/sbin/boot-order`, basada en `grub-set-default`, para elegir interactivamente el sistema predeterminado.

## Pruebas reales
### Disco completo
QEMU/KVM, disco virtio limpio de 8 GiB, sin NIC. Resultado `INSTALL_RC=0`.
Se validaron GPT, FAT32 ESP, ext4, instalación de 170 APK offline, initramfs, GRUB BIOS y UEFI, repositorios, Avahi, SSH, NetworkManager y `boot-order`.

### Coexistencia
Layout de prueba:
- vda1: ESP FAT32 compartida, con marcador `EFI/Existing/keep.txt`.
- vda2: ext4 simulando otro Linux, con marcador `KEEP-OTHER.txt`.
- vda3: partición elegida para DexOS.
Resultado `COEXIST_RC=0`.
Tras instalar: `KEEP-EFI` y `KEEP-OTHER` permanecieron intactos, DexOS quedó en vda3 y se creó `EFI/DexOS/grubx64.efi` sin borrar el contenido EFI existente.
La partición Linux sintética no fue detectada por os-prober porque no contenía un cargador/kernel arrancable real; sí se verificó que os-prober se ejecuta y que GRUB queda habilitado para incorporar Windows/Linux reales detectables.

## ISO definitiva
- `/workspace/yah-alpine/out/DexOS-Server-edge-x86_64.iso`
- Aproximadamente 473 MiB.
- SHA-256: `b8e2ad3c9e52794b713c3aeb18b6a886dad69b0250865ab4a341a47d9beb3d44`
- APKINDEX interno: 170 paquetes.
- Verificado sin Xorg, XFCE, LightDM, Firefox, Mesa, audio, Bluetooth ni firmware de GPU.


# Corrección de red y DNS 2026-09-08
Tras arrancar una instalación real con una NIC VirtIO/NAT se detectó que los repositorios APK estaban correctamente configurados, pero el sistema no tenía `/etc/resolv.conf` y NetworkManager mostraba `eth0` como `unmanaged` con motivo 71: `The device is unmanaged because the link is not initialized by udev`.

## Causa raíz
El Live y el sistema instalado usaban BusyBox `mdev` como gestor de dispositivos. NetworkManager 1.58 en Alpine edge necesita que las interfaces hayan pasado por udev/eudev para gestionarlas correctamente. Sin coldplug de udev no obtenía DHCP y, por tanto, tampoco generaba DNS.

## Solución
- Se añadieron `eudev` y `eudev-openrc` al Live, al sistema instalado y al repositorio offline.
- En `sysinit` se sustituyó `mdev` por `udev`, `udev-trigger` y `udev-settle`; se mantiene `hwdrivers` y `modloop`.
- Se añadió `udev-postmount` al runlevel `default`.
- NetworkManager usa un archivo `10-dexos-network.conf` con `plugins=keyfile`, `rc-manager=file`, `dns=default` e `ifupdown managed=true`.
- Se crea un perfil `DexOS Wired` autoconnect con IPv4/IPv6 DHCP automático, tanto en Live como en el sistema instalado.
- `/etc/resolv.conf` incluye fallback `1.1.1.1` y `8.8.8.8`; cuando hay DHCP/Wi-Fi NetworkManager lo reemplaza con el DNS real de la conexión.
- Los perfiles Wi-Fi creados durante el Live siguen copiándose al sistema instalado.

## Validación real
Se arrancó la ISO corregida desde cero en QEMU/KVM con `-nic user,model=virtio-net-pci`, sin ejecutar `udhcpc` ni comandos de reparación manual. Resultado:
- `eth0`: `connected`, conexión `DexOS Wired`.
- IPv4: `10.0.2.15/24`, obtenida dinámicamente.
- Gateway: `10.0.2.2`.
- `/etc/resolv.conf` fue generado por NetworkManager con `nameserver 10.0.2.3`.
- Ping a `1.1.1.1`: correcto.
- Resolución y ping de `dl-cdn.alpinelinux.org`: correctos.
- `apk update`: correcto, `APK_UPDATE_RC=0`, repositorios edge main/community accesibles.

## ISO actual después de la corrección
- `/workspace/yah-alpine/out/DexOS-Server-edge-x86_64.iso`
- Aproximadamente 474 MiB.
- SHA-256: `aab605a18285d3dccb9d421917b88154477dd599427401705930dc0752a58c1a`
- APKINDEX interno: 176 paquetes.
- Sigue sin Xorg, XFCE, LightDM, Firefox, Mesa, audio, Bluetooth ni firmware de GPU.

# GRUB robusto + tema Argon del DexOS de escritorio — 2026-09-08

## Problema reproducido
En una instalación real de coexistencia, el GRUB de DexOS podía terminar mostrando únicamente DexOS aunque hubiese otro sistema operativo en el disco. `GRUB_DISABLE_OS_PROBER=false` y el paquete `os-prober` ya estaban presentes, pero eso no garantiza una entrada útil: `os-prober` usa heurísticas y en algunos layouts reconoce una raíz de forma incompleta o no obtiene un kernel/cargador utilizable para `30_os-prober`.

## Detección de otros sistemas
Se mantiene `os-prober` como detector principal y se añadió `/etc/grub.d/31_dexos_other_os` como segunda capa propia de DexOS.

El fallback:
- inspecciona particiones ajenas en solo lectura; ext2/3/4 se monta con `ro,noload`;
- evita duplicar un Linux cuando `os-prober` + `linux-boot-prober` ya producen una entrada válida;
- reutiliza el `grub.cfg` del Linux externo mediante `configfile` cuando existe;
- si no existe un GRUB externo, detecta kernel/initramfs y genera una entrada por UUID;
- contempla `/boot` separado y `subvol=`/`subvolid=` de la raíz;
- detecta cargadores UEFI, incluido `EFI/Microsoft/Boot/bootmgfw.efi`, y genera `chainloader` por UUID;
- conserva el contenido de la ESP y las particiones de los otros sistemas.

Se añadió `/usr/local/sbin/grub-update` y el alias `/usr/local/sbin/update-grub`. El comando genera primero un `grub.cfg` temporal, lo valida con `grub-script-check` y sólo después publica `/boot/grub/grub.cfg`.

## Tema GRUB reutilizado desde DexOS de escritorio
A petición del proyecto se revisó el sandbox anterior del DexOS gráfico y se identificó el GRUB personalizado documentado allí: el tema **Argon**.

Se portó de forma literal el directorio de assets del proyecto gráfico a:
- fuente Server: `server/assets/argon-grub-theme/`;
- Live: `/usr/share/dexos/argon-grub-theme/`;
- sistema instalado: `/boot/grub/themes/argon/`.

El tema contiene 92 archivos: `theme.txt`, `background.png`, `LICENCE.txt`, fuentes Terminus y los iconos de sistemas operativos. Los tres hashes principales son:
- `theme.txt`: `8a6b6ab98ee189fbab809e3f105f6efb320157732c028068c5170be74376ffed`;
- `background.png`: `772f3ff45c450987557a308256bbd05c584af15fcb50942351a2fec34200d126`;
- `LICENCE.txt`: `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986`.

Se reprodujo el contrato visual del instalador gráfico:
```text
GRUB_TIMEOUT=8
GRUB_THEME="/boot/grub/themes/argon/theme.txt"
GRUB_GFXMODE="1920x1080,auto"
GRUB_GFXPAYLOAD_LINUX=keep
```

Se conservan además las decisiones de DexOS Server (`GRUB_DEFAULT=saved`, raíz por UUID, `GRUB_DISABLE_OS_PROBER=false`, `boot-order` y el fallback de detección). No se copiaron los parámetros de splash/XFCE del sistema gráfico porque no pertenecen a la edición Server.

## Validación QEMU/KVM
Se arrancó la ISO resultante sin red y se instaló en modo coexistencia sobre un disco de 8 GiB con:
- `vda1`: ESP FAT32 compartida;
- `vda2`: otro Alpine/Linux con kernel, initramfs y GRUB;
- `vda3`: destino DexOS Server.

Resultado:
- instalación offline de 176 APK completada;
- salida explícita `Found theme: /boot/grub/themes/argon/theme.txt` durante `grub-update`;
- 92 assets Argon copiados al sistema instalado y hashes idénticos al origen;
- `grub.cfg` contiene `set gfxmode=1920x1080,auto`, las dos fuentes Terminus y `set theme=($root)/boot/grub/themes/argon/theme.txt`;
- el otro Linux aparece en GRUB;
- el fallback UEFI de Windows fue generado en la prueba sintética correspondiente;
- `grub-script-check` finalizó con código 0;
- el `grub.cfg` del otro Linux y el marcador de la ESP compartida permanecieron intactos.

También se validaron por separado los fallbacks de Linux cuando se fuerza a `os-prober` a fallar: primero mediante `configfile` del GRUB externo y, sin ese archivo, mediante kernel/initramfs y `root=UUID=...`.

## ISO actual con Argon y detección robusta
- Ruta: `/workspace/yah-alpine/out/DexOS-Server-edge-x86_64.iso`
- Tamaño: `497025024` bytes (~474 MiB)
- SHA-256: `2decb0ed6b5da72bf26dd8fd62f95e71bf82408b65048d8684f22926509bf473`
- APKINDEX offline: 176 paquetes.

La ISO inmediatamente anterior, con la corrección de detección de otros SO pero sin Argon, se conservó para comparación en:
`/workspace/yah-alpine/out/archive/DexOS-Server-edge-x86_64-pre-argon-d07930ad.iso`.


# Instalador web Live + hotspot Wi-Fi robusto — 2026-09-08

## Particiones sin formato
El selector de coexistencia ya no depende de `FSTYPE`. Una partición creada desde Windows u otro sistema y dejada sin filesystem se acepta como raíz si:
- es una partición real del disco seleccionado;
- no está montada;
- es escribible;
- no es ESP ni BIOS Boot;
- tiene al menos 1 GiB.

Antes de inventariar se refrescan tabla y nodos (`blockdev --rereadpt`, `partx`, `udevadm trigger/settle`, fallback `mdev`). En QEMU se creó una GPT con `/dev/vda2` denominada `Windows empty slot`, sin ejecutar `mkfs`; `blkid` sólo mostró PARTLABEL/PARTUUID y `install --inventory` la devolvió como `sin-formato`, `eligible=yes`, `reason=ok`. El CGI web devolvió exactamente el mismo resultado.

## Portal Live
El Live incluye una UI multistep offline servida por `mini_httpd`, Tailwind 3.4.17 y Lucide 0.468.0 locales, backend CGI y los modos comunes `install --inventory` / `install --batch`. El hostname Live es `dexos-installer`, el portal es `http://dexos-installer.local/` y el acceso SSH temporal es `root/root`. Estas funciones son sólo del Live y no se copian al sistema instalado.

## Hotspot `Dex-Installer`: causa y corrección
La primera implementación podía no levantar AP porque la detección era demasiado temprana y la ISO no cubría firmware Intel ni varias familias adicionales. Además NetworkManager en Alpine necesita un `wpa_supplicant` D-Bus disponible para manejar Wi-Fi de forma fiable.

Se corrigió con:
- `wpa_supplicant -B -u` global iniciado antes de NetworkManager y revalidado por el monitor;
- monitor persistente cada 2 s que detecta radios por `nmcli` + `iw` y acepta USB Wi-Fi conectado después del arranque;
- desbloqueo `rfkill` cuando existe;
- validación real de capacidad AP mediante `iw phy`;
- reintento automático si NetworkManager aún no arrancó o el dispositivo apareció tarde;
- estado detallado (`waiting`, `unsupported`, `active`, razón y adaptador) y log `/var/log/dex-installer-hotspot.log`;
- firmware ampliado para Intel/iwlwifi, Realtek, MediaTek, Atheros, Broadcom/Cypress, Qualcomm, Marvell/NXP, Airoha, Atmel y `linux-firmware-other`.

## Validación runtime real del flujo AP
QEMU no emula una tarjeta Wi-Fi física, por lo que se validó con el módulo kernel `mac80211_hwsim`, que sí está presente dentro de `modloop-lts` de la ISO.

Procedimiento:
1. arrancar la ISO sin ningún radio Wi-Fi: estado `HOTSPOT=waiting`, `REASON=no-wifi-device`;
2. después del boot ejecutar `modprobe mac80211_hwsim radios=2`, simulando un radio/USB que aparece tarde;
3. el monitor detectó `wlan0 wlan1` automáticamente;
4. `wlan0` cambió a `type AP`, SSID `Dex-Installer`, canal 11 e IPv4 `10.42.0.1/24`;
5. `dnsmasq` arrancó;
6. `wlan1` se conectó como cliente al SSID, obtuvo DHCP `10.42.0.122/24`;
7. DNS cautivo respondió `portal.dex -> 10.42.0.1`;
8. HTTP desde el cliente devolvió `DexOS Server Installer`.

También se comprobó en el host físico de pruebas que su Intel `iwlwifi` (`wlan0`) anuncia modo `AP`; el nuevo `linux-firmware-intel` está incluido en la ISO.

## ISO actual tras la corrección de hotspot
- Ruta: `/workspace/yah-alpine/out/DexOS-Server-edge-x86_64.iso`
- Tamaño: `740294656` bytes (~706 MiB)
- SHA-256: `91db6e9aa83a2c2e3abfc959bdaec8845a875815d6fe2c4b4276a11deb27ea3d`
- APKINDEX offline: 194 paquetes.

La ISO inmediatamente anterior al arreglo final del hotspot quedó archivada como:
`/workspace/yah-alpine/out/archive/DexOS-Server-edge-x86_64-pre-hotspotfix-2d470842.iso`.


# Instalador web: Wi-Fi opcional y reinicio 2026-09-08
- La UI web permite buscar y conectar a una red Wi-Fi antes de instalar.
- El perfil se crea como `DexOS WiFi`, se deja sin vínculo al nombre/MAC Live y el instalador lo copia a `/etc/NetworkManager/system-connections/` del sistema final.
- El hotspot `Dex-Installer` nunca se baja deliberadamente para conectar. Si hay otro adaptador se usa directamente; si sólo existe la radio del AP se intenta crear `dexsta0` como interfaz managed concurrente. Si el driver rechaza AP+STA, la UI indica usar Ethernet o un segundo adaptador.
- `network.cgi` fue probado con redes simuladas, SSID con `:` y escenario AP+STA simulado; no ejecutó `connection down Dex-Installer`.
- `status.cgi` publica `NET\tconnectivity` para mostrar si el Live tiene Internet.
- Al completar `perform_install`, el instalador crea `/run/dexos-install-complete`; `reboot.cgi` sólo acepta POST después de ese marcador y programa `/sbin/reboot`.
- El botón `Reiniciar ahora` aparece en la pantalla final. La prueba QEMU obtuvo HTTP 400 antes del marcador, HTTP 200/`REBOOTING` después y el guest llegó a `reboot: Restarting system`.
- Se añadió regla CSS global `[hidden] { display: none !important; }` y el footer queda oculto durante todo el paso 5, corrigiendo el botón `Continuar` que Tailwind podía volver visible.
- ISO final de esta revisión: `/workspace/yah-alpine/out/DexOS-Server-edge-x86_64.iso`, 741343232 bytes, SHA-256 `74dbc2f01b6dc001f3b7005d7ef75bf500af4070e7724f421c5be3fe359cdc29`, APKINDEX 194 paquetes.


# Wi-Fi diferido y dashboard de login 2026-09-08
- Se eliminó del instalador web la conexión Wi-Fi en vivo/AP+STA (`network.cgi`, `dexsta0` y botones de escaneo/conexión). El hotspot `Dex-Installer` queda dedicado al acceso al instalador.
- El paso inicial ahora pide opcionalmente SSID y contraseña. No se intenta conectar en el Live; esos valores se pasan al instalador y se guardan en el target como Base64 dentro de `/etc/dexos/wifi-firstboot.conf` con modo `0600`.
- El sistema instalado incluye `/etc/init.d/dexos-wifi-firstboot`, que espera NetworkManager, busca una interfaz Wi-Fi durante hasta 15 s y conecta mediante `nmcli --ask`; si no hay radio o falla la conexión conserva el archivo para reintentar en el siguiente boot. Tras éxito borra el archivo temporal.
- NetworkManager del sistema instalado depende de `wpa_supplicant` mediante `/etc/conf.d/networkmanager` (`rc_need="wpa_supplicant"`) y el servicio se habilita en `default`.
- Se instaló `/usr/local/bin/wifi`: `status`, `scan`, `saved`, `connect`, `up`, `disconnect`, `forget`. Las operaciones mutables usan `doas` si el usuario no es root. Las contraseñas no van en argv: se pasan por stdin a `nmcli --ask`.
- Se instaló `/usr/local/bin/diskinfo` con el dashboard solicitado y `/etc/profile.d/10-dexos-diskinfo.sh` lo ejecuta una vez al abrir una shell interactiva con TTY.
- El botón `Reiniciar ahora` sigue protegido por `/run/dexos-install-complete` y el footer/Continuar permanece oculto durante el paso de instalación.
- Validación QEMU: instalación completa con SSID diferido; target con config `0600`, servicio habilitado y scripts presentes. Smoke tests con nmcli simulado validaron primer arranque y herramienta `wifi` sin filtrar contraseña por argv.
- ISO actual: `/workspace/yah-alpine/out/DexOS-Server-edge-x86_64.iso`, 741343232 bytes (~707 MiB), SHA-256 `0fb1b37937d6869e27e4d4f2ebfed372db6161058b1884722927f74801671bf7`, APKINDEX 194 paquetes.
