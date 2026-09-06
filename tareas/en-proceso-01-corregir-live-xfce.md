# Tarea
Corregir la sesión Live XFCE congelada.
# Criterios de aceptación
- Sólo eudev como devd.
- LightDM + usuario live normal.
- Mouse/teclado interactivos en QEMU.
- XFCE responde a hover/clic.

## Mejora de arranque 2026-09-05
- [x] Detectar que el Live instala 570 paquetes (~822 MiB) en RAM antes de OpenRC.
- [x] Diseñar splash temprano usando fbsplash nativo de Alpine.
- [x] Alimentar progreso real desde apk-tools `--progress-fd`.
- [x] Agregar ESC para alternar splash/detalles.
- [x] Agregar readiness gate antes de mostrar XFCE.
- [ ] Recompilar initramfs/ISO con el nuevo flujo.
- [ ] Validar splash, ESC y escritorio interactivo en QEMU.

## DexOS 2026-09-05
- [x] Corregir repintado completo al volver de logs con ESC.
- [x] Sustituir transición negra por fondo X11 rojo mate inmediato.
- [x] Esperar componentes reales de XFCE antes de marcar escritorio listo.
- [x] Corregir lanzador/privilegios del instalador.
- [x] Renombrar branding visible a DexOS y usuario Live a `dexos`.
- [x] Añadir pruebas de regresión para branding, transición, instalador y splash.
- [ ] Recompilar ISO DexOS.
- [ ] Probar ESC ida/vuelta, transición sin negro, interacción XFCE e instalador en QEMU.

## Corrección posterior a prueba runtime
- [x] Diagnosticar `lightdm failed to start` como fallo provocado por timeout síncrono de 20 s.
- [x] Desacoplar monitor de readiness de XFCE del estado OpenRC de LightDM.
- [x] Extender monitor a 180 s sin marcar servicio fallido por lentitud.
- [x] Simplificar instalador con `Terminal=true` y elevación directa del comando autorizado.
- [x] Cambiar identidad tty/os-release a DexOS y branding del menú de arranque.
- [x] Actualizar pruebas de regresión.
- [ ] Recompilar ISO y recrear VM.
- [ ] Validar escritorio e instalador en runtime.

## Ajuste visual por salida real
- [x] Detectar que XFCE usa propiedades de fondo por nombre real de monitor.
- [x] Aplicar wallpaper/tema DexOS dinámicamente a todas las salidas detectadas.
- [x] Añadir prueba estática del autostart de branding.
- [x] Optimizar invalidación de cache para evitar recompilar kernel cuando el parche de initramfs no cambia.
- [ ] Recompilar ISO final y recrear VM.
- [ ] Validar visualmente fondo rojo e instalador en la ISO final.

## Instalador gráfico propio 2026-09-05
- [x] Eliminar dependencia funcional de setup-alpine para instalar.
- [x] Crear asistente GTK3 de disco, timezone, usuario, resumen y progreso.
- [x] Crear backend root validado con comunicación JSON.
- [x] Validar y excluir medios/discos montados.
- [x] Crear esquema GPT BIOS+UEFI y ext4.
- [x] Instalar sistema offline desde la propia ISO con apk --root.
- [x] Configurar timezone directamente, usuario, doas, OpenRC, NetworkManager, XFCE y branding.
- [x] Instalar GRUB BIOS + UEFI con fallback.
- [x] Añadir pruebas de seguridad y esquema GPT.
- [ ] Recompilar ISO con python3 + py3-gobject3.
- [ ] Validar que la GUI abre en el Live.
- [ ] Realizar instalación completa en disco virtual y arrancar desde ese disco.

## Arranque del sistema instalado 2026-09-05
- [x] Reproducir fallo de initramfs con `/dev/vda3` ausente.
- [x] Forzar módulos VirtIO + ext4 en initramfs instalado.
- [x] Forzar root por UUID en GRUB.
- [x] Añadir prueba de regresión de `grub.cfg`.
- [ ] Reempaquetar ISO con backend corregido.
- [ ] Reinstalar en disco virtual limpio.
- [ ] Arrancar sin ISO y confirmar login/LightDM/XFCE.

## Wi-Fi y wallpaper 2026-09-06
- [x] Añadir re-sondeo y desbloqueo Wi-Fi antes de NetworkManager.
- [x] Incluir herramientas y firmware para Wi-Fi real.
- [x] Integrar el wallpaper exacto proporcionado por el usuario.
- [x] Verificar hash idéntico del wallpaper dentro de la ISO.
- [x] Recompilar ISO con correcciones.
- [ ] Probar en hardware físico que aparece la interfaz Wi-Fi.
