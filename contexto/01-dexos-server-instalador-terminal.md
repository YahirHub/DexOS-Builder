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
