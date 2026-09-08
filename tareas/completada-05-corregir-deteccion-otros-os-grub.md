# Tarea 05 — Corregir detección de otros sistemas en GRUB

## Estado
completada

## Objetivo
Corregir la ISO DexOS Server para que una instalación en coexistencia detecte otros sistemas operativos y genere entradas GRUB útiles incluso cuando las heurísticas estándar de `os-prober` no son suficientes. Integrar además el tema Argon del DexOS de escritorio solicitado para el menú instalado.

## Criterios completados
- [x] Reproducido el flujo con un segundo Linux arrancable en el mismo disco.
- [x] Confirmada la limitación en la integración `os-prober`/`linux-boot-prober`, no en el núcleo de GRUB.
- [x] Se mantiene `GRUB_DISABLE_OS_PROBER=false`.
- [x] Añadido fallback seguro `/etc/grub.d/31_dexos_other_os`.
- [x] Fallback Linux mediante `configfile` y, como último recurso, kernel/initramfs por UUID.
- [x] Detección adicional de cargadores EFI, incluido Windows Boot Manager.
- [x] Inspección de particiones ajenas en solo lectura y ext con `ro,noload`.
- [x] No se formatean ni alteran otras raíces ni la ESP en modo coexistencia.
- [x] Añadidos `grub-update` y alias `update-grub` con generación temporal y `grub-script-check`.
- [x] Añadidas pruebas estáticas de detección, actualización y tema.
- [x] Probado en QEMU/KVM con otro Linux y ESP compartida.
- [x] Portado el tema Argon original del DexOS gráfico, con sus 92 archivos y licencia.
- [x] Verificado `Found theme` y `set theme` en el GRUB generado.
- [x] Recompilada e inspeccionada la ISO final.
- [x] Actualizado `contexto/01-dexos-server-instalador-terminal.md`.

## ISO final
- `/workspace/yah-alpine/out/DexOS-Server-edge-x86_64.iso`
- 497025024 bytes
- SHA-256: `2decb0ed6b5da72bf26dd8fd62f95e71bf82408b65048d8684f22926509bf473`
