# Tarea 06 — Instalador web Live y particiones sin formato

## Estado
en-proceso — implementación funcional; pendiente validación final en hardware físico del usuario y cierre del flujo de instalación web completo.

## Objetivo
Permitir instalar DexOS Server sobre particiones existentes aunque no tengan filesystem, y añadir al Live un instalador gráfico multistep accesible por navegador mediante una red Wi-Fi temporal `Dex-Installer` o por la red cableada.

## Criterios
- [x] Detectar y mostrar particiones reales sin `FSTYPE`, siempre que sean escribibles, no estén montadas, no sean ESP/BIOS Boot y tengan tamaño suficiente.
- [x] Refrescar tabla/nodos de partición antes de inventariar (`partx` + udev settle + fallback existente).
- [x] El instalador terminal y el web reutilizan las mismas reglas de validación.
- [x] Añadir `install --inventory` y modo no interactivo `install --batch` con validación estricta.
- [x] Servir UI offline multistep rojo mate, responsive y sin dependencias remotas.
- [x] Tailwind 3.4.17 y Lucide 0.468.0 incluidos localmente con licencias.
- [x] Iniciar servidor web automáticamente en el Live.
- [x] Hotspot abierto temporal `Dex-Installer`, IP `10.42.0.1`, DHCP/DNS cautivo local.
- [x] Detección por `nmcli` + `iw` y reintento cada 2 s para Wi-Fi interno o USB conectado después del arranque.
- [x] Iniciar `wpa_supplicant` D-Bus antes de NetworkManager para Wi-Fi/AP en Alpine.
- [x] Ampliar firmware Wi-Fi, incluyendo Intel/iwlwifi y otras familias comunes.
- [x] Exponer rutas comunes de portal cautivo.
- [x] Acceso SSH temporal Live `root` / `root`.
- [x] No persistir hotspot/web/credencial Live en el sistema instalado según listas y configuración.
- [x] Mantener NetworkManager normal en el sistema instalado.
- [x] Pruebas estáticas de frontend/backend/particionado/hotspot.
- [x] Validación QEMU de partición sin filesystem: `/dev/vda2` `Windows empty slot` apareció `sin-formato`, `eligible=yes`, `reason=ok`.
- [x] Validación QEMU del hotplug/AP con `mac80211_hwsim`: radio añadido después del boot -> `HOTSPOT=active`.
- [x] Cliente Wi-Fi virtual conectado a `Dex-Installer`, DHCP `10.42.0.122`, DNS cautivo -> `10.42.0.1`, HTTP -> `DexOS Server Installer`.
- [x] ISO recompilada e inspeccionada internamente.
- [x] El usuario confirmó en hardware físico que el flujo web corregido funciona correctamente, incluida la instalación sobre el almacenamiento preparado desde Windows.
- [x] Validación E2E QEMU de creación de raíz dentro de espacio no asignado, preservando PARTUUID y contenido de las particiones existentes.
- [x] Se prototipó conexión Wi-Fi desde el Live; posteriormente se retiró al comprobar en hardware físico que AP+STA no era fiable.
- [x] Se probó AP+STA mediante `dexsta0`; tras el resultado físico se eliminó esa ruta y el Live ya no intenta conectarse a otra red.
- [x] Añadir botón `Reiniciar ahora` sólo después de una instalación confirmada y proteger el CGI con `/run/dexos-install-complete`.
- [x] Ocultar completamente footer/botón Continuar durante el paso de instalación; `[hidden]` ya no puede ser anulado por las clases Tailwind.
- [x] Validación histórica de `network.cgi` y reboot; `network.cgi` fue retirado al adoptar Wi-Fi diferido, mientras el reboot permanece.
- [x] AP+STA simultáneo descartado tras la prueba física del usuario; se sustituyó por configuración Wi-Fi para el primer arranque.
- [ ] Validar en hardware físico la nueva ISO con Wi-Fi diferido y `diskinfo`; cerrar la tarea después de esa prueba.

## ISO actual para prueba física
- `/workspace/yah-alpine/out/DexOS-Server-edge-x86_64.iso`
- `741343232` bytes (~707 MiB)
- SHA-256: `0fb1b37937d6869e27e4d4f2ebfed372db6161058b1884722927f74801671bf7`
- APKINDEX offline: 194 paquetes.

## Nota de diagnóstico
Si un adaptador físico sigue sin levantar el AP, revisar en el Live:

```sh
/usr/local/sbin/dex-installer-live status
tail -200 /var/log/dex-installer-hotspot.log
nmcli -f DEVICE,TYPE,STATE,CONNECTION device status
iw dev
rfkill list
```

El estado distingue `no-wifi-device`, `no-ap-capability` y `activation-failed`, para separar falta de driver/firmware de un adaptador cuyo driver no soporta modo AP.


## Ajuste solicitado 2026-09-08 — Wi-Fi posterior al reinicio y dashboard
- [x] Eliminar el intento de conectar el Live a Wi-Fi mientras mantiene `Dex-Installer`; en hardware físico no fue viable.
- [x] Pedir SSID y contraseña opcionales en el formulario y usarlos sólo en el sistema instalado después de reiniciar.
- [x] Añadir servicio de primer arranque que cree/conecte el perfil NetworkManager y conserve el hotspot exclusivamente en el Live.
- [x] Añadir comando `wifi` para ver estado, escanear, conectar, activar perfiles guardados, desconectar y olvidar redes.
- [x] Añadir `/usr/local/bin/diskinfo` y ejecutarlo automáticamente al abrir una sesión interactiva.
- [x] Mantener el botón `Reiniciar ahora` y el footer oculto durante la instalación.
- [x] Recompilar ISO y validar en QEMU el perfil Wi-Fi pendiente, scripts instalados y dashboard.


### Validación del ajuste Wi-Fi diferido
- Instalación interactiva real en QEMU con SSID `Casa-E2E`: el Live mostró que la conexión se aplaza y completó la instalación correctamente.
- El target quedó con `/etc/dexos/wifi-firstboot.conf` modo `0600`, SSID correcto y contraseña codificada; no se imprimió la contraseña.
- `dexos-wifi-firstboot`, `wifi`, `diskinfo` y `10-dexos-diskinfo.sh` quedaron instalados con permisos correctos y el servicio está en `default`.
- NetworkManager instalado queda con `rc_need="wpa_supplicant"` y `wpa_supplicant` habilitado para disponer del backend Wi-Fi D-Bus.
- Smoke test con `nmcli` simulado confirmó que `dexos-wifi-firstboot` conecta por `--ask`, elimina el archivo temporal tras éxito y no expone la contraseña en argv.
- Smoke test de `wifi` confirmó `status`, `scan` y `connect`; la contraseña también se entrega por stdin a `nmcli --ask`.
- `diskinfo` se ejecutó y mostró la tarjeta de almacenamiento solicitada.
- La ISO final fue extraída e inspeccionada: no contiene `network.cgi` ni lógica `dexsta0`; sí contiene campos SSID/contraseña, servicio diferido, `wifi`, `diskinfo` y botón de reinicio.
