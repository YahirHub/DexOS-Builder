# Tutorial reproducible: crear una ISO personalizada de Alpine Linux

> **Objetivo:** documento autocontenido para que una persona o un LLM pueda reconstruir, modificar, probar y mantener una ISO personalizada de Alpine Linux usando el mismo método empleado para **DexOS Server**.
>
> Este documento no se limita a "ejecutar mkimage". Explica el entorno de compilación, qué se congela, qué NO se congela, el perfil de `mkimage`, el `apkovl`, el repositorio offline, el instalador propio, BIOS/UEFI, QEMU, NetworkManager, Avahi, SSH, pruebas y los errores reales encontrados durante el desarrollo.

---

## 1. Resultado de referencia que este tutorial documenta

La compilación de referencia produjo:

- ISO: `DexOS-Server-edge-x86_64.iso`
- Arquitectura: `x86_64`
- Base: Alpine edge
- Kernel: `linux-lts`
- Tamaño final observado: `497025024` bytes (~474 MiB)
- SHA-256 de la ISO validada: `aab605a18285d3dccb9d421917b88154477dd599427401705930dc0752a58c1a`
- APK incluidos en el repositorio offline de la ISO: **176**
- Arranque: BIOS mediante Syslinux + UEFI mediante GRUB EFI
- Instalación: completamente offline desde los APK incluidos en la propia ISO
- Red instalada: NetworkManager + eudev, Ethernet DHCP automático y Wi-Fi mediante `nmcli`
- Servicios: OpenSSH, Avahi/mDNS, dbus, NetworkManager
- Dual boot: `os-prober`, NTFS y GRUB
- Herramienta interactiva para cambiar arranque predeterminado: `boot-order`

La ISO fue probada de extremo a extremo:

1. arranque Live sin NIC;
2. instalación offline en QCOW2 vacío;
3. reinicio sin ISO;
4. activación posterior de NIC VirtIO/NAT;
5. DHCP/DNS automáticos;
6. `apk update` exitoso;
7. SSH real al sistema instalado;
8. Avahi anunciando `<hostname>.local`;
9. GRUB usando el UUID real de la raíz.

---

## 2. Regla más importante: fijar versiones no es lo mismo que fijar una rama

Si quieres que cambios futuros de Alpine no rompan el método, **NO uses solamente `master`, `edge` o `latest` como referencia de reproducibilidad**.

Para esta compilación se usó exactamente:

### Alpine aports

- Repositorio: `https://gitlab.alpinelinux.org/alpine/aports.git`
- Rama que estaba activa: `master`
- **Commit exacto:** `f5ea0a0af34e2185bdd5543786433f5383172f89`
- Fecha del commit: `2026-09-05T23:14:58-04:00`
- Asunto: `community/dotnet10-sdk: upgrade to 10.0.303`

El checkout local quedó `dirty` porque el script de build aplica deliberadamente pequeños parches a `scripts/mkimage.sh` y `scripts/mkimg.base.sh`. Los parches exactos están incluidos más adelante.

### Alpine minirootfs usado como raíz de build

- Archivo: `alpine-minirootfs-20260805-x86_64.tar.gz`
- URL usada: `https://dl-cdn.alpinelinux.org/alpine/edge/releases/x86_64/alpine-minirootfs-20260805-x86_64.tar.gz`
- SHA-256: `5acac12c425a0817c1b6a79bdd5df4c73756fc8dc268eab32f8ba830872b835d`
- `/etc/alpine-release` del root de build: `3.25.0_alpha20260805`
- `apk-tools` inicial observado en ese root: `3.0.7-r0`

### Proyecto DexOS Server

El repositorio local del proyecto estaba en:

- rama: `main`
- commit de referencia después de la corrección de red/DNS: `9c8fb90405aad191c1e6e43f2d516b004eba377f`
- commit corto: `9c8fb90`
- mensaje: `Corregir DHCP y DNS de NetworkManager`

**Importante:** este repositorio local no tiene un `remote` configurado. Por tanto, ese hash sirve como referencia histórica dentro de la copia del proyecto, pero **no es recuperable desde Internet por sí solo**. Para preservarlo debes guardar el repositorio, crear un `git bundle` o archivar estos archivos personalizados.

---

## 3. Reproducibilidad funcional vs. reproducibilidad bit a bit

Hay dos niveles distintos:

### Nivel A: reproducibilidad funcional

Fijas:

- minirootfs por nombre + SHA-256;
- aports por commit exacto;
- scripts personalizados por SHA-256;
- lista de paquetes;
- perfil `mkimage`;
- parches exactos.

Pero sigues usando:

```text
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
```

Esos repositorios **son mutables**. Mañana una versión de un APK puede cambiar aunque tu commit de aports siga fijo. El sistema debería construirse de la misma forma conceptual, pero no necesariamente producirá el mismo SHA-256 de ISO.

### Nivel B: reproducibilidad bit a bit

Además de lo anterior debes conservar:

1. todos los `.apk` exactos usados;
2. su `APKINDEX.tar.gz`;
3. la clave `abuild` usada para firmar el repositorio si quieres reproducir firmas idénticas;
4. el minirootfs exacto;
5. la versión de herramientas del host (`xorrisofs`, `proot`, etc.);
6. idealmente el árbol `cache/` de la compilación exitosa o un mirror local inmutable.

Para esta ISO, el manifiesto de versiones exactas de los 176 APK está incluido en el apéndice.

**Recomendación práctica:** guarda siempre la ISO final validada, el proyecto Git, la clave de build y un mirror de APK. No dependas de que `edge` siga igual.

---

## 4. Entorno host de referencia

El build se realizó en:

- Debian GNU/Linux 13 (trixie), versión observada 13.6
- `x86_64`
- QEMU 10.0.11
- PRoot 5.1.0
- xorriso/xorrisofs 1.5.6

No es obligatorio usar Debian 13, pero este tutorial asume Debian/Ubuntu para los comandos del host.

### Dependencias del host

```bash
sudo apt update
sudo apt install -y   git curl ca-certificates   proot xorriso openssl python3   coreutils tar gzip xz-utils   qemu-system-x86 qemu-utils
```

Comandos realmente requeridos por el script de build principal:

```text
proot
xorrisofs
openssl
sha256sum
python3
```

QEMU es opcional para compilar, pero **obligatorio si quieres validar correctamente la ISO**.

Comprueba:

```bash
command -v proot xorrisofs openssl sha256sum python3
command -v qemu-system-x86_64 qemu-img
```

---

## 5. Estructura recomendada del proyecto

La estructura usada es conceptualmente esta:

```text
yah-alpine/
├── alpine-root/                 # minirootfs Alpine; NO se versiona
├── aports/                      # checkout exacto de Alpine aports
├── build-home/                  # clave abuild; sensible
├── cache/                       # secciones y APK descargados; no Git
├── out/                         # ISO final
├── runtime/                     # QCOW2, logs y VMs de prueba
├── server/
│   ├── build-dexos-server.sh
│   ├── install
│   ├── boot-order
│   ├── packages.txt
│   ├── live-world.txt
│   ├── mkimage/
│   │   ├── mkimg.dexserver.sh
│   │   └── genapkovl-dexserver.sh
│   └── tests/
│       └── test-server.sh
└── docs/
    └── TUTORIAL-ISO-ALPINE-PERSONALIZADA-REPRODUCIBLE.md
```

Una `.gitignore` razonable:

```gitignore
alpine-root/
aports/
cache/
out/
runtime/
build-home/
*.log
*.pid
*.qcow2
*.iso
__pycache__/
*.pyc
```

No ignores tus fuentes bajo `server/`.

---

## 6. Bootstrap exacto del root Alpine con PRoot

Desde la raíz del proyecto:

```bash
set -euo pipefail

MINI='alpine-minirootfs-20260805-x86_64.tar.gz'
MINI_URL='https://dl-cdn.alpinelinux.org/alpine/edge/releases/x86_64/alpine-minirootfs-20260805-x86_64.tar.gz'
MINI_SHA='5acac12c425a0817c1b6a79bdd5df4c73756fc8dc268eab32f8ba830872b835d'

curl -fL "$MINI_URL" -o "$MINI"
echo "$MINI_SHA  $MINI" | sha256sum -c -

rm -rf alpine-root
mkdir -p alpine-root
sudo tar -xzf "$MINI" -C alpine-root
```

Si trabajas como usuario sin `sudo`, normalmente puedes extraerlo igualmente y usar `proot -0`, pero conservar owners/permisos de forma correcta es preferible.

Configura los repositorios del root de build:

```bash
cat > alpine-root/etc/apk/repositories <<'EOF'
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
EOF
```

Da DNS al root de build:

```bash
cp -L /etc/resolv.conf alpine-root/etc/resolv.conf
```

Actualiza e instala las herramientas de construcción dentro del root Alpine:

```bash
proot -0 -R "$PWD/alpine-root" /sbin/apk update
proot -0 -R "$PWD/alpine-root" /sbin/apk add   alpine-base alpine-baselayout alpine-conf alpine-keys alpine-release   apk-tools alpine-sdk abuild musl-utils   dosfstools grub grub-efi mtools squashfs-tools syslinux xorriso
```

El `/etc/apk/world` observado en el root de build de referencia fue:

```text
abuild
alpine-base
alpine-baselayout
alpine-conf
alpine-keys
alpine-release
alpine-sdk
apk-tools
busybox
dosfstools
grub
grub-efi
mtools
musl-utils
squashfs-tools
syslinux
xorriso
```

Verifica:

```bash
proot -0 -R alpine-root /bin/cat /etc/alpine-release
proot -0 -R alpine-root /sbin/apk --version
```

Esperado para el root original:

```text
3.25.0_alpha20260805
apk-tools 3.0.7-r0, compiled for x86_64
```

No te sorprendas si un `apk upgrade` posterior cambia `apk-tools`: para reproducibilidad estricta, no actualices arbitrariamente.

---

## 7. Clonar `aports` en el commit exacto

```bash
git clone https://gitlab.alpinelinux.org/alpine/aports.git aports
git -C aports fetch --all --tags
git -C aports checkout --detach f5ea0a0af34e2185bdd5543786433f5383172f89
```

Comprueba:

```bash
git -C aports rev-parse HEAD
```

Debe imprimir exactamente:

```text
f5ea0a0af34e2185bdd5543786433f5383172f89
```

**No hagas `git pull`** mientras intentas reproducir esta versión.

Si quieres trabajar en una rama local sin mover la referencia:

```bash
git -C aports switch -c dexos-pinned-f5ea0a0a
```

---

## 8. Qué hace `mkimage` y por qué hay tres listas diferentes

Este punto evita muchos errores conceptuales.

### `apks=` del perfil

Define paquetes que `mkimage` debe tener disponibles en el repositorio de la ISO y usa para construir secciones de kernel/boot/modloop.

**Que un APK esté en `apks=` NO significa que esté instalado en el Live.**

### `/etc/apk/world` dentro del `apkovl`

Define qué paquetes se instalan en el root Live cuando Alpine monta/aplica la ISO.

Por eso existe `server/live-world.txt`.

### `server/packages.txt`

Es la lista que el instalador propio usa para instalar el sistema en disco mediante:

```bash
apk add --root ... --no-network --repository <repo-local>
```

Esto permite que el Live sea razonablemente pequeño y que la instalación funcione **sin Internet**.

---

## 9. Perfil personalizado de `mkimage`

El perfil se llama `dexserver`. Se deriva de `profile_standard` y cambia nombre, kernel, firmware y paquetes.

Puntos relevantes:

- kernel `lts`;
- firmware Wi-Fi selectivo, no el meta-paquete completo `linux-firmware`;
- microcode AMD e Intel;
- Syslinux para BIOS;
- GRUB EFI para UEFI;
- NetworkManager, eudev, SSH, Avahi y herramientas del instalador;
- `os-prober` y NTFS para coexistencia.

El fuente exacto está incluido en el apéndice.

---

## 10. `apkovl`: personalizar el Live correctamente

`apkovl` es el mecanismo Alpine que aplica archivos/configuraciones sobre el Live.

En este proyecto se usa para:

- `/etc/hostname`, `/etc/hosts`;
- repositorios APK online;
- NetworkManager;
- Ethernet DHCP automático;
- DNS fallback;
- `/etc/apk/world`;
- branding;
- SSH;
- Avahi;
- runlevels OpenRC;
- copiar `install` y `boot-order`.

### Error crítico 1: no escribas el `.apkovl.tar.gz` dentro del directorio temporal

El generador crea:

```sh
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
```

Si haces:

```sh
output="$tmp/dexos-server.apkovl.tar.gz"
```

el `trap` lo elimina y la ISO termina arrancando como Alpine genérico.

La forma correcta en este flujo es:

```sh
tar -c -C "$tmp" . | gzip -9n > "$HOSTNAME.apkovl.tar.gz"
```

porque `mkimage` ejecuta el script desde el destino de la sección.

### Error crítico 2: `mktemp -d` crea 0700

El tar incluye el propio `.`. Si no haces:

```sh
chmod 0755 "$tmp"
```

el modo 0700 puede propagarse a `/` del Live. Resultado observado: Avahi y otros daemons no-root no podían atravesar `/` y fallaban con `Permission denied`.

### No hornees host keys SSH

El overlay elimina:

```sh
rm -f "$tmp"/etc/ssh/ssh_host_*
```

Las claves deben ser únicas por máquina/arranque, no idénticas en todas las copias de la ISO.

---

## 11. NetworkManager: por qué se usa eudev y no `mdev`

Este fue uno de los bugs más importantes.

Con BusyBox `mdev`, NetworkManager 1.58 mostraba la interfaz VirtIO como:

```text
unmanaged
reason 71: The device is unmanaged because the link is not initialized by udev
```

Resultado:

- no DHCP;
- no `/etc/resolv.conf` útil;
- `apk update` fallaba con DNS aunque los repositorios estuvieran bien escritos.

La solución correcta fue incluir y arrancar:

```text
eudev
eudev-openrc
udev
udev-trigger
udev-settle
udev-postmount
```

Runlevel `sysinit`:

```text
devfs
dmesg
udev
udev-trigger
udev-settle
hwdrivers
modloop
```

Runlevel `default`:

```text
dbus
networkmanager
sshd
avahi-daemon
udev-postmount
```

NetworkManager usa:

```ini
[main]
plugins=keyfile
rc-manager=file
dns=default

[ifupdown]
managed=true
```

Y un perfil Ethernet universal:

```ini
[connection]
id=DexOS Wired
type=ethernet
autoconnect=true
autoconnect-priority=100

[ipv4]
method=auto

[ipv6]
method=auto
```

En la prueba QEMU posterior, sin ningún `udhcpc` manual:

```text
eth0       connected   DexOS Wired
IPv4       10.0.2.15/24
Gateway    10.0.2.2
DNS        10.0.2.3
apk update -> exit 0
```

---

## 12. DNS: fallback vs DNS real de DHCP

El Live y el instalado llevan inicialmente:

```text
nameserver 1.1.1.1
nameserver 8.8.8.8
```

Pero con `rc-manager=file` + `dns=default`, NetworkManager reemplaza el contenido cuando una conexión DHCP/Wi-Fi entrega DNS.

En QEMU NAT terminó siendo:

```text
# Generated by NetworkManager
nameserver 10.0.2.3
```

El fallback evita que un fallo temprano deje el sistema sin ninguna posibilidad de resolver nombres, pero **la fuente primaria debe ser NetworkManager**.

---

## 13. Firmware: evitar que una ISO Server crezca innecesariamente

El perfil estándar de Alpine puede arrastrar `linux-firmware` completo.

Para esta ISO se parcheó `mkimg.base.sh` para permitir:

```sh
kernel_firmware_packages="..."
```

La lista seleccionada cubre principalmente Wi-Fi:

```text
linux-firmware-realtek
linux-firmware-rtlwifi
linux-firmware-rtw88
linux-firmware-rtw89
linux-firmware-mediatek
linux-firmware-ath6k
linux-firmware-ath9k_htc
linux-firmware-ath10k
linux-firmware-ath11k
linux-firmware-ath12k
linux-firmware-brcm
linux-firmware-cypress
linux-firmware-qca
linux-firmware-mwl8k
linux-firmware-mwlwifi
linux-firmware-libertas
linux-firmware-ti-connectivity
linux-firmware-rsi
linux-firmware-wfx
```

Además se modifica temporalmente `alpine-root/usr/sbin/update-kernel` para que no vuelva a insertar `linux-firmware` completo.

Esto es deliberado: si tu hardware requiere firmware GPU/RAID/NIC específico, añádelo explícitamente.

---

## 14. Parches exactos aplicados a aports

Partiendo del commit `f5ea0a0af34e2185bdd5543786433f5383172f89`, el build deja este diff:

```diff
diff --git a/scripts/mkimage.sh b/scripts/mkimage.sh
index c31a1d85..65075527 100755
--- a/scripts/mkimage.sh
+++ b/scripts/mkimage.sh
@@ -118,6 +118,7 @@ build_section() {
     local section="$1"
     local args="$@"
     local _dir="${args//[^a-zA-Z0-9]/_}"
+    if [ ${#_dir} -gt 180 ]; then _dir="${section}_$(printf %s "$args" | sha1sum | cut -c1-40)"; fi
     shift
     local args="$@"

@@ -172,7 +173,7 @@ build_profile() {
             mkdir -p "$DESTDIR"
             for _dir in $_my_sections; do
                 for _fn in $WORKDIR/$_dir/*; do
-                    [ ! -e "$_fn" ] || cp -Lrs $_fn $DESTDIR/
+                    [ ! -e "$_fn" ] || cp -Lr $_fn $DESTDIR/
                 done
             done
             echo "${image_name}-${RELEASE} ${build_date}" > "$DESTDIR"/.alpine-release
diff --git a/scripts/mkimg.base.sh b/scripts/mkimg.base.sh
index 41797d7d..a742dd35 100644
--- a/scripts/mkimg.base.sh
+++ b/scripts/mkimg.base.sh
@@ -30,7 +30,7 @@ build_kernel() {
 section_kernels() {
     local _f _a _pkgs
     for _f in $kernel_flavors; do
-        _pkgs="linux-$_f linux-firmware wireless-regdb $modloop_addons"
+        _pkgs="linux-$_f ${kernel_firmware_packages:-linux-firmware} wireless-regdb $modloop_addons"
         for _a in $kernel_addons; do
             _pkgs="$_pkgs $_a-$_f"
         done
@@ -284,6 +284,8 @@ create_image_iso() {
         fi
     fi

+    [ "${YAH_SKIP_XORRISO:-}" = "1" ] && return 0
+
     if [ "$ARCH" = ppc64le ]; then
         apk fetch --root "$APKROOT" --quiet --stdout grub-ieee1275 | tar -C "$WORKDIR" -zx usr/lib/grub
         grub-mkrescue --output ${ISO} ${DESTDIR} -follow-links \
```

### Qué resuelve cada parche

1. **`kernel_firmware_packages`**: sustituir el meta `linux-firmware` por una lista controlada.
2. **`YAH_SKIP_XORRISO`**: `mkimage` construye el árbol, pero el ISO final se ensambla fuera de PRoot; esto evitó problemas de xorriso siguiendo el árbol generado bajo PRoot.
3. **paths de cache demasiado largos**: si el nombre de sección supera 180 caracteres se reemplaza por un SHA-1 corto.
4. **`cp -Lrs` → `cp -Lr`**: evita problemas con árboles llenos de symlinks relativos durante el ensamblado bajo PRoot.

El script también parchea `alpine-root/usr/sbin/update-kernel`:

```python
old = 'PACKAGES="$PACKAGES linux-$FLAVOR linux-firmware"'
new = 'PACKAGES="$PACKAGES linux-$FLAVOR"'
```

Ese cambio es en el root de build, no en el Git de aports.

---

## 15. Clave de abuild

El build crea una clave local si no existe:

```bash
openssl genrsa -out build-home/.config/abuild/dexos-server.rsa 3072
openssl rsa   -in build-home/.config/abuild/dexos-server.rsa   -pubout   -out build-home/.config/abuild/dexos-server.rsa.pub
```

La clave pública se copia a:

```text
alpine-root/etc/apk/keys/dexos-server.rsa.pub
```

### Seguridad

- La **privada no se versiona**.
- Si distribuyes la ISO/repo, protege esa clave.
- Si deseas ISO bit-a-bit idéntica, debes conservar la misma clave; regenerarla cambiará firmas y probablemente el hash final.

---

## 16. Build: flujo exacto

El script hace, en orden:

1. verifica host tools;
2. genera/carga clave abuild;
3. copia perfil y generador apkovl a `aports/scripts/`;
4. parchea aports de forma idempotente;
5. parchea `update-kernel`;
6. limpia secciones de cache afectadas;
7. ejecuta `mkimage.sh` dentro de PRoot;
8. `mkimage` genera el árbol BIOS/UEFI y repo APK;
9. se salta xorriso dentro de PRoot;
10. el host usa `xorrisofs` sobre el árbol final;
11. genera SHA-256.

Invocación central:

```bash
proot -i 1000:1000   -R "$ALPINE_ROOT"   -b "$ROOT:/work"   -w /work/server/mkimage   /usr/bin/env     HOME=/work/build-home     PACKAGER_PRIVKEY=/work/build-home/.config/abuild/dexos-server.rsa     PACKAGER_PUBKEY=/work/build-home/.config/abuild/dexos-server.rsa.pub     YAH_SKIP_XORRISO=1     /bin/sh /work/aports/scripts/mkimage.sh       --tag edge       --outdir /work/out       --workdir /work/cache       --arch x86_64       --profile dexserver       --repository https://dl-cdn.alpinelinux.org/alpine/edge/main       --repository https://dl-cdn.alpinelinux.org/alpine/edge/community
```

Ensambla el ISO híbrido:

```bash
xorrisofs   -output out/DexOS-Server-edge-x86_64.iso   -full-iso9660-filenames -joliet -rational-rock   -sysid LINUX -volid DEXOS_SERVER   -isohybrid-mbr "$IMG/boot/syslinux/isohdpfx.bin"   -eltorito-boot boot/syslinux/isolinux.bin   -eltorito-catalog boot/syslinux/boot.cat   -no-emul-boot -boot-load-size 4 -boot-info-table   -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot   -isohybrid-gpt-basdat -follow-links "$IMG"
```

Después:

```bash
sha256sum out/DexOS-Server-edge-x86_64.iso   > out/DexOS-Server-edge-x86_64.iso.sha256
```

Para construir en este proyecto:

```bash
./server/tests/test-server.sh
./server/build-dexos-server.sh
```

---

## 17. Por qué se usa un instalador propio y no `setup-alpine`

`setup-alpine` es excelente para una instalación Alpine genérica, pero aquí se necesitaba:

- instalación offline garantizada;
- repo reducido incluido en ISO;
- control total de paquetes;
- NetworkManager y perfiles Wi-Fi;
- Avahi/mDNS;
- GRUB BIOS/UEFI;
- coexistencia con otro SO;
- root UUID verificado;
- UX de Server personalizada.

El comando Live es simplemente:

```text
install
```

El PATH antepone `/usr/local/sbin` para que ese comando sea el asistente DexOS. Si recibe argumentos que no son los suyos, delega a `/usr/bin/install`, evitando romper scripts Unix que esperen el `install(1)` estándar.

Modos:

```text
install
install --wifi
install --check
install --help
```

---

## 18. Preflight offline correcto

### Error real encontrado

Se intentó validar paquetes con:

```bash
apk fetch --simulate ...
```

Pero `apk fetch --simulate` puede imprimir error de paquete inexistente y aun así terminar con código 0.

La validación robusta usa:

```bash
apk add --simulate   --no-network   --repositories-file /dev/null   --repository "$repo"   $package_words
```

Si falta cualquier dependencia, debe fallar **antes de tocar el disco**.

### Ruta correcta del repo de la ISO

La raíz del repo debe ser algo como:

```text
/media/cdrom/apks
```

No:

```text
/media/cdrom/apks/x86_64
```

porque `apk` añade la arquitectura y, si le das ya `x86_64`, buscaría `x86_64/x86_64/APKINDEX.tar.gz`.

---

## 19. Modloop, drivers y ext4

El kernel Alpine de la ISO puede compilar ext4 como módulo.

Bug observado:

```text
mount: unknown filesystem type 'ext4'
```

La ISO tenía `ext4.ko` dentro de `boot/modloop-lts`, pero `modloop` no estaba montado porque faltaban servicios del runlevel.

Solución:

```text
sysinit:
  devfs
  dmesg
  udev
  udev-trigger
  udev-settle
  hwdrivers
  modloop
```

Y el instalador, de forma defensiva, ejecuta/verifica `modloop`, `hwdrivers` y `modprobe ext4` antes de tocar almacenamiento.

---

## 20. Race de `/dev/vda3` después de particionar

En QEMU se observó varias veces:

- `sfdisk` actualizaba la tabla;
- `/sys/class/block/vda3` ya existía;
- `/dev/vda3` todavía no estaba creado.

Confiar solo en `sleep` es frágil.

El instalador usa:

```text
blockdev --rereadpt
partx -u / partx -a
mdev -s
```

Y fallback robusto:

1. lee `/sys/class/block/<part>/dev`;
2. extrae major/minor;
3. crea el nodo con `mknod` si falta.

Esta lógica hace la creación de particiones mucho menos dependiente del timing del entorno.

---

## 21. Orden correcto al montar raíz y ESP

Otro bug real:

```sh
mkdir -p "$TARGET" "$TARGET/boot/efi"
mount "$root_part" "$TARGET"
mount "$efi_part" "$TARGET/boot/efi"
```

Es incorrecto porque montar la raíz sobre `$TARGET` oculta el directorio `$TARGET/boot/efi` creado antes.

Correcto:

```sh
mkdir -p "$TARGET"
mount "$root_part" "$TARGET"
mkdir -p "$TARGET/boot/efi"
mount "$efi_part" "$TARGET/boot/efi"
```

---

## 22. Compatibilidad `lsblk` util-linux 2.42

Esta combinación falló en Alpine usado durante las pruebas:

```text
lsblk --list --raw
```

No mezcles `-l` y `-r` si tu util-linux no lo permite.

El instalador terminó usando formatos compatibles como:

```bash
lsblk -npr -o NAME,TYPE,RO "$disk"
```

---

## 23. Selección de disco y modo coexistencia

El medio de instalación se identifica mediante el mount del repo APK y se excluye de la lista de discos destino.

El usuario elige mediante menús numerados:

```text
1) /dev/vda ...
2) /dev/sda ...
```

Modos:

```text
1) disco completo
2) coexistencia con particiones existentes
```

### Disco completo

Crea GPT:

1. 2 MiB BIOS Boot;
2. 512 MiB ESP FAT32;
3. resto ext4 raíz.

Solo requiere confirmación `s/y`; no obliga a escribir una frase tipo `BORRAR /dev/...`.

### Coexistencia

El usuario selecciona:

- disco;
- partición raíz que será formateada;
- ESP existente que será reutilizada **sin formatear**.

La prueba real preservó marcadores colocados en la ESP y en otra partición Linux mientras solo formateaba la raíz seleccionada.

---

## 24. GRUB BIOS + UEFI + otros sistemas

El instalador:

- intenta GRUB BIOS cuando el layout lo permite;
- instala GRUB EFI en `EFI/DexOS`;
- en disco completo crea fallback `EFI/BOOT/BOOTX64.EFI`;
- en coexistencia no pisa deliberadamente el fallback de otro sistema;
- usa `os-prober`;
- incluye `ntfs-3g`;
- habilita `GRUB_DISABLE_OS_PROBER=false`;
- inserta la raíz por UUID;
- verifica que `grub.cfg` contenga el UUID correcto.

Configuración clave:

```text
GRUB_TIMEOUT=5
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=y
GRUB_DISABLE_RECOVERY=true
GRUB_DISABLE_OS_PROBER=false
GRUB_CMDLINE_LINUX="root=UUID=<uuid> rootfstype=ext4"
```

---

## 25. `boot-order`: cambiar el SO predeterminado

Después de instalar se puede ejecutar:

```bash
boot-order
```

La herramienta:

1. lee las entradas top-level de `/boot/grub/grub.cfg`;
2. muestra un menú numerado;
3. lee `saved_entry` actual;
4. llama a `grub-set-default <índice>`.

Esto permite elegir interactivamente DexOS, Windows u otro Linux cuando GRUB los haya detectado.

---

## 26. Avahi y nombre `.local`

El asistente acepta:

```text
servidor
```

o:

```text
servidor.local
```

Internamente elimina un `.local` final si ya existe y guarda:

```text
hostname = servidor
mDNS     = servidor.local
```

Así nunca genera `servidor.local.local`.

Avahi se instala y habilita automáticamente.

---

## 27. Contraseñas y root SSH

El asistente pide:

1. usuario administrador;
2. contraseña de ese usuario;
3. contraseña root.

Si en la contraseña root se pulsa solo Enter, reutiliza la del administrador.

Después pregunta separadamente si permitir root vía SSH y genera:

```text
PermitRootLogin yes
```

o:

```text
PermitRootLogin no
```

La ISO de pruebas permitió root porque se seleccionó explícitamente durante la instalación. Para producción se recomienda `no` y autenticación por clave.

---

## 28. Prueba estática antes de compilar

Ejecuta siempre:

```bash
./server/tests/test-server.sh
```

La suite verifica, entre otras cosas:

- sintaxis shell;
- paquetes NetworkManager/eudev/SSH/Avahi;
- cobertura del repositorio offline;
- ausencia de stack gráfico/audio/Bluetooth;
- overlay Live;
- coldplug udev;
- DHCP Ethernet;
- DNS NetworkManager;
- coexistencia;
- root SSH configurable;
- `os-prober`;
- `boot-order`;
- workaround `/dev/vdaN`;
- no dependencia de `setup-alpine`.

No consideres terminado un cambio hasta que esta suite pase.

---

## 29. Inspeccionar la ISO sin arrancarla

### Ver el contenido

```bash
xorriso -indev out/DexOS-Server-edge-x86_64.iso -find / -maxdepth 3 -print
```

### Extraer el apkovl

```bash
rm -rf /tmp/dexos-apkovl
mkdir /tmp/dexos-apkovl
xorriso -osirrox on   -indev out/DexOS-Server-edge-x86_64.iso   -extract /dexos-server.apkovl.tar.gz /tmp/dexos.apkovl.tar.gz

tar -xzf /tmp/dexos.apkovl.tar.gz -C /tmp/dexos-apkovl
```

Comprueba:

```bash
stat -c '%a %n' /tmp/dexos-apkovl
cat /tmp/dexos-apkovl/etc/apk/world
cat /tmp/dexos-apkovl/etc/NetworkManager/conf.d/10-dexos-network.conf
find /tmp/dexos-apkovl/etc/runlevels -type l -ls
ls -l /tmp/dexos-apkovl/usr/local/sbin/install
```

### Verificar APKINDEX

```bash
xorriso -osirrox on   -indev out/DexOS-Server-edge-x86_64.iso   -extract /apks/x86_64/APKINDEX.tar.gz /tmp/APKINDEX.tar.gz

tar -xOzf /tmp/APKINDEX.tar.gz APKINDEX > /tmp/APKINDEX

grep -c '^P:' /tmp/APKINDEX
```

Para esta ISO debe ser `176`.

---

## 30. Probar instalación realmente offline con QEMU

Primero crea un disco vacío nuevo:

```bash
rm -f runtime/dexos-test.qcow2
qemu-img create -f qcow2 runtime/dexos-test.qcow2 8G
```

Arranca la ISO **sin NIC**:

```bash
qemu-system-x86_64   -name DexOS-Offline-Test   -machine q35,accel=kvm   -cpu host   -m 4096   -smp 4   -boot order=d   -drive file=runtime/dexos-test.qcow2,format=qcow2,if=virtio   -cdrom out/DexOS-Server-edge-x86_64.iso   -nic none   -vnc 127.0.0.1:1   -display none
```

Si KVM no está disponible:

```text
-machine q35
-cpu max
```

será más lento pero funcional.

Dentro del Live:

```bash
install --check
install
```

La instalación completa debe funcionar sin Internet.

---

## 31. Segundo test obligatorio: arrancar SIN la ISO

Después de instalar, apaga QEMU y arranca solo el QCOW2:

```bash
qemu-system-x86_64   -name DexOS-Installed   -machine q35,accel=kvm   -cpu host   -m 4096   -smp 4   -boot order=c   -drive file=runtime/dexos-test.qcow2,format=qcow2,if=virtio   -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22   -vnc 127.0.0.1:1   -display none
```

Observa que **no hay `-cdrom`**.

Prueba SSH:

```bash
ssh -p 2222 root@127.0.0.1
```

o con el usuario administrador.

---

## 32. Validación de red/DNS del sistema instalado

Dentro de DexOS:

```bash
nmcli -f DEVICE,TYPE,STATE,CONNECTION device status
ip -4 addr
ip route
cat /etc/resolv.conf
ping -c1 1.1.1.1
ping -c1 dl-cdn.alpinelinux.org
apk update
```

Esperado en QEMU user-mode NAT:

```text
eth0 connected DexOS Wired
10.0.2.15/24
default via 10.0.2.2
nameserver 10.0.2.3
```

`apk update` debe terminar con exit code 0.

---

## 33. Validación de servicios y almacenamiento

```bash
rc-status sysinit
rc-status default

rc-service udev status
rc-service networkmanager status
rc-service sshd status
rc-service avahi-daemon status

lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS
cat /etc/fstab
findmnt /
findmnt /boot/efi
```

Comprueba también:

```bash
sshd -t
avahi-daemon --version || true
boot-order
```

Si `ss` no existe, no significa que SSH esté roto; `ss` viene de herramientas de diagnóstico adicionales y no era obligatorio en la imagen de referencia.

---

## 34. Errores conocidos y solución rápida

| Síntoma | Causa probable | Solución |
|---|---|---|
| Live muestra `localhost` y motd de Alpine | apkovl no llegó a la ISO | escribir `HOSTNAME.apkovl.tar.gz` fuera del tmp |
| Avahi `Permission denied` | `/` heredó modo 0700 del tmp | `chmod 0755 "$tmp"` antes de tar |
| `unknown filesystem type ext4` | modloop/drivers no arrancaron | `modloop`, `hwdrivers`, `modprobe ext4` |
| `apk` busca `x86_64/x86_64` | ruta repo apunta demasiado abajo | usar `/media/.../apks` |
| preflight dice OK con paquete inexistente | `apk fetch --simulate` no es fiable para exit status | usar `apk add --simulate --no-network` |
| `/dev/vda3` no existe tras sfdisk | race uevent/nodo device | `partx`, `mdev`/udev y fallback `mknod` desde sysfs |
| no se puede montar ESP | `/boot/efi` se creó antes de montar raíz | crear el directorio después de montar `/` |
| `lsblk` rechaza flags | util-linux 2.42 no admite `--list` + `--raw` juntos | usar `lsblk -npr ...` |
| NetworkManager muestra `unmanaged reason 71` | interfaz no inicializada por udev | eudev + udev-trigger + udev-settle |
| `apk update` no resuelve DNS | NM no obtuvo DHCP o no gestiona resolv.conf | eudev + perfil DHCP + `rc-manager=file` |
| ISO demasiado grande | meta `linux-firmware` completo | firmware selectivo + parche mkimg/update-kernel |
| xorriso falla dentro de PRoot | árbol/symlinks/proot | `YAH_SKIP_XORRISO=1`, ensamblar en host |
| nombres de cache exceden límite | args de sección largos | sustituir por hash si >180 chars |

---

## 35. Cómo congelar de verdad la versión para el futuro

### A. Guardar el repositorio Git local completo

Como el proyecto no tiene remote:

```bash
git bundle create dexos-server-9c8fb90.bundle --all
```

Para restaurar:

```bash
git clone dexos-server-9c8fb90.bundle yah-alpine
```

### B. Guardar aports exacto

No necesitas archivar todo aports si confías en GitLab, porque el commit está fijado:

```bash
git clone https://gitlab.alpinelinux.org/alpine/aports.git aports
git -C aports checkout f5ea0a0af34e2185bdd5543786433f5383172f89
```

Pero para independencia total:

```bash
git -C aports bundle create ../aports-f5ea0a0a.bundle --all
```

### C. Guardar el minirootfs

Conserva:

```text
alpine-minirootfs-20260805-x86_64.tar.gz
SHA256=5acac12c425a0817c1b6a79bdd5df4c73756fc8dc268eab32f8ba830872b835d
```

### D. Guardar APK exactos

La opción más sencilla es conservar:

- `cache/` del build bueno; o
- un directorio `frozen-repo/x86_64/` con todos los `.apk` usados.

Por ejemplo:

```bash
mkdir -p frozen-repo/x86_64
find cache -type f -name '*.apk' -exec cp -n {} frozen-repo/x86_64/ \;
```

Crea un inventario:

```bash
find frozen-repo/x86_64 -type f -name '*.apk' -print0   | sort -z   | xargs -0 sha256sum   > frozen-repo/SHA256SUMS
```

### E. Guardar la clave abuild

```text
build-home/.config/abuild/dexos-server.rsa
build-home/.config/abuild/dexos-server.rsa.pub
```

Guárdala cifrada/segura. No la publiques.

---

## 36. Procedimiento para actualizar Alpine intencionalmente

Cuando quieras subir de versión, **no cambies varias capas a la vez**.

Orden recomendado:

1. crea nueva rama del proyecto;
2. registra hashes actuales;
3. cambia solo minirootfs o aports commit;
4. ejecuta pruebas estáticas;
5. resuelve cambios de API de `mkimage`;
6. build;
7. inspecciona apkovl/APKINDEX;
8. instalación QEMU offline en QCOW nuevo;
9. boot sin ISO;
10. prueba NetworkManager/DNS/APK;
11. prueba SSH/Avahi/GRUB;
12. solo entonces actualiza la documentación y el hash de referencia.

Nunca sustituyas silenciosamente:

```text
f5ea0a0af34e2185bdd5543786433f5383172f89
```

por `master` si tu objetivo es reproducir esta versión.

---

## 37. Checklist especial para un LLM/agente autónomo

Si un LLM recibe este proyecto, debe seguir estas reglas:

1. **Leer este MD antes de tocar `aports` o `server/`.**
2. Ejecutar `git status` y registrar commit actual.
3. Verificar `git -C aports rev-parse HEAD == f5ea0a0af34e2185bdd5543786433f5383172f89` si se pretende reproducir la versión documentada.
4. No hacer `git pull`, `apk upgrade` ni cambiar repositorios sin petición explícita.
5. Verificar SHA-256 de minirootfs y fuentes personalizadas.
6. No meter GUI/audio/Bluetooth accidentalmente en la edición Server.
7. No usar `setup-alpine` como sustituto del instalador propio.
8. No usar Internet durante la prueba primaria de instalación.
9. Usar un QCOW2 **nuevo** para cada prueba destructiva.
10. Después de instalar, arrancar sin ISO.
11. Después activar red y verificar DHCP/DNS/APK.
12. Probar SSH real.
13. Inspeccionar `/etc/runlevels`, `/etc/fstab`, GRUB y UUID.
14. Ejecutar `./server/tests/test-server.sh` antes y después de cambios.
15. Calcular y registrar SHA-256 de cada ISO nueva.
16. Si el hash cambia, explicar por qué; no afirmar que es la misma build.
17. No considerar "funciona" solo porque QEMU llega al login Live: hay que probar instalación y primer boot desde disco.

---

## 38. Invariantes que no deben romperse

Para esta edición Server, una build se considera correcta si mantiene:

- terminal-only;
- sin Xorg/XFCE/LightDM/Firefox/Mesa salvo solicitud explícita;
- instalación offline;
- repo APK embebido;
- `install --check`;
- NetworkManager + eudev;
- Ethernet DHCP automático;
- Wi-Fi con `nmcli`;
- DNS funcional;
- OpenSSH;
- Avahi `.local`;
- BIOS + UEFI;
- UUID root verificado;
- coexistencia que no formatea la ESP;
- `os-prober`;
- `boot-order`;
- firmware Wi-Fi selectivo;
- host keys SSH generadas por máquina, no horneadas.

---

## 39. Hashes de las fuentes personalizadas de referencia

Usa estos hashes para detectar cambios accidentales:

| Archivo | SHA-256 |
|---|---|
| `server/build-dexos-server.sh` | `f3092b26ba7f922a23bab87f294a2f129f1938347a376ff4caf073a3165b9503` |
| `server/install` | `82202ff06c7ac4c266948944ff946ca1a7de5a86e1a4abc1f8e4a5d06529b41f` |
| `server/boot-order` | `9f003aaee9f08509b312f63b6dd4f9431829614c7ae4c8c69a49879f3788f2f4` |
| `server/mkimage/mkimg.dexserver.sh` | `482e916bee2ef0bbf62811933ded7c1eb49258a231659ddd7415156c79cf45d2` |
| `server/mkimage/genapkovl-dexserver.sh` | `84c6688110463ec5cd6c5046f528dc1351e5d835a73e6945c525276588a41a07` |
| `server/packages.txt` | `ae012aec758dcb93fe474cca71b91ecb1d0658ade9149f226f6808d78b88231b` |
| `server/live-world.txt` | `a510c085ec33174a0e7f5f380719665faa377b3afe5eab1ba59a7b19ded8c378` |
| `server/tests/test-server.sh` | `ba02b592e3b9085e0c6023f6aebf94c0d99c31ce3938539fd354503e3b0d8cd3` |

Si cualquiera cambia, la build ya no es exactamente la fuente documentada. Eso puede ser correcto si el cambio fue intencional; simplemente debes registrar un nuevo estado.

---

# APÉNDICE A — Fuentes exactas personalizadas

Las siguientes secciones contienen los archivos de referencia completos tal como estaban en el commit local `9c8fb90` / estado documentado de la corrección de red. Esto permite reconstruir el método aun si el repositorio local se pierde.

### `server/build-dexos-server.sh`

```sh
#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALPINE_ROOT="$ROOT/alpine-root"
APORTS="$ROOT/aports"
CACHE="$ROOT/cache"
OUT="$ROOT/out"
BUILD_HOME="$ROOT/build-home"
KEY_DIR="$BUILD_HOME/.config/abuild"
PRIVKEY="$KEY_DIR/dexos-server.rsa"
PUBKEY="$PRIVKEY.pub"
mkdir -p "$CACHE" "$OUT" "$KEY_DIR"
for cmd in proot xorrisofs openssl sha256sum; do command -v "$cmd" >/dev/null || { echo "Missing $cmd" >&2; exit 1; }; done
[ -x "$ALPINE_ROOT/sbin/apk" ]
[ -x "$APORTS/scripts/mkimage.sh" ]
if [ ! -f "$PRIVKEY" ]; then
  openssl genrsa -out "$PRIVKEY" 3072 >/dev/null 2>&1
  chmod 0600 "$PRIVKEY"
  openssl rsa -in "$PRIVKEY" -pubout -out "$PUBKEY" >/dev/null 2>&1
fi
mkdir -p "$ALPINE_ROOT/etc/apk/keys"
cp "$PUBKEY" "$ALPINE_ROOT/etc/apk/keys/dexos-server.rsa.pub"
cp "$ROOT/server/mkimage/mkimg.dexserver.sh" "$APORTS/scripts/mkimg.dexserver.sh"
cp "$ROOT/server/mkimage/genapkovl-dexserver.sh" "$APORTS/scripts/genapkovl-dexserver.sh"
chmod +x "$APORTS/scripts/genapkovl-dexserver.sh"
python3 - "$APORTS/scripts/mkimg.base.sh" "$APORTS/scripts/mkimage.sh" <<'PY'
from pathlib import Path
import sys
base = Path(sys.argv[1])
s = base.read_text()
old = '_pkgs="linux-$_f linux-firmware wireless-regdb $modloop_addons"'
new = '_pkgs="linux-$_f ${kernel_firmware_packages:-linux-firmware} wireless-regdb $modloop_addons"'
if old in s:
    s = s.replace(old, new, 1)
elif new not in s:
    raise SystemExit('mkimg.base.sh firmware anchor not found')
# Skip xorriso inside proot; it cannot reliably follow the generated tree there.
needle_iso='\tif [ "$ARCH" = ppc64le ]; then\n'
marker='\t[ "${YAH_SKIP_XORRISO:-}" = "1" ] && return 0\n\n'
if 'YAH_SKIP_XORRISO' not in s:
    idx=s.find(needle_iso, s.find('create_image_iso()'))
    if idx < 0:
        raise SystemExit('create_image_iso insertion point not found')
    s=s[:idx]+marker+s[idx:]
base.write_text(s)
mk = Path(sys.argv[2])
m = mk.read_text()
m = m.replace('cp -Lrs $_fn $DESTDIR/', 'cp -Lr $_fn $DESTDIR/')
needle = '\tlocal _dir="${args//[^a-zA-Z0-9]/_}"\n'
short = needle + '\tif [ ${#_dir} -gt 180 ]; then _dir="${section}_$(printf %s "$args" | sha1sum | cut -c1-40)"; fi\n'
if short not in m:
    if needle not in m:
        raise SystemExit('mkimage.sh build_section anchor not found')
    m = m.replace(needle, short, 1)
mk.write_text(m)
PY
python3 - "$ALPINE_ROOT/usr/sbin/update-kernel" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = 'PACKAGES="$PACKAGES linux-$FLAVOR linux-firmware"'
new = 'PACKAGES="$PACKAGES linux-$FLAVOR"'
if old in s:
    s = s.replace(old, new, 1)
elif new not in s:
    raise SystemExit('update-kernel firmware anchor not found')
p.write_text(s)
PY
rm -rf "$CACHE"/apkovl_* "$CACHE"/image-*-x86_64-dexserver "$OUT"/DexOS-Server-edge-x86_64.iso*
proot -i 1000:1000 -R "$ALPINE_ROOT" -b "$ROOT:/work" -w /work/server/mkimage \
  /usr/bin/env HOME=/work/build-home PACKAGER_PRIVKEY=/work/build-home/.config/abuild/dexos-server.rsa PACKAGER_PUBKEY=/work/build-home/.config/abuild/dexos-server.rsa.pub YAH_SKIP_XORRISO=1 \
  /bin/sh /work/aports/scripts/mkimage.sh --tag edge --outdir /work/out --workdir /work/cache --arch x86_64 --profile dexserver \
  --repository https://dl-cdn.alpinelinux.org/alpine/edge/main \
  --repository https://dl-cdn.alpinelinux.org/alpine/edge/community

IMG="$(find "$CACHE" -maxdepth 1 -type d -name 'image-*-x86_64-dexserver' -print | sort | tail -1)"
[ -n "$IMG" ] && [ -f "$IMG/boot/grub/efi.img" ] && [ -f "$IMG/boot/syslinux/isolinux.bin" ]
iso="$OUT/DexOS-Server-edge-x86_64.iso"
xorrisofs \
  -output "$iso" \
  -full-iso9660-filenames -joliet -rational-rock \
  -sysid LINUX -volid DEXOS_SERVER \
  -isohybrid-mbr "$IMG/boot/syslinux/isohdpfx.bin" \
  -eltorito-boot boot/syslinux/isolinux.bin \
  -eltorito-catalog boot/syslinux/boot.cat \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
  -isohybrid-gpt-basdat -follow-links "$IMG"
sha256sum "$iso" > "$iso.sha256"
ls -lh "$iso"
cat "$iso.sha256"
```

### `server/install`

```sh
#!/bin/sh
set -eu

TARGET=/mnt/dexos-target
PACKAGE_FILE=/usr/share/dexos/server-packages.txt
ONLINE_MAIN=https://dl-cdn.alpinelinux.org/alpine/edge/main
ONLINE_COMMUNITY=https://dl-cdn.alpinelinux.org/alpine/edge/community
MIN_DISK=4294967296
MIN_ROOT=1073741824
EFI_GUID=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
BIOS_GUID=21686148-6449-6e6f-744e-656564454649
MOUNTED=0
WORK=/tmp/dexos-installer.$$
mkdir -p "$WORK"

say() { printf '\n==> %s\n' "$*"; }
warn() { printf '\nAVISO: %s\n' "$*" >&2; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
ask() { printf '%s' "$1"; IFS= read -r REPLY; }
secret() {
    printf '%s' "$1"
    stty -echo 2>/dev/null || true
    IFS= read -r REPLY
    stty echo 2>/dev/null || true
    printf '\n'
}
confirm() {
    printf '%s [s/N]: ' "$1"
    IFS= read -r answer
    case "$answer" in s|S|si|SI|sí|Sí|y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
cleanup() {
    if [ "$MOUNTED" -eq 1 ]; then
        umount -R "$TARGET" >/dev/null 2>&1 || true
        MOUNTED=0
    fi
    rm -rf "$WORK" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM

case "${1:-}" in
    ''|--wifi|--check|--help|-h) ;;
    *)
        if [ -x /usr/bin/install ] && [ "$0" != /usr/bin/install ]; then
            exec /usr/bin/install "$@"
        fi
        die "Opción desconocida: $1"
        ;;
esac

if [ "${1:-}" = --help ] || [ "${1:-}" = -h ]; then
    cat <<'EOF'
DexOS Server installer

  install          Ejecuta el asistente inteligente de instalación offline.
  install --wifi   Ejecuta únicamente el asistente de Wi-Fi.
  install --check  Verifica medio, módulos, paquetes y discos sin modificar nada.
EOF
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    if command -v doas >/dev/null 2>&1; then exec doas "$0" "$@"; fi
    die "El instalador necesita privilegios root."
fi

find_repo() {
    for arch_repo in /media/*/apks/x86_64 /media/*/*/apks/x86_64 /run/media/*/apks/x86_64; do
        if [ -f "$arch_repo/APKINDEX.tar.gz" ]; then
            dirname "$arch_repo"
            return 0
        fi
    done
    return 1
}

packages() {
    [ -f "$PACKAGE_FILE" ] || die "Falta $PACKAGE_FILE"
    sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' "$PACKAGE_FILE"
}

require_cmds() {
    missing=''
    for cmd in apk lsblk sfdisk blockdev partx wipefs mkfs.vfat mkfs.ext4 mount umount chroot blkid grub-install nmcli rc-service findmnt mknod modprobe uuidgen; do
        command -v "$cmd" >/dev/null 2>&1 || missing="$missing $cmd"
    done
    [ -z "$missing" ] || die "Faltan herramientas del Live:$missing"
}

ensure_runtime_modules() {
    rc-service modloop status >/dev/null 2>&1 || rc-service modloop start >/dev/null 2>&1 || true
    rc-service hwdrivers status >/dev/null 2>&1 || rc-service hwdrivers start >/dev/null 2>&1 || true
    modprobe ext4 >/dev/null 2>&1 || die "No se pudo cargar ext4 desde modloop."
    modprobe vfat >/dev/null 2>&1 || true
}

ensure_networkmanager() {
    rc-service dbus status >/dev/null 2>&1 || rc-service dbus start >/dev/null 2>&1 || true
    rc-service networkmanager status >/dev/null 2>&1 || rc-service networkmanager start >/dev/null 2>&1 || true
}

wifi_assistant() {
    require_cmds
    ensure_networkmanager
    say "Red y Wi-Fi"
    nmcli -f DEVICE,TYPE,STATE,CONNECTION device status || true

    if ! nmcli -t -f DEVICE,TYPE device status 2>/dev/null | grep -q ':wifi$'; then
        echo "No se detectó adaptador Wi-Fi. Ethernet será gestionado por NetworkManager."
        return 0
    fi

    nmcli radio wifi on >/dev/null 2>&1 || true
    nmcli device wifi rescan >/dev/null 2>&1 || true
    echo
    nmcli -f IN-USE,SSID,SIGNAL,SECURITY device wifi list || true
    echo
    confirm "¿Quieres conectarte a una red Wi-Fi ahora?" || return 0
    ask "SSID exacto: "
    ssid=$REPLY
    [ -n "$ssid" ] || die "El SSID no puede estar vacío."
    secret "Contraseña Wi-Fi (Enter si es abierta): "
    wifi_password=$REPLY
    if [ -n "$wifi_password" ]; then
        nmcli device wifi connect "$ssid" password "$wifi_password"
    else
        nmcli device wifi connect "$ssid"
    fi
    unset wifi_password
    nmcli -f DEVICE,TYPE,STATE,CONNECTION device status || true
}

preflight() {
    require_cmds
    ensure_runtime_modules
    repo=$(find_repo) || die "No se encontró el repositorio APK offline de DexOS Server."
    package_words=$(packages | tr '\n' ' ')
    [ -n "$package_words" ] || die "La lista de paquetes está vacía."
    say "Verificando repositorio offline"
    echo "Repositorio: $repo"
    apk add --simulate --no-network --repositories-file /dev/null \
        --repository "$repo" $package_words >/dev/null \
        || die "El repositorio offline no contiene todas las dependencias del sistema instalado."
}

validate_hostname() {
    printf '%s\n' "$1" | grep -Eq '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$'
}
validate_user() {
    [ "$1" != root ] && printf '%s\n' "$1" | grep -Eq '^[a-z_][a-z0-9_-]{0,30}$'
}

normalize_mdns_name() {
    name=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    name=${name%.}
    case "$name" in *.local) name=${name%.local} ;; esac
    validate_hostname "$name" || die "Nombre inválido. Usa letras, números y guiones; .local es opcional."
    hostname=$name
    mdns_name=$name.local
}

collect_identity() {
    say "Identidad del servidor"
    ask "Nombre del servidor/mDNS [dexos-server.local]: "
    normalize_mdns_name "${REPLY:-dexos-server.local}"
    echo "El servidor se anunciará como: $mdns_name"

    ask "Usuario administrador [admin]: "
    admin_user=${REPLY:-admin}
    validate_user "$admin_user" || die "Usuario no válido."

    secret "Contraseña de $admin_user (mínimo 8 caracteres): "
    admin_password=$REPLY
    [ ${#admin_password} -ge 8 ] || die "La contraseña debe tener al menos 8 caracteres."
    case "$admin_password" in *:*) die "La contraseña no puede contener ':'." ;; esac
    secret "Repite la contraseña de $admin_user: "
    [ "$REPLY" = "$admin_password" ] || die "Las contraseñas del usuario no coinciden."

    secret "Contraseña de root [Enter = usar la de $admin_user]: "
    if [ -z "$REPLY" ]; then
        root_password=$admin_password
        echo "root usará la misma contraseña que $admin_user."
    else
        root_password=$REPLY
        [ ${#root_password} -ge 8 ] || die "La contraseña root debe tener al menos 8 caracteres."
        case "$root_password" in *:*) die "La contraseña root no puede contener ':'." ;; esac
        secret "Repite la contraseña de root: "
        [ "$REPLY" = "$root_password" ] || die "Las contraseñas root no coinciden."
    fi

    if confirm "¿Permitir acceso root directamente por SSH?"; then
        ssh_root_login=yes
    else
        ssh_root_login=no
    fi

    ask "Zona horaria [UTC] (ej. America/Mexico_City): "
    timezone=${REPLY:-UTC}
    case "$timezone" in /*|*'..'*) die "Zona horaria no válida." ;; esac
    [ -f "/usr/share/zoneinfo/$timezone" ] || die "Zona horaria no disponible: $timezone"
}

installation_media_disk() {
    repo=$(find_repo 2>/dev/null || true)
    [ -n "$repo" ] || return 0
    src=$(findmnt -n -o SOURCE -T "$repo" 2>/dev/null || true)
    case "$src" in
        /dev/*)
            type=$(lsblk -dnro TYPE "$src" 2>/dev/null | tr -d ' ')
            if [ "$type" = part ]; then
                pk=$(lsblk -dnro PKNAME "$src" 2>/dev/null | tr -d ' ')
                [ -n "$pk" ] && printf '/dev/%s\n' "$pk"
            elif [ "$type" = disk ]; then
                printf '%s\n' "$src"
            fi
            ;;
    esac
}

make_disk_list() {
    file=$1
    live_disk=$(installation_media_disk || true)
    : > "$file"
    lsblk -dnpr -o NAME,TYPE,RO | awk '$2=="disk" && $3==0 {print $1}' | while IFS= read -r dev; do
        [ -n "$live_disk" ] && [ "$dev" = "$live_disk" ] && continue
        printf '%s\n' "$dev"
    done > "$file"
}

print_disk_menu() {
    file=$1
    idx=1
    while IFS= read -r dev; do
        meta=$(lsblk -dn -o SIZE,MODEL,TRAN "$dev" 2>/dev/null | sed 's/[[:space:]]*$//')
        printf ' %d) %-14s %s\n' "$idx" "$dev" "$meta"
        idx=$((idx + 1))
    done < "$file"
}

select_disk() {
    file="$WORK/disks"
    make_disk_list "$file"
    [ -s "$file" ] || die "No hay discos instalables; el medio Live se excluye automáticamente."
    say "Discos disponibles"
    print_disk_menu "$file"
    count=$(wc -l < "$file" | tr -d ' ')
    while :; do
        ask "Selecciona el disco [1-$count]: "
        case "$REPLY" in ''|*[!0-9]*) echo "Selección inválida."; continue ;; esac
        [ "$REPLY" -ge 1 ] && [ "$REPLY" -le "$count" ] || { echo "Fuera de rango."; continue; }
        disk=$(sed -n "${REPLY}p" "$file")
        break
    done
}

is_efi_guid() {
    pt=$(lsblk -dnro PARTTYPE "$1" 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    [ "$pt" = "$EFI_GUID" ]
}

make_root_partition_list() {
    file=$1
    : > "$file"
    lsblk -npr -o NAME,TYPE,RO "$disk" | awk '$2=="part" && $3==0 {print $1}' | while IFS= read -r part; do
        is_efi_guid "$part" && continue
        mnt=$(lsblk -dnro MOUNTPOINTS "$part" 2>/dev/null | tr -d ' ')
        [ -n "$mnt" ] && continue
        size=$(lsblk -bdnro SIZE "$part" 2>/dev/null | tr -d ' ')
        [ "${size:-0}" -ge "$MIN_ROOT" ] || continue
        printf '%s\n' "$part"
    done > "$file"
}

print_partition_menu() {
    file=$1
    idx=1
    while IFS= read -r part; do
        meta=$(lsblk -dn -o SIZE,FSTYPE,LABEL,PARTLABEL "$part" 2>/dev/null | sed 's/[[:space:]]*$//')
        printf ' %d) %-16s %s\n' "$idx" "$part" "$meta"
        idx=$((idx + 1))
    done < "$file"
}

select_root_partition() {
    file="$WORK/root-parts"
    make_root_partition_list "$file"
    [ -s "$file" ] || die "No hay particiones raíz utilizables de al menos 1 GiB en $disk."
    say "Partición para DexOS Server"
    echo "La partición elegida se formateará como ext4; las demás se conservarán."
    print_partition_menu "$file"
    count=$(wc -l < "$file" | tr -d ' ')
    while :; do
        ask "Selecciona la partición raíz [1-$count]: "
        case "$REPLY" in ''|*[!0-9]*) echo "Selección inválida."; continue ;; esac
        [ "$REPLY" -ge 1 ] && [ "$REPLY" -le "$count" ] || { echo "Fuera de rango."; continue; }
        root_part=$(sed -n "${REPLY}p" "$file")
        break
    done
}

make_efi_partition_list() {
    file=$1
    : > "$file"
    lsblk -npr -o NAME,TYPE,RO "$disk" | awk '$2=="part" && $3==0 {print $1}' | while IFS= read -r part; do
        [ "$part" = "$root_part" ] && continue
        fs=$(lsblk -dnro FSTYPE "$part" 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d ' ')
        if is_efi_guid "$part" || [ "$fs" = vfat ] || [ "$fs" = fat ] || [ "$fs" = fat32 ]; then
            printf '%s\n' "$part"
        fi
    done > "$file"
}

select_efi_partition() {
    file="$WORK/efi-parts"
    make_efi_partition_list "$file"
    efi_part=''
    if [ ! -s "$file" ]; then
        echo "No se detectó una partición EFI/FAT en $disk."
        return 0
    fi
    say "Partición de arranque EFI"
    echo "Se reutilizará sin formatearla; los cargadores existentes se conservan."
    print_partition_menu "$file"
    echo " 0) Ninguna (solo BIOS si el disco lo permite)"
    count=$(wc -l < "$file" | tr -d ' ')
    default=''
    [ "$count" -eq 1 ] && default=1
    while :; do
        if [ -n "$default" ]; then
            ask "Selecciona la ESP [0-$count, Enter=$default]: "
            choice=${REPLY:-$default}
        else
            ask "Selecciona la ESP [0-$count]: "
            choice=$REPLY
        fi
        case "$choice" in *[!0-9]*|'') echo "Selección inválida."; continue ;; esac
        [ "$choice" -ge 0 ] && [ "$choice" -le "$count" ] || { echo "Fuera de rango."; continue; }
        [ "$choice" -eq 0 ] && { efi_part=''; break; }
        efi_part=$(sed -n "${choice}p" "$file")
        fs=$(lsblk -dnro FSTYPE "$efi_part" 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d ' ')
        case "$fs" in vfat|fat|fat32) ;; *) echo "$efi_part no contiene un filesystem FAT utilizable como ESP."; continue ;; esac
        break
    done
}

disk_bios_capable() {
    pttype=$(blkid -p -s PTTYPE -o value "$disk" 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
    case "$pttype" in dos|msdos) return 0 ;; esac
    [ "$pttype" = gpt ] || return 1
    lsblk -nro PARTTYPE "$disk" 2>/dev/null \
        | tr '[:upper:]' '[:lower:]' \
        | tr -d ' ' \
        | grep -qx "$BIOS_GUID"
}

validate_boot_plan() {
    bios_install=0
    efi_install=0
    disk_bios_capable && bios_install=1 || true
    [ -n "${efi_part:-}" ] && efi_install=1
    if [ -d /sys/firmware/efi ] && [ "$efi_install" -ne 1 ]; then
        die "El Live arrancó en UEFI; selecciona una partición EFI para garantizar el arranque."
    fi
    [ "$bios_install" -eq 1 ] || [ "$efi_install" -eq 1 ] \
        || die "No hay un destino de arranque válido: falta ESP y el disco no permite GRUB BIOS."
}

choose_layout() {
    say "Modo de instalación"
    echo " 1) Usar un disco completo (borra ese disco)"
    echo " 2) Coexistir con otro sistema usando particiones existentes"
    while :; do
        ask "Selecciona [1-2]: "
        case "$REPLY" in 1) install_mode=whole; break ;; 2) install_mode=coexist; break ;; *) echo "Elige 1 o 2." ;; esac
    done

    select_disk
    if [ "$install_mode" = whole ]; then
        disk_size=$(lsblk -bdnro SIZE "$disk" 2>/dev/null | tr -d ' ')
        [ "${disk_size:-0}" -ge "$MIN_DISK" ] || die "DexOS Server requiere un disco de al menos 4 GiB."
        if lsblk -nr -o MOUNTPOINTS "$disk" | grep -q '[^[:space:]]'; then
            die "$disk contiene una partición montada. Desmóntala o usa modo coexistencia."
        fi
        root_part=''
        efi_part=''
        bios_install=1
        efi_install=1
    else
        select_root_partition
        select_efi_partition
        validate_boot_plan
    fi
}

part_path() {
    case "$1" in *[0-9]) printf '%sp%s\n' "$1" "$2" ;; *) printf '%s%s\n' "$1" "$2" ;; esac
}

ensure_block_node() {
    path=$1
    [ -b "$path" ] && return 0
    name=${path#/dev/}
    sysdev="/sys/class/block/$name/dev"
    if [ -r "$sysdev" ]; then
        mm=$(cat "$sysdev")
        major=${mm%%:*}
        minor=${mm#*:}
        rm -f "$path" 2>/dev/null || true
        mknod "$path" b "$major" "$minor" 2>/dev/null || true
    fi
    [ -b "$path" ]
}

refresh_partition_nodes() {
    sync
    blockdev --rereadpt "$disk" >/dev/null 2>&1 || true
    partx -u "$disk" >/dev/null 2>&1 || partx -a "$disk" >/dev/null 2>&1 || true
    command -v mdev >/dev/null 2>&1 && mdev -s >/dev/null 2>&1 || true
}

wait_block() {
    path=$1
    count=0
    while [ "$count" -lt 30 ]; do
        ensure_block_node "$path" && return 0
        refresh_partition_nodes
        ensure_block_node "$path" && return 0
        sleep 1
        count=$((count + 1))
    done
    die "No apareció el dispositivo $path después de actualizar la tabla de particiones."
}

prepare_storage() {
    ensure_runtime_modules
    if [ "$install_mode" = whole ]; then
        bios_part=$(part_path "$disk" 1)
        efi_part=$(part_path "$disk" 2)
        root_part=$(part_path "$disk" 3)
        say "Creando GPT BIOS + UEFI"
        wipefs -a "$disk"
        sfdisk --wipe always --wipe-partitions always "$disk" <<EOF
label: gpt
size=2M, type=$BIOS_GUID
size=512M, type=$EFI_GUID
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
EOF
        refresh_partition_nodes
        wait_block "$bios_part"
        wait_block "$efi_part"
        wait_block "$root_part"
        say "Formateando particiones nuevas"
        wait_block "$efi_part"
        mkfs.vfat -F 32 -n DEXOS_EFI "$efi_part"
        refresh_partition_nodes
        wait_block "$root_part"
        mkfs.ext4 -F -L DexOS-Server "$root_part"
        bios_install=1
        efi_install=1
    else
        say "Preparando la partición raíz seleccionada"
        echo "Se conservarán todas las demás particiones, incluida: ${efi_part:-ninguna ESP seleccionada}."
        wait_block "$root_part"
        wipefs -a "$root_part"
        wait_block "$root_part"
        mkfs.ext4 -F -L DexOS-Server "$root_part"
        wait_block "$root_part"
    fi
}

mount_target() {
    umount -R "$TARGET" >/dev/null 2>&1 || true
    rm -rf "$TARGET"
    mkdir -p "$TARGET"
    wait_block "$root_part"
    mount -t ext4 "$root_part" "$TARGET"
    MOUNTED=1
    mkdir -p "$TARGET/boot/efi"
    if [ -n "${efi_part:-}" ]; then
        wait_block "$efi_part"
        mount "$efi_part" "$TARGET/boot/efi"
    fi
    for src in proc sys dev run; do
        mkdir -p "$TARGET/$src"
        mount --rbind "/$src" "$TARGET/$src"
        mount --make-rslave "$TARGET/$src"
    done
}

install_offline_packages() {
    repo=$(find_repo) || die "El repositorio APK de la ISO desapareció."
    package_words=$(packages | tr '\n' ' ')
    mkdir -p "$TARGET/etc/apk/keys"
    cp /etc/apk/keys/* "$TARGET/etc/apk/keys/"
    say "Instalando paquetes desde la ISO (sin Internet)"
    apk add --root "$TARGET" --initdb --arch x86_64 \
        --keys-dir /etc/apk/keys --no-network --repositories-file /dev/null \
        --repository "$repo" $package_words
}

write_target_config() {
    say "Configurando DexOS Server"
    mkdir -p "$TARGET/etc/apk" "$TARGET/etc/ssh/sshd_config.d" "$TARGET/etc/avahi" \
        "$TARGET/etc/doas.d" "$TARGET/etc/NetworkManager/conf.d" \
        "$TARGET/etc/NetworkManager/system-connections" "$TARGET/usr/local/sbin"

    cat > "$TARGET/etc/apk/repositories" <<EOF
$ONLINE_MAIN
$ONLINE_COMMUNITY
EOF
    printf '%s\n' "$hostname" > "$TARGET/etc/hostname"
    cat > "$TARGET/etc/hosts" <<EOF
127.0.0.1 localhost localhost.localdomain
127.0.1.1 $hostname $hostname.localdomain
::1 localhost localhost.localdomain
EOF
    ln -sf "/usr/share/zoneinfo/$timezone" "$TARGET/etc/localtime"
    printf '%s\n' "$timezone" > "$TARGET/etc/timezone"

    cat > "$TARGET/etc/os-release" <<'EOF'
NAME="DexOS Server"
PRETTY_NAME="DexOS Server"
ID=dexos-server
ID_LIKE=alpine
VERSION_ID="edge"
VERSION="edge"
EOF
    cat > "$TARGET/etc/issue" <<'EOF'
DexOS Server \n (Alpine Linux) \l
EOF
    cat > "$TARGET/etc/motd" <<EOF
DexOS Server
mDNS: $mdns_name
Network: nmcli
Cambiar arranque predeterminado: boot-order
EOF
    cat > "$TARGET/etc/ssh/sshd_config.d/10-dexos-server.conf" <<EOF
PasswordAuthentication yes
PermitRootLogin $ssh_root_login
PermitEmptyPasswords no
UseDNS no
EOF
    cat > "$TARGET/etc/avahi/avahi-daemon.conf" <<EOF
[server]
host-name=$hostname
domain-name=local
use-ipv4=yes
use-ipv6=yes
[wide-area]
enable-wide-area=no
[publish]
publish-addresses=yes
publish-workstation=no
EOF
    cat > "$TARGET/etc/doas.d/10-wheel.conf" <<'EOF'
permit persist :wheel
EOF
    chmod 0600 "$TARGET/etc/doas.d/10-wheel.conf"

    cat > "$TARGET/etc/NetworkManager/conf.d/10-dexos-network.conf" <<'EOF'
[main]
plugins=keyfile
rc-manager=file
dns=default

[ifupdown]
managed=true
EOF
    cat > "$TARGET/etc/resolv.conf" <<'EOF'
# Fallback DNS; NetworkManager replaces this after DHCP/Wi-Fi connects.
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

    chroot "$TARGET" /usr/sbin/adduser -D -s /bin/ash "$admin_user"
    chroot "$TARGET" /usr/sbin/addgroup "$admin_user" wheel >/dev/null 2>&1 || true
    chroot "$TARGET" /usr/sbin/addgroup "$admin_user" plugdev >/dev/null 2>&1 || true
    printf '%s:%s\nroot:%s\n' "$admin_user" "$admin_password" "$root_password" \
        | chroot "$TARGET" /usr/sbin/chpasswd
    unset admin_password root_password

    chroot "$TARGET" /usr/bin/ssh-keygen -A >/dev/null 2>&1 || true
    chroot "$TARGET" /sbin/rc-update del mdev sysinit >/dev/null 2>&1 || true
    for svc in udev udev-trigger udev-settle; do
        chroot "$TARGET" /sbin/rc-update add "$svc" sysinit >/dev/null 2>&1 || true
    done
    for svc in dbus networkmanager sshd avahi-daemon udev-postmount; do
        chroot "$TARGET" /sbin/rc-update add "$svc" default >/dev/null 2>&1 || true
    done
    chroot "$TARGET" /sbin/rc-update del networking default >/dev/null 2>&1 || true
    chroot "$TARGET" /sbin/rc-update del dhcpcd default >/dev/null 2>&1 || true
    chroot "$TARGET" /sbin/rc-update del wpa_supplicant default >/dev/null 2>&1 || true

    if [ -d /etc/NetworkManager/system-connections ]; then
        cp -a /etc/NetworkManager/system-connections/. "$TARGET/etc/NetworkManager/system-connections/" 2>/dev/null || true
    fi
    wired_uuid=$(uuidgen)
    cat > "$TARGET/etc/NetworkManager/system-connections/dexos-wired.nmconnection" <<EOF
[connection]
id=DexOS Wired
uuid=$wired_uuid
type=ethernet
autoconnect=true
autoconnect-priority=100

[ethernet]

[ipv4]
method=auto

[ipv6]
method=auto
addr-gen-mode=default

[proxy]
EOF
    chmod 0600 "$TARGET"/etc/NetworkManager/system-connections/* 2>/dev/null || true
    if [ -x /usr/local/sbin/boot-order ]; then
        cp /usr/local/sbin/boot-order "$TARGET/usr/local/sbin/boot-order"
        chmod 0755 "$TARGET/usr/local/sbin/boot-order"
    fi
}

configure_boot() {
    root_uuid=$(blkid -s UUID -o value "$root_part")
    [ -n "$root_uuid" ] || die "No se pudo obtener el UUID de la raíz."
    efi_uuid=''
    [ -z "${efi_part:-}" ] || efi_uuid=$(blkid -s UUID -o value "$efi_part")

    cat > "$TARGET/etc/fstab" <<EOF
UUID=$root_uuid / ext4 defaults,noatime 0 1
EOF
    if [ -n "$efi_uuid" ]; then
        printf 'UUID=%s /boot/efi vfat umask=0077 0 2\n' "$efi_uuid" >> "$TARGET/etc/fstab"
    fi
    printf 'tmpfs /tmp tmpfs nosuid,nodev 0 0\n' >> "$TARGET/etc/fstab"

    mkdir -p "$TARGET/etc/mkinitfs"
    cat > "$TARGET/etc/mkinitfs/mkinitfs.conf" <<'EOF'
features="ata base scsi usb virtio ext4 nvme"
EOF
    kernel_version=''
    for module_dir in "$TARGET"/lib/modules/*; do
        [ -d "$module_dir" ] || continue
        kernel_version=${module_dir##*/}
    done
    [ -n "$kernel_version" ] || die "No se encontró el kernel instalado."

    say "Generando initramfs"
    chroot "$TARGET" /sbin/mkinitfs -c /etc/mkinitfs/mkinitfs.conf -o /boot/initramfs-lts "$kernel_version"
    [ -s "$TARGET/boot/initramfs-lts" ] || die "No se generó /boot/initramfs-lts."
    [ -s "$TARGET/boot/vmlinuz-lts" ] || die "No se instaló /boot/vmlinuz-lts."

    say "Instalando GRUB"
    bios_ok=0
    efi_ok=0
    if [ "$bios_install" -eq 1 ]; then
        if grub-install --boot-directory="$TARGET/boot" --target=i386-pc "$disk"; then
            bios_ok=1
        elif [ "$efi_install" -ne 1 ]; then
            die "Falló GRUB BIOS y no existe una alternativa UEFI."
        else
            warn "GRUB BIOS no pudo instalarse; se continuará con UEFI."
        fi
    fi

    if [ "$efi_install" -eq 1 ]; then
        [ -n "${efi_part:-}" ] || die "Se solicitó UEFI pero no hay ESP seleccionada."
        if [ -d /sys/firmware/efi/efivars ]; then
            grub-install --target=x86_64-efi --efi-directory="$TARGET/boot/efi" \
                --bootloader-id=DexOS --boot-directory="$TARGET/boot"
        else
            grub-install --target=x86_64-efi --efi-directory="$TARGET/boot/efi" \
                --bootloader-id=DexOS --boot-directory="$TARGET/boot" --no-nvram
        fi
        efi_ok=1
        if [ "$install_mode" = whole ]; then
            mkdir -p "$TARGET/boot/efi/EFI/BOOT"
            cp "$TARGET/boot/efi/EFI/DexOS/grubx64.efi" "$TARGET/boot/efi/EFI/BOOT/BOOTX64.EFI"
        fi
    fi
    [ "$bios_ok" -eq 1 ] || [ "$efi_ok" -eq 1 ] || die "No se instaló ningún cargador de arranque."

    cat > "$TARGET/etc/default/grub" <<EOF
GRUB_TIMEOUT=5
GRUB_DEFAULT=saved
GRUB_SAVEDEFAULT=false
GRUB_DISABLE_SUBMENU=y
GRUB_DISABLE_RECOVERY=true
GRUB_DISTRIBUTOR="DexOS Server"
GRUB_DISABLE_OS_PROBER=false
GRUB_CMDLINE_LINUX="root=UUID=$root_uuid rootfstype=ext4"
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
EOF

    say "Buscando Windows y otros Linux"
    mkdir -p "$TARGET/var/log"
    if [ -x "$TARGET/usr/bin/os-prober" ]; then
        chroot "$TARGET" /usr/bin/os-prober > "$TARGET/var/log/dexos-os-prober.log" 2>&1 || true
        if [ -s "$TARGET/var/log/dexos-os-prober.log" ]; then
            cat "$TARGET/var/log/dexos-os-prober.log"
        else
            echo "No se detectaron otros sistemas operativos."
        fi
    fi
    chroot "$TARGET" /usr/sbin/grub-mkconfig -o /boot/grub/grub.cfg
    grep -Fq "root=UUID=$root_uuid" "$TARGET/boot/grub/grub.cfg" \
        || die "GRUB no quedó configurado con el UUID de la raíz."
    chroot "$TARGET" /usr/sbin/grub-set-default 0 >/dev/null 2>&1 || true
}

show_installable_disks() {
    file="$WORK/check-disks"
    make_disk_list "$file"
    if [ ! -s "$file" ]; then
        echo "No hay discos de destino; el medio de instalación está oculto."
        return 0
    fi
    print_disk_menu "$file"
}

run_check() {
    preflight
    ensure_networkmanager
    say "NetworkManager"
    nmcli -f DEVICE,TYPE,STATE,CONNECTION device status || true
    say "Discos instalables"
    show_installable_disks
    echo
    echo "Comprobación completada: el instalador puede trabajar sin Internet."
}

run_installer() {
    clear 2>/dev/null || true
    cat <<'EOF'
========================================
         DexOS Server Installer
========================================
Instalador offline con NetworkManager, mDNS y GRUB inteligente.
Puede usar un disco completo o coexistir con Windows/Linux.
EOF

    preflight
    wifi_assistant
    collect_identity
    choose_layout

    say "Resumen"
    echo "Servidor:     $mdns_name"
    echo "Usuario:      $admin_user"
    echo "Root por SSH: $ssh_root_login"
    echo "Zona:         $timezone"
    echo "Disco:        $disk"
    echo "Modo:         $install_mode"
    if [ "$install_mode" = coexist ]; then
        echo "Raíz a borrar: $root_part"
        echo "ESP conservada: ${efi_part:-ninguna}"
        echo "Otros sistemas: se conservarán y GRUB intentará detectarlos."
    else
        echo "ATENCIÓN: se borrará TODO el disco $disk."
    fi
    confirm "¿Iniciar la instalación?" || exit 0

    prepare_storage
    mount_target
    install_offline_packages
    write_target_config
    configure_boot

    say "Sincronizando datos"
    sync
    cleanup
    trap - EXIT HUP INT TERM
    echo
    echo "DexOS Server se instaló correctamente."
    echo "Nombre mDNS: $mdns_name"
    echo "Después de arrancar puedes cambiar el sistema predeterminado con: boot-order"
    echo "Retira el medio Live y reinicia."
}

case "${1:-}" in
    --wifi) wifi_assistant ;;
    --check) run_check ;;
    '') run_installer ;;
esac
```

### `server/boot-order`

```sh
#!/bin/sh
set -eu

CFG=/boot/grub/grub.cfg
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

[ "$(id -u)" -eq 0 ] || {
    if command -v doas >/dev/null 2>&1; then exec doas "$0" "$@"; fi
    echo "ERROR: ejecuta esta herramienta como root." >&2
    exit 1
}

[ -f "$CFG" ] || {
    echo "ERROR: no existe $CFG. Ejecuta grub-mkconfig primero." >&2
    exit 1
}

# GRUB generated by DexOS disables submenus, so the top-level menuentry order
# maps directly to the numeric saved_entry accepted by grub-set-default.
sed -n "s/^[[:space:]]*menuentry '\([^']*\)'.*/\1/p" "$CFG" > "$TMP"
[ -s "$TMP" ] || {
    echo "ERROR: no se encontraron entradas de arranque en $CFG." >&2
    exit 1
}

current=$(grub-editenv list 2>/dev/null | sed -n 's/^saved_entry=//p' | head -1 || true)

echo "DexOS Server - selección de arranque predeterminado"
echo
idx=1
while IFS= read -r title; do
    marker=' '
    zero=$((idx - 1))
    [ "$current" = "$zero" ] && marker='*'
    printf ' %s %d) %s\n' "$marker" "$idx" "$title"
    idx=$((idx + 1))
done < "$TMP"
count=$((idx - 1))

echo
printf 'Selecciona la entrada que arrancará por defecto [1-%s]: ' "$count"
IFS= read -r choice
case "$choice" in ''|*[!0-9]*) echo "Selección cancelada."; exit 0 ;; esac
[ "$choice" -ge 1 ] && [ "$choice" -le "$count" ] || {
    echo "Selección fuera de rango." >&2
    exit 1
}

selected=$((choice - 1))
grub-set-default "$selected"
title=$(sed -n "${choice}p" "$TMP")
echo "Predeterminado: $title"
echo "Índice GRUB guardado: $selected"
```

### `server/mkimage/mkimg.dexserver.sh`

```sh
profile_dexserver() {
    profile_standard
    profile_abbrev="dexserver"
    title="DexOS Server"
    desc="DexOS Server: ultra-light terminal-only Alpine Linux server with SSH, mDNS and Wi-Fi."
    arch="x86_64"
    image_name="DexOS-Server"
    output_filename="DexOS-Server-edge-x86_64.iso"
    hostname="dexos-server"
    apkovl="genapkovl-dexserver.sh"
    kernel_flavors="lts"
    kernel_firmware_packages="linux-firmware-realtek linux-firmware-rtlwifi linux-firmware-rtw88 linux-firmware-rtw89 linux-firmware-mediatek linux-firmware-ath6k linux-firmware-ath9k_htc linux-firmware-ath10k linux-firmware-ath11k linux-firmware-ath12k linux-firmware-brcm linux-firmware-cypress linux-firmware-qca linux-firmware-mwl8k linux-firmware-mwlwifi linux-firmware-libertas linux-firmware-ti-connectivity linux-firmware-rsi linux-firmware-wfx"
    boot_addons="amd-ucode intel-ucode"
    initrd_ucode="/boot/amd-ucode.img /boot/intel-ucode.img"
    syslinux_timeout=5
    syslinux_prompt=0
    apks="alpine-base alpine-conf busybox-extras ca-certificates tzdata doas \
        openssh openssh-server openssh-client openssl kbd-bkeymaps \
        avahi avahi-openrc dbus dbus-openrc eudev eudev-openrc \
        networkmanager networkmanager-openrc networkmanager-wifi networkmanager-cli \
        wpa_supplicant iw wireless-regdb \
        linux-firmware-realtek linux-firmware-rtlwifi linux-firmware-rtw88 linux-firmware-rtw89 \
        linux-firmware-mediatek linux-firmware-ath6k linux-firmware-ath9k_htc linux-firmware-ath10k \
        linux-firmware-ath11k linux-firmware-ath12k linux-firmware-brcm linux-firmware-cypress \
        linux-firmware-qca linux-firmware-mwl8k linux-firmware-mwlwifi linux-firmware-libertas \
        linux-firmware-ti-connectivity linux-firmware-rsi linux-firmware-wfx \
        util-linux e2fsprogs dosfstools \
        grub grub-bios grub-efi efibootmgr os-prober ntfs-3g \
        linux-lts"
}
```

### `server/mkimage/genapkovl-dexserver.sh`

```sh
#!/bin/sh
set -eu

HOSTNAME="${1:-dexos-server}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# The archive contains `.` itself. mktemp creates it as 0700; if preserved,
# Alpine applies that mode to the Live root and non-root daemons cannot traverse /.
chmod 0755 "$tmp"

mkdir -p \
  "$tmp/etc/ssh/sshd_config.d" \
  "$tmp/etc/avahi" \
  "$tmp/etc/NetworkManager/conf.d" \
  "$tmp/etc/NetworkManager/system-connections" \
  "$tmp/etc/apk" \
  "$tmp/etc/runlevels/sysinit" \
  "$tmp/etc/runlevels/default" \
  "$tmp/etc/runlevels/boot" \
  "$tmp/etc/runlevels/shutdown" \
  "$tmp/etc/profile.d" \
  "$tmp/usr/local/sbin" \
  "$tmp/usr/share/dexos"

printf '%s\n' "$HOSTNAME" > "$tmp/etc/hostname"
cat > "$tmp/etc/hosts" <<EOF
127.0.0.1 localhost localhost.localdomain
127.0.1.1 $HOSTNAME $HOSTNAME.localdomain
::1 localhost localhost.localdomain
EOF
cat > "$tmp/etc/apk/repositories" <<'EOF'
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
EOF
cat > "$tmp/etc/NetworkManager/conf.d/10-dexos-network.conf" <<'EOF'
[main]
plugins=keyfile
rc-manager=file
dns=default

[ifupdown]
managed=true
EOF
cat > "$tmp/etc/NetworkManager/system-connections/dexos-wired.nmconnection" <<'EOF'
[connection]
id=DexOS Wired
uuid=7ef3663e-bd07-4eb2-8cd6-2be94a6a6391
type=ethernet
autoconnect=true
autoconnect-priority=100

[ethernet]

[ipv4]
method=auto

[ipv6]
method=auto
addr-gen-mode=default

[proxy]
EOF
chmod 0600 "$tmp/etc/NetworkManager/system-connections/dexos-wired.nmconnection"
cat > "$tmp/etc/resolv.conf" <<'EOF'
# Fallback DNS; NetworkManager replaces this after DHCP/Wi-Fi connects.
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

# Packages in the ISO repository are not automatically installed in the Live.
# world makes nmcli, firmware and the disk installer available before networking.
cp /work/server/live-world.txt "$tmp/etc/apk/world"
sed -i -e 's/#.*$//' -e '/^[[:space:]]*$/d' "$tmp/etc/apk/world"
cp /work/server/packages.txt "$tmp/usr/share/dexos/server-packages.txt"

cat > "$tmp/etc/motd" <<'EOF'
DexOS Server
Ultra-light Alpine Linux server edition.

Install to disk: install
Wi-Fi assistant: install --wifi
Network tools: nmcli
SSH and Avahi start automatically.
EOF
cat > "$tmp/etc/issue" <<'EOF'
DexOS Server \n (Alpine Linux) \l
EOF
cat > "$tmp/etc/os-release" <<'EOF'
NAME="DexOS Server"
PRETTY_NAME="DexOS Server"
ID=dexos-server
ID_LIKE=alpine
VERSION_ID="edge"
VERSION="edge"
EOF
cat > "$tmp/etc/ssh/sshd_config.d/10-dexos-server.conf" <<'EOF'
PasswordAuthentication yes
PermitRootLogin yes
PermitEmptyPasswords no
UseDNS no
EOF
cat > "$tmp/etc/avahi/avahi-daemon.conf" <<'EOF'
[server]
use-ipv4=yes
use-ipv6=yes
[wide-area]
enable-wide-area=no
[publish]
publish-addresses=yes
publish-workstation=no
EOF
cat > "$tmp/etc/profile.d/00-dexos-path.sh" <<'EOF'
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EOF

cp /work/server/install "$tmp/usr/local/sbin/install"
cp /work/server/boot-order "$tmp/usr/local/sbin/boot-order"
chmod 0755 "$tmp/usr/local/sbin/install" "$tmp/usr/local/sbin/boot-order"

for svc in devfs dmesg udev udev-trigger udev-settle hwdrivers modloop; do
    ln -s "/etc/init.d/$svc" "$tmp/etc/runlevels/sysinit/$svc"
done
for svc in dbus networkmanager sshd avahi-daemon udev-postmount; do
    ln -s "/etc/init.d/$svc" "$tmp/etc/runlevels/default/$svc"
done
for svc in hostname modules sysctl bootmisc syslog; do
    ln -s "/etc/init.d/$svc" "$tmp/etc/runlevels/boot/$svc"
done
for svc in mount-ro killprocs savecache; do
    ln -s "/etc/init.d/$svc" "$tmp/etc/runlevels/shutdown/$svc"
done

# OpenSSH generates unique host keys when the Live boots; never bake keys into ISO.
rm -f "$tmp"/etc/ssh/ssh_host_* 2>/dev/null || true

# mkimage invokes this script from the section destination directory. Write the
# archive there (not inside $tmp, which is removed by the EXIT trap).
tar -c -C "$tmp" . | gzip -9n > "$HOSTNAME.apkovl.tar.gz"
```

### `server/packages.txt`

```text
# DexOS Server packages installed to disk by /usr/local/sbin/install.
alpine-base
alpine-conf
busybox-extras
ca-certificates
tzdata
doas
openssh
openssh-server
openssh-client
openssl
kbd-bkeymaps
avahi
avahi-openrc
dbus
dbus-openrc
eudev
eudev-openrc
networkmanager
networkmanager-openrc
networkmanager-wifi
networkmanager-cli
wpa_supplicant
iw
wireless-regdb
util-linux
e2fsprogs
dosfstools
grub
grub-bios
grub-efi
efibootmgr
os-prober
ntfs-3g
linux-lts
linux-firmware-realtek
linux-firmware-rtlwifi
linux-firmware-rtw88
linux-firmware-rtw89
linux-firmware-mediatek
linux-firmware-ath6k
linux-firmware-ath9k_htc
linux-firmware-ath10k
linux-firmware-ath11k
linux-firmware-ath12k
linux-firmware-brcm
linux-firmware-cypress
linux-firmware-qca
linux-firmware-mwl8k
linux-firmware-mwlwifi
linux-firmware-libertas
linux-firmware-ti-connectivity
linux-firmware-rsi
linux-firmware-wfx
```

### `server/live-world.txt`

```text
# Packages installed into the DexOS Server Live root.
alpine-base
alpine-conf
busybox-extras
ca-certificates
tzdata
doas
openssh
openssh-server
openssh-client
openssl
kbd-bkeymaps
avahi
avahi-openrc
dbus
dbus-openrc
eudev
eudev-openrc
networkmanager
networkmanager-openrc
networkmanager-wifi
networkmanager-cli
wpa_supplicant
iw
wireless-regdb
util-linux
e2fsprogs
dosfstools
grub
grub-bios
grub-efi
efibootmgr
linux-firmware-realtek
linux-firmware-rtlwifi
linux-firmware-rtw88
linux-firmware-rtw89
linux-firmware-mediatek
linux-firmware-ath6k
linux-firmware-ath9k_htc
linux-firmware-ath10k
linux-firmware-ath11k
linux-firmware-ath12k
linux-firmware-brcm
linux-firmware-cypress
linux-firmware-qca
linux-firmware-mwl8k
linux-firmware-mwlwifi
linux-firmware-libertas
linux-firmware-ti-connectivity
linux-firmware-rsi
linux-firmware-wfx
```

### `server/tests/test-server.sh`

```sh
#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PROFILE="$ROOT/server/mkimage/mkimg.dexserver.sh"
OVERLAY="$ROOT/server/mkimage/genapkovl-dexserver.sh"
INSTALLER="$ROOT/server/install"
BOOT_ORDER="$ROOT/server/boot-order"
LIVE_WORLD="$ROOT/server/live-world.txt"
TARGET_PACKAGES="$ROOT/server/packages.txt"
BUILD="$ROOT/server/build-dexos-server.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

sh -n "$INSTALLER"
sh -n "$BOOT_ORDER"
sh -n "$OVERLAY"
bash -n "$BUILD"
pass "sintaxis shell"

for file in "$LIVE_WORLD" "$TARGET_PACKAGES"; do
    [ -s "$file" ] || fail "lista vacía: $file"
done

for pkg in networkmanager networkmanager-openrc networkmanager-wifi networkmanager-cli eudev eudev-openrc openssh avahi avahi-openrc dbus dbus-openrc wpa_supplicant iw wireless-regdb; do
    grep -qx "$pkg" "$LIVE_WORLD" || fail "$pkg falta en Live world"
    grep -qx "$pkg" "$TARGET_PACKAGES" || fail "$pkg falta en sistema instalado"
done
grep -qx doas "$TARGET_PACKAGES" || fail "doas falta en sistema instalado"
for pkg in os-prober ntfs-3g; do
    grep -qx "$pkg" "$TARGET_PACKAGES" || fail "$pkg falta para detectar otros sistemas"
done
pass "red, SSH, Avahi, administración y dual boot presentes"

# Every explicit Live/installed package must exist in the ISO package repository profile.
for file in "$LIVE_WORLD" "$TARGET_PACKAGES"; do
    sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' "$file" | while IFS= read -r pkg; do
        grep -Fq "$pkg" "$PROFILE" || fail "$pkg no está incluido en el repositorio offline del perfil"
    done
done
pass "listas cubiertas por el repositorio offline"

for bad in xorg-server xfce4 lightdm firefox mesa-dri-gallium mesa-gl pipewire bluez pulseaudio vulkan-loader linux-firmware-amdgpu linux-firmware-i915 linux-firmware-nvidia linux-firmware-xe; do
    if grep -Fxq "$bad" "$LIVE_WORLD" || grep -Fxq "$bad" "$TARGET_PACKAGES"; then
        fail "paquete gráfico/no-server presente: $bad"
    fi
done
pass "sin stack gráfico, audio ni Bluetooth"

grep -Fq 'chmod 0755 "$tmp"' "$OVERLAY" || fail "el apkovl dejaría la raíz Live sin permisos de traversing"
grep -Fq 'cp /work/server/live-world.txt "$tmp/etc/apk/world"' "$OVERLAY" || fail "overlay no instala /etc/apk/world"
grep -Fq 'cp /work/server/install "$tmp/usr/local/sbin/install"' "$OVERLAY" || fail "overlay no instala el comando install"
grep -Fq 'cp /work/server/boot-order "$tmp/usr/local/sbin/boot-order"' "$OVERLAY" || fail "overlay no instala boot-order"
grep -Fq 'udev udev-trigger udev-settle' "$OVERLAY" || fail "coldplug udev no habilitado en Live"
grep -Fq 'networkmanager sshd avahi-daemon udev-postmount' "$OVERLAY" || fail "servicios Server no habilitados en Live"
grep -Fq 'rc-manager=file' "$OVERLAY" || fail "NetworkManager Live no administra resolv.conf"
grep -Fq 'dexos-wired.nmconnection' "$OVERLAY" || fail "Live no tiene Ethernet DHCP automático"
grep -Fq 'https://dl-cdn.alpinelinux.org/alpine/edge/main' "$OVERLAY" || fail "repositorio main falta en Live"
grep -Fq 'https://dl-cdn.alpinelinux.org/alpine/edge/community' "$OVERLAY" || fail "repositorio community falta en Live"
pass "overlay Live"

grep -Fq 'apk add --simulate --no-network --repositories-file /dev/null' "$INSTALLER" || fail "preflight offline estricto ausente"
grep -Fq 'apk add --root "$TARGET"' "$INSTALLER" || fail "instalación apk --root ausente"
grep -Fq -- '--no-network --repositories-file /dev/null' "$INSTALLER" || fail "instalación no aísla los repositorios online"
grep -Fq -- '--repository "$repo"' "$INSTALLER" || fail "instalación no usa el repositorio de la ISO"
grep -Fq 'nmcli device wifi connect' "$INSTALLER" || fail "asistente Wi-Fi no usa nmcli"
grep -Fq 'udev udev-trigger udev-settle' "$INSTALLER" || fail "coldplug udev no configurado en sistema instalado"
grep -Fq 'networkmanager sshd avahi-daemon udev-postmount' "$INSTALLER" || fail "servicios instalados no configurados"
grep -Fq 'rc-manager=file' "$INSTALLER" || fail "NetworkManager instalado no administra resolv.conf"
grep -Fq 'dexos-wired.nmconnection' "$INSTALLER" || fail "sistema instalado no tiene Ethernet DHCP automático"
grep -Fq '/etc/apk/repositories' "$INSTALLER" || fail "repositorios instalados no configurados"
grep -Fq '/sbin/mkinitfs' "$INSTALLER" || fail "initramfs no se genera explícitamente"
grep -Fq 'root=UUID=$root_uuid' "$INSTALLER" || fail "GRUB no fija root por UUID"
grep -Fq 'system-connections' "$INSTALLER" || fail "perfiles NetworkManager no se preservan"
grep -Fq 'Nombre del servidor/mDNS' "$INSTALLER" || fail "falta nombre .local inteligente"
grep -Fq 'case "$name" in *.local)' "$INSTALLER" || fail "no se evita duplicar .local"
grep -Fq 'Enter = usar la de $admin_user' "$INSTALLER" || fail "root no puede heredar contraseña"
grep -Fq 'PermitRootLogin $ssh_root_login' "$INSTALLER" || fail "root SSH no es configurable"
grep -Fq 'Coexistir con otro sistema' "$INSTALLER" || fail "falta modo coexistencia"
grep -Fq 'select_root_partition' "$INSTALLER" || fail "falta selector de partición raíz"
grep -Fq 'select_efi_partition' "$INSTALLER" || fail "falta selector de ESP"
grep -Fq 'GRUB_DISABLE_OS_PROBER=false' "$INSTALLER" || fail "os-prober no está habilitado en GRUB"
grep -Fq '/usr/bin/os-prober' "$INSTALLER" || fail "otros sistemas no se detectan"
grep -Fq 'ensure_block_node' "$INSTALLER" || fail "falta reparación robusta de nodos de partición"
grep -Fq 'mknod "$path"' "$INSTALLER" || fail "no se corrige el race de /dev/vda3"
if grep -Fq 'BORRAR $disk' "$INSTALLER"; then fail "el instalador aún exige escribir BORRAR"; fi
if grep -Fq 'setup-alpine' "$INSTALLER"; then fail "el instalador propio depende de setup-alpine"; fi
grep -Fq 'grub-set-default' "$BOOT_ORDER" || fail "boot-order no cambia el arranque predeterminado"
pass "flujo del instalador terminal, coexistencia y boot-order"

if grep -R -E 'Gtk|py3-gobject|xorg-server|xfce4|lightdm' "$ROOT/server" --exclude='test-server.sh' >/dev/null 2>&1; then
    fail "dependencia gráfica detectada dentro de server/"
fi
pass "server/ no depende de GUI"

echo "DexOS Server static tests: PASS"
```


# APÉNDICE B — Manifiesto exacto de APK del ISO validado

Este manifiesto fue extraído de:

```text
out/DexOS-Server-edge-x86_64.iso
SHA256=aab605a18285d3dccb9d421917b88154477dd599427401705930dc0752a58c1a
```

Contiene las 176 entradas `package=version` del `APKINDEX` embebido. Úsalo para detectar deriva del repositorio `edge`.

```text
agetty-openrc=0.63.2-r0
agetty=2.42.3-r1
alpine-base=3.25.0_alpha20260805-r0
alpine-baselayout-data=3.7.2-r1
alpine-baselayout=3.7.2-r1
alpine-conf=3.22.0-r0
alpine-keys=2.6-r0
alpine-release=3.25.0_alpha20260805-r0
apk-tools=3.0.8-r0
avahi-libs=0.9_rc5-r0
avahi-openrc=0.9_rc5-r0
avahi=0.9_rc5-r0
blkid=2.42.3-r1
bridge=1.5-r5
brotli-libs=1.2.0-r1
busybox-binsh=1.38.0-r4
busybox-extras=1.38.0-r4
busybox-mdev-openrc=1.38.0-r4
busybox-openrc=1.38.0-r4
busybox-suid=1.38.0-r4
busybox=1.38.0-r4
c-ares=1.34.8-r0
ca-certificates-bundle=20260611-r0
ca-certificates=20260611-r0
cfdisk=2.42.3-r1
cryptsetup-libs=2.8.7-r0
dbus-daemon-launch-helper=1.16.2-r3
dbus-libs=1.16.2-r3
dbus-openrc=1.16.2-r3
dbus=1.16.2-r3
device-mapper-libs=2.03.35-r6
device-mapper-udev=2.03.35-r6
device-mapper=2.03.35-r6
dmesg=2.42.3-r1
doas=6.8.2-r8
dosfstools=4.2-r2
e2fsprogs-libs=1.47.4-r0
e2fsprogs=1.47.4-r0
efibootmgr=18-r2
efivar-libs=39-r1
eudev-libs=3.2.14-r7
eudev-openrc=3.2.14-r7
eudev=3.2.14-r7
findmnt=2.42.3-r1
flock=2.42.3-r1
fstrim=2.42.3-r1
fuse3-libs=3.18.2-r0
glib=2.88.3-r0
grub-bios=2.14-r1
grub-efi=2.14-r1
grub-mount=2.14-r1
grub=2.14-r1
hexdump=2.42.3-r1
ifupdown-ng-wifi=0.13.0-r0
ifupdown-ng=0.13.0-r0
iw=6.17-r0
jansson=2.15.0-r0
json-c=0.19-r1
kbd-bkeymaps=2.8.0-r0
kmod-libs=34.2-r1
kmod=34.2-r1
lddtree=1.27-r0
libapk=3.0.8-r0
libblkid=2.42.3-r1
libbpf=1.7.0-r1
libcap-ng=0.8.5-r2
libcap2=2.78-r0
libcom_err=1.47.4-r0
libcrypto3=3.5.8-r0
libcurl=8.22.0-r0
libdaemon=0.14-r6
libeconf=0.8.4-r0
libedit=20260508.3.1-r1
libelf=0.195-r0
libelogind=255.24-r0
libevent=2.1.13-r0
libexpat=2.8.4-r0
libfdisk=2.42.3-r1
libffi=3.8.0-r0
libidn2=2.3.8-r0
libintl=1.0-r0
libmount=2.42.3-r1
libncursesw=6.6_p20260822-r0
libndp=1.9-r1
libnl3=3.11.0-r0
libnm=1.58.0-r0
libpsl=0.21.5-r3
libselinux=3.11-r0
libsmartcols=2.42.3-r1
libssl3=3.5.8-r0
libunistring=1.4.2-r0
libuuid=2.42.3-r1
linux-firmware-ath10k=20260810-r0
linux-firmware-ath11k=20260810-r0
linux-firmware-ath12k=20260810-r0
linux-firmware-ath6k=20260810-r0
linux-firmware-ath9k_htc=20260810-r0
linux-firmware-brcm=20260810-r0
linux-firmware-cypress=20260810-r0
linux-firmware-libertas=20260810-r0
linux-firmware-mediatek=20260810-r0
linux-firmware-mwl8k=20260810-r0
linux-firmware-mwlwifi=20260810-r0
linux-firmware-qca=20260810-r0
linux-firmware-realtek=20260810-r0
linux-firmware-rsi=20260810-r0
linux-firmware-rtlwifi=20260810-r0
linux-firmware-rtw88=20260810-r0
linux-firmware-rtw89=20260810-r0
linux-firmware-synaptics=20260810-r0
linux-firmware-ti-connectivity=20260810-r0
linux-firmware-wfx=20260810-r0
linux-lts=6.18.50-r0
linux-pam=1.7.1-r3
logger=2.42.3-r1
losetup=2.42.3-r1
lsblk=2.42.3-r1
lscpu=2.42.3-r1
mcookie=2.42.3-r1
mdev-conf=4.10-r0
mkinitfs=3.14.0-r0
mount=2.42.3-r1
musl-fts=1.2.7-r7
musl-utils=1.2.6-r3
musl=1.2.6-r3
ncurses-terminfo-base=6.6_p20260822-r0
networkmanager-cli=1.58.0-r0
networkmanager-openrc=1.58.0-r0
networkmanager-wifi=1.58.0-r0
networkmanager=1.58.0-r0
nghttp2-libs=1.70.0-r0
nspr=4.38.2-r0
nss=3.127-r0
ntfs-3g-libs=2026.7.7-r0
ntfs-3g=2026.7.7-r0
openrc-user=0.63.2-r0
openrc=0.63.2-r0
openssh-client-common=10.5_p1-r1
openssh-client-default=10.5_p1-r1
openssh-keygen=10.5_p1-r1
openssh-server-common-openrc=10.5_p1-r1
openssh-server-common=10.5_p1-r1
openssh-server=10.5_p1-r1
openssh-sftp-server=10.5_p1-r1
openssh=10.5_p1-r1
openssl=3.5.8-r0
os-prober=1.85-r0
partx=2.42.3-r1
pcre2=10.48-r0
pcsc-lite-libs=2.5.1-r0
popt=1.19-r4
readline=8.3.3-r1
runuser=2.42.3-r1
scanelf=1.3.9-r1
setarch=2.42.3-r1
setpriv=2.42.3-r1
sfdisk=2.42.3-r1
skalibs-libs=2.15.1.0-r0
sqlite-libs=3.53.4-r0
ssl_client=1.38.0-r4
tzdata=2026c-r0
udev-init-scripts-openrc=35-r1
udev-init-scripts=35-r1
umount=2.42.3-r1
util-linux-misc=2.42.3-r1
util-linux-openrc=2.42.3-r1
util-linux=2.42.3-r1
utmps-libs=0.1.3.4-r0
uuidgen=2.42.3-r1
wipefs=2.42.3-r1
wireless-regdb=2025.10.07-r0
wpa_supplicant-openrc=2.11-r4
wpa_supplicant=2.11-r4
xz-libs=5.8.3-r0
zlib=1.3.2-r0
zstd-libs=1.5.7-r2
```

# APÉNDICE C — Comandos de verificación rápida

```bash
# Proyecto
git rev-parse HEAD
git status --short

# Aports
git -C aports rev-parse HEAD
git -C aports status --short

# Root Alpine
proot -0 -R alpine-root /bin/cat /etc/alpine-release
proot -0 -R alpine-root /sbin/apk --version

# Fuentes
sha256sum \
  server/build-dexos-server.sh \
  server/install \
  server/boot-order \
  server/mkimage/mkimg.dexserver.sh \
  server/mkimage/genapkovl-dexserver.sh \
  server/packages.txt \
  server/live-world.txt \
  server/tests/test-server.sh

# Build
./server/tests/test-server.sh
./server/build-dexos-server.sh
sha256sum out/DexOS-Server-edge-x86_64.iso
```

Referencia esperada de la ISO documentada:

```text
aab605a18285d3dccb9d421917b88154477dd599427401705930dc0752a58c1a  out/DexOS-Server-edge-x86_64.iso
```

---

## Cierre

La idea clave es separar claramente **fuente**, **root de build**, **aports**, **overlay Live**, **repo offline**, **instalador a disco** y **pruebas de boot**. La mayoría de los fallos encontrados durante el desarrollo ocurrieron cuando una de esas capas se asumió implícitamente: un APK presente pero no instalado en Live, un módulo presente pero modloop no montado, un repo correcto pero DNS inexistente, una partición existente en sysfs pero aún no en `/dev`, o un apkovl generado en un directorio que luego se eliminó.

Si mantienes las versiones fijadas, conservas las fuentes y pruebas cada capa por separado, crear una ISO Alpine personalizada deja de ser un proceso frágil y se vuelve reproducible y auditable.
