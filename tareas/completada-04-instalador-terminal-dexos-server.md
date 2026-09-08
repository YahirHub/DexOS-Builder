# Tarea
Crear y validar el instalador terminal propio de DexOS Server.

# Estado
Completada el 2026-09-08.

# Criterios de aceptación validados
- `install` abre el asistente propio desde el Live y no depende de `setup-alpine`.
- La instalación funciona sin Internet usando exclusivamente el repositorio APK incluido en la ISO.
- Wi-Fi se configura con NetworkManager/`nmcli` y los perfiles se preservan al sistema instalado.
- OpenSSH, Avahi y NetworkManager quedan habilitados en el sistema instalado.
- El nombre pedido por el instalador se normaliza a `<nombre>.local` sin duplicar `.local`.
- Enter en la contraseña de root hereda la contraseña del usuario administrador.
- El acceso root por SSH se pregunta explícitamente y configura `PermitRootLogin yes/no`.
- El medio de instalación no aparece entre los discos instalables.
- La selección de disco, raíz y ESP usa menús numerados.
- El modo disco completo solo exige confirmación s/y; no exige escribir `BORRAR`.
- El race de nodos `/dev/vdaN` se corrige consultando sysfs y creando el nodo con `mknod` si es necesario.
- El modo coexistencia reutiliza una ESP existente sin formatearla, formatea solo la raíz seleccionada y conserva las otras particiones.
- GRUB soporta BIOS/UEFI según el layout, habilita `os-prober` y contiene `ntfs-3g` para ayudar a detectar Windows.
- `boot-order` permite seleccionar interactivamente la entrada predeterminada de GRUB.
- La instalación genera initramfs explícitamente y fija la raíz por UUID.
- No se añadieron Xorg, XFCE, LightDM, Firefox, Mesa, audio, Bluetooth ni firmware de GPU.
- Las pruebas estáticas pasan y el repositorio final contiene 170 APK.
- Instalación completa en disco virtual de 8 GiB: `INSTALL_RC=0`.
- Instalación de coexistencia: `COEXIST_RC=0`; se preservaron los marcadores de ESP y de otra partición Linux.
- ISO final inspeccionada desde dentro: `install`, `boot-order`, `os-prober`, `ntfs-3g`, NetworkManager, Avahi, OpenSSH y kernel LTS presentes.

# ISO final
- Ruta: `/workspace/yah-alpine/out/DexOS-Server-edge-x86_64.iso`
- Tamaño: ~473 MiB
- SHA-256: `b8e2ad3c9e52794b713c3aeb18b6a886dad69b0250865ab4a341a47d9beb3d44`
