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
