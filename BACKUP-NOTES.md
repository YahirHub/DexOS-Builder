# DexOS Server — snapshot de desarrollo

Snapshot creado el 2026-09-09 para retomar el desarrollo sin conservar artefactos pesados de compilación.

## Estado fuente

- Commit base del proyecto: `6e436dc9769301fe09b4a5d4f5ea0dad618d8048`
- Alpine aports usado durante el build: `f5ea0a0af34e2185bdd5543786433f5383172f89`
- alpine-conf observado en el entorno de desarrollo: `88e9859f3db4feb0cc8a694152bfc1ded02a6f03`
- Última ISO validada (NO incluida): SHA-256 `116f639489075b29cb2068429ee01a575d754eac4650f0bceb430602598eaeb9`, 713031680 bytes (680 MiB).

## Qué sí contiene

El código fuente actual de `server/`, documentación, contexto de desarrollo, tareas y el árbol fuente auxiliar `project/`. También conserva el historial Git previo para poder continuar desde los commits existentes.

## Qué se excluyó intencionalmente

No se incluyen `out/`, `runtime/`, `cache/`, `alpine-root/`, `aports/`, `alpine-conf/`, `build-home/`, `.venv-vnc/`, logs, imágenes ISO, discos QEMU ni otros resultados descargables/regenerables.

`alpine-root/` es el root/chroot de compilación y se reconstruye siguiendo `docs/TUTORIAL-ISO-ALPINE-PERSONALIZADA-REPRODUCIBLE.md`. `aports/` tampoco se archiva: el tutorial fija el commit exacto y explica cómo clonarlo nuevamente.

## Punto de continuación

La última versión deja Wi-Fi y DNS funcionales en hardware. `dexos-wifi-autoconnect` es un bootstrap de una sola ejecución tras la instalación; los reinicios posteriores quedan a cargo de NetworkManager. El build final usa SquashFS/XZ con bloque de 1 MiB y `tailends`, initramfs XZ y optimización zisofs selectiva.

Antes de continuar, leer `contexto/01-dexos-server-instalador-terminal.md` y `tareas/en-proceso-06-instalador-web-live.md`.
