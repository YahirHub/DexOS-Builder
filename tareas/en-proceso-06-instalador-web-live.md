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
- [x] Diagnosticar la carrera del primer arranque: la radio aparecía antes de que el SSID estuviera disponible en el scan de NetworkManager.
- [x] Añadir dependencias explícitas `dbus` + `wpa_supplicant` + `networkmanager`, scan dirigido, `hidden yes`, tres intentos y log de diagnóstico.
- [x] La validación física del servicio diferido mostró que seguía fallando; ese enfoque fue sustituido por perfil persistente y luego por activación explícita OpenRC.

## ISO actual para prueba física
- `/workspace/yah-alpine/out/DexOS-Server-edge-x86_64.iso`
- `741343232` bytes (~707 MiB)
- SHA-256: `6d52cf729c39b4c6f3ff3df1b517defac168e8be48e4a7216da61aba21ce5f95`
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


### Diagnóstico Wi-Fi primer arranque
- El fallo físico reportado coincide con una carrera de escaneo, no con una ausencia total de la tarjeta: el servicio ya había detectado una interfaz Wi-Fi pero intentaba conectar una sola vez demasiado pronto.
- Reproducción `mac80211_hwsim`: sin scan actualizado, `nmcli` devolvió `No network with SSID ... found`; después de un scan dirigido, el mismo comando de conexión funcionó.
- Nuevo servicio: espera 30 s por dispositivo, fuerza scan del SSID, prueba hasta tres veces, usa `hidden yes` y deja `/var/log/dexos-wifi-firstboot.log`.
- ISO corregida SHA-256: `6d52cf729c39b4c6f3ff3df1b517defac168e8be48e4a7216da61aba21ce5f95`.

### Revisión 2026-09-09: NetworkManager persistente + ext4 obligatorio
- [x] Retirar `dexos-wifi-firstboot` tras persistir el fallo físico con tres retries.
- [x] Crear directamente un perfil NetworkManager `dexos-wifi.nmconnection` modo 600, autoconnect y WPA-PSK.
- [x] Mantener `wpa_supplicant` como dependencia/servicio de NetworkManager.
- [x] Hacer obligatorio ext4: comprobar `blkid` inmediatamente después de `mkfs.ext4` y `findmnt` después de montar la raíz.
- [x] E2E QEMU en disco nuevo confirmó `/dev/vda3 TYPE=ext4`, perfil Wi-Fi persistente y ausencia del antiguo firstboot.
- [x] La prueba física del perfil NetworkManager silencioso confirmó que no se activaba de forma fiable; se sustituyó por un servicio visible que fuerza `connection up` y deja diagnóstico.
- ISO SHA-256: `0fbdb5a5101ee2bbd8200359f1e2046652e68e5c53751840f50c239a973db38b`.

### Revisión 2026-09-09 — Wi-Fi visible al boot, GRUB Argon, Bash y TUI
- [x] Hacer que NetworkManager reintente indefinidamente el perfil Wi-Fi persistente y mostrar una activación/diagnóstico explícito durante OpenRC.
- [x] Sustituir el script `wifi` por un binario TUI interactivo compilado y sin dependencias de runtime adicionales.
- [x] Instalar Bash en Live y sistema final; root y el administrador usan `/bin/bash` en el sistema instalado.
- [x] Forzar Argon en GRUB gráfico y ordenar la entrada principal de DexOS antes de `os-prober` y del fallback de otros sistemas.
- [x] Aplicar Argon también al GRUB UEFI del medio Live con la opción `Instalar Alpine Linux` y fallbacks para Windows/otro Linux.
- [x] Recompilar ISO; validar tests estáticos, unit tests Go, TUI real en PTY, helper de autoconexión con `nmcli` simulado, `grub-script-check` y contenido final de la ISO.


### Resultado actual 2026-09-09
- [x] Perfil `DexOS WiFi`: `autoconnect=true`, prioridad 80 y `autoconnect-retries=0` (NetworkManager reintenta indefinidamente).
- [x] `/etc/init.d/dexos-wifi-autoconnect` depende de dbus+wpa_supplicant+NetworkManager; ejecuta `/usr/local/sbin/dexos-wifi-connect`, muestra el SSID/adaptador/resultado durante el arranque y guarda detalle en `/var/log/dexos-wifi-autoconnect.log`.
- [x] El helper fuerza un scan dirigido y `nmcli --wait 35 connection up "DexOS WiFi" ifname <wifi>`. Si falla, deja el motivo y NetworkManager continúa reintentando.
- [x] `wifi` ahora es un binario Go estático (~1.8 MiB) con TUI: flechas, Enter, refrescar, SSID oculto y contraseña sin eco. El parser neutraliza caracteres de control de SSIDs y no pasa contraseñas por argv.
- [x] Bash se incluye en el repositorio offline/Live/target; root y el administrador usan `/bin/bash` tras instalar.
- [x] GRUB instalado usa Argon (`gfxterm`, `1920x1080,auto`) y `/etc/grub.d/09_dexos_linux` coloca `DexOS Server (Alpine Linux)` antes de `30_os-prober`/`31_dexos_other_os`; `10_linux` se deshabilita para no duplicar DexOS.
- [x] GRUB UEFI de la ISO usa el mismo Argon, primera opción `Instalar Alpine Linux`, seguida de fallbacks de Windows y otro Linux cuando GRUB puede encontrarlos.
- [x] Compatibilidad de la entrada principal DexOS con GPT y MBR (`part_gpt` + `part_msdos`).
- [x] El build tolera un fallo DNS transitorio del mirror sólo cuando ya existe un APKINDEX cacheado firmado; paquetes ausentes siguen haciendo fallar el build.
- [x] ISO final: `/workspace/yah-alpine/out/DexOS-Server-edge-x86_64.iso`, `742391808` bytes (~708 MiB), SHA-256 `8549d2e1a9a7e4d99b590a0fd32233d9c76d183db9164f91a95b93ac56bca31c`, APKINDEX 195 paquetes.
- [ ] Validar en el hardware físico del usuario que el servicio muestre el diagnóstico durante boot y que la conexión real se complete; después probar el TUI `wifi` y el GRUB Argon.


### Fix físico 2026-09-09 — perfil no registrado y Argon
- [x] Reproducir/interpretar el fallo real: servicio habilitado + keyfile esperado, pero `nmcli connection show` no publicaba `DexOS WiFi`.
- [x] Validar el keyfile exacto con NetworkManager 1.58.0 (`nmcli connection load` => éxito).
- [x] Hacer que `dexos-wifi-connect` cargue explícitamente `dexos-wifi.nmconnection` cuando `connection reload` no lo registra.
- [x] Añadir mensajes diferenciados para archivo ausente vs keyfile rechazado/no publicado.
- [x] Probar con `nmcli` simulado el caso exacto archivo-existe/perfil-no-registrado y confirmar conexión posterior.
- [x] Añadir `/etc/grub.d/05_dexos_theme` para forzar Argon directamente y localizar la partición del tema mediante `search --file`.
- [x] Recompilar y comprobar que la ISO contiene helper, generador Argon y pruebas actualizadas.
- [ ] Validar en hardware físico que el boot muestre la carga explícita del perfil y que GRUB renderice Argon.
- ISO SHA-256: `142a7694f5acd387d4574ab0e644017da0591978b48aa9ca606ef9897c0df8a1`.
