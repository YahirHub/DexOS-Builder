# Mostrar el dashboard sólo en shells interactivos con terminal.
if [ -t 1 ] && [ -z "${DEXOS_DISKINFO_SHOWN:-}" ] && command -v diskinfo >/dev/null 2>&1; then
    export DEXOS_DISKINFO_SHOWN=1
    diskinfo || true
fi
