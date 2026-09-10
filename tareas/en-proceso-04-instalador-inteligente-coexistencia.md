# Tarea
Igualar la inteligencia de particionado/arranque del instalador DexOS Desktop con DexOS Server.

# Objetivo
Permitir instalación segura en disco completo o coexistencia con Windows/Linux, reutilizando ESP sin formatearla, aceptando particiones raíz existentes o espacio no asignado, soportando GPT/MBR y BIOS/UEFI, y evitando tocar particiones no seleccionadas.

# Criterios de aceptación
- [ ] Inventario robusto de discos, particiones sin formato y espacio no asignado.
- [ ] Coexistencia disponible con Windows o Linux, no sólo Windows.
- [ ] En coexistencia se puede elegir una partición existente elegible o un hueco no asignado.
- [ ] La raíz elegida se valida de nuevo justo antes de modificarla.
- [ ] La ESP se reutiliza sin formatear y sólo es obligatoria cuando el Live arrancó en UEFI.
- [ ] BIOS se permite sólo cuando la tabla/disco ofrece destino válido.
- [ ] Creación de raíz en hueco libre funciona en GPT y MBR sin alterar otras particiones.
- [ ] GRUB conserva otros cargadores, usa UUID estable y ejecuta os-prober.
- [ ] Instalación completa mantiene esquema BIOS+UEFI.
- [ ] GUI explica exactamente qué se conservará/formateará.
- [ ] Pruebas automáticas cubren elegibilidad, huecos libres, BIOS/UEFI y no-formateo de ESP.
- [ ] Build/ISO y validación QEMU posterior.

## Extensión v010 — UX y mantenimiento de arranque

- [x] Corregir iconos de «Todas las aplicaciones», «Configuración» e «Internet» en Whisker.
- [x] Añadir puntero tipo Windows y aplicarlo en LightDM/XFCE.
- [x] Añadir perfil de energía equilibrado para reducir carga/temperatura en reposo.
- [x] Eliminar diagnósticos gráficos costosos de cada inicio y limitar `apk update` periódico.
- [x] Añadir protección de vista/luz cálida con GUI y persistencia.
- [x] Convertir el cambio de orden de GRUB en aplicación gráfica de escritorio.
- [x] Añadir botón de escaneo de discos que regenere GRUB y añada otros sistemas detectados.
- [x] Integrar las herramientas en Live y sistema instalado.
- [x] Generar y verificar ISO v010.
- [ ] Validar visualmente v010 en una sesión Live y después de instalación real/virtual.

## Extensión v012 — GeoClue2 y experiencia de credenciales

- [x] Incluir GeoClue2 completo en Live y sistema instalado.
- [x] Permitir Redshift automático por ubicación/amanecer-atardecer.
- [x] Permitir que el usuario active inicio automático de protección de vista.
- [x] Checkbox marcado por defecto para usar la misma contraseña en usuario y root.
- [x] Permitir mayúsculas en nombre de usuario y normalizar a minúsculas antes de instalar.
- [x] Validar cambios e ISO v012.

## Extensión v013 — persistencia de estado y permisos del gestor GRUB

- [x] Eliminar el reset de volumen PipeWire a 100% en cada login.
- [x] Habilitar persistencia ALSA mediante servicio OpenRC `alsa`.
- [x] Guardar/restaurar brillo de hardware durante reinicio/apagado.
- [x] Hacer que el gestor de orden de arranque solicite autenticación administrativa antes de abrir.
- [x] Añadir política PolicyKit gráfica para `dexos-boot-manager`.
- [x] Corregir lectura vacía de GRUB causada por permisos de `/boot/grub/grub.cfg`.
- [x] Compilar y verificar ISO v013.
- [ ] Validar visualmente el diálogo PolicyKit y la persistencia volumen/brillo tras una instalación v013 completa.

## Extensión v014 — brillo y Redshift offline

- [x] Encontrar la causa exacta de que el brillo guardado no se restaurara.
- [x] Corregir la validación POSIX que descartaba todos los valores de backlight.
- [x] Esperar drivers de backlight tardíos antes de restaurar.
- [x] Mantener Redshift funcional sin Internet mediante horario local.
- [x] Volver automáticamente a GeoClue2 cuando haya conectividad.
- [x] Generar y verificar ISO v014.
- [ ] Confirmar en hardware real que el brillo persiste después de reiniciar v014.
