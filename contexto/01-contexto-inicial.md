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
