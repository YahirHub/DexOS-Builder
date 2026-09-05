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
