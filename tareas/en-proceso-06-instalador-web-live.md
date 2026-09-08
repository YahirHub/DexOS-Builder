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
- [ ] Validar con la tarjeta Wi-Fi/USB física del equipo del usuario.
- [ ] Ejecutar y validar de extremo a extremo una instalación completa iniciada desde el POST CGI del navegador y primer boot del sistema resultante.
- [ ] Cerrar tarea y crear commit final en español una vez pasen las dos validaciones anteriores.

## ISO actual para prueba física
- `/workspace/yah-alpine/out/DexOS-Server-edge-x86_64.iso`
- `740294656` bytes (~706 MiB)
- SHA-256: `91db6e9aa83a2c2e3abfc959bdaec8845a875815d6fe2c4b4276a11deb27ea3d`
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
