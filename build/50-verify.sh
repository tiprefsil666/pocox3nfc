#!/usr/bin/env bash
# Check that what was built is what was expected.
#
# The important check is the kernel: the image has to carry the same kernel
# and the same modules, from the same build. A mismatched pair gives a phone
# that boots, reaches greetd, and dies silently at about 25 seconds, with no
# Oops and nothing in ramoops — because CONFIG_MODVERSIONS is off and nothing
# notices the mismatch.
#
#   ./50-verify.sh          check the build
#   ./50-verify.sh --device <host>   also check a running phone over ssh
set -eu
. "$(dirname -- "$0")/env.sh"
. "$(dirname -- "$0")/lib.sh"

DEVICE_HOST=${2:-}

fail=0
note() { printf '%s%s%s\n' "$C_BOLD" "$*" "$C_RESET"; }
bad()  { printf '%sFALHA%s %s\n' "$C_RED" "$C_RESET" "$*"; fail=$((fail + 1)); }
good() { printf '%s ok %s %s\n' "$C_GREEN" "$C_RESET" "$*"; }

IMAGES=$WORK/images

say "as imagens"
if [ -d "$IMAGES" ]; then
    for img in "$IMAGES"/*.img; do
        [ -e "$img" ] || continue
        note "  $(basename "$img")  $(du -h "$img" | cut -f1)  $(sha256sum "$img" | cut -c1-16)..."
    done
    [ -f "$IMAGES/rootfs.img" ] && good "rootfs.img presente" || bad "rootfs.img falta"
else
    bad "não há imagens em $IMAGES"
fi
echo

# ---------------------------------------------------------------------------
# The kernel inside the image.

say "o kernel na imagem"

KERNEL_IN_IMAGE=""
if [ -f "$IMAGES/boot.img" ]; then
    # The kernel is in the boot partition, at the offset the bootimg header
    # points to. Rather than parse it, look for the kernel's own markers.
    if grep -qa 'Linux version' "$IMAGES/boot.img" 2>/dev/null; then
        good "o boot.img tem uma string de versão do kernel"
        KERNEL_IN_IMAGE=$(strings -a "$IMAGES/boot.img" 2>/dev/null \
            | grep -m1 -oE 'Linux version [0-9][^ ]*' || true)
        [ -n "$KERNEL_IN_IMAGE" ] && note "  $KERNEL_IN_IMAGE"
    else
        bad "o boot.img não tem uma string de versão do kernel"
    fi
else
    warn "não há boot.img — a imagem pode só ter a raiz"
fi
echo

# ---------------------------------------------------------------------------
# The modules and the kernel have to agree.

say "kernel e módulos"

# The release the kernel build produces. LOCALVERSION= is what keeps the
# '+' out of it; without it the module directory does not match and the
# phone boots into nothing.
if [ -n "$KERNEL_IN_IMAGE" ]; then
    rel=$(echo "$KERNEL_IN_IMAGE" | awk '{print $3}')
    echo "  release: $rel"
    case "$rel" in
        *+) bad "o release tem um '+' — falta LOCALVERSION= no build do kernel" ;;
        *)  good "o release está limpo (sem '+')" ;;
    esac
else
    warn "sem release para verificar"
fi

# The module directory inside the rootfs.
MODDIR=
if [ -f "$IMAGES/rootfs.img" ]; then
    for d in $(sudo losetup -j "$IMAGES/rootfs.img" 2>/dev/null | cut -d: -f1); do
        MODDIR=$(sudo find "/mnt/$(basename "$d")" -maxdepth 5 -type d -name 'lib/modules' 2>/dev/null | head -1)
        [ -n "$MODDIR" ] && break
    done
fi
if [ -n "$MODDIR" ]; then
    good "módulos em $MODDIR"
    ls "$MODDIR" 2>/dev/null | while read -r d; do
        echo "    $d"
    done
    # The module directory has to be named after the kernel release.
    if [ -n "$KERNEL_IN_IMAGE" ]; then
        rel=$(echo "$KERNEL_IN_IMAGE" | awk '{print $3}')
        if [ -d "$MODDIR/$rel" ]; then
            good "lib/modules/$rel existe — o kernel e os módulos são do mesmo build"
        else
            bad "lib/modules/$rel não existe (há: $(ls "$MODDIR" | tr '\n' ' '))"
        fi
    fi
    sudo umount -l "$MODDIR" 2>/dev/null || true
else
    warn "não foi possível montar a rootfs para ver os módulos"
fi
echo

# ---------------------------------------------------------------------------
# The packages that were overlaid.

say "os pacotes sobrepostos"

KVER=$(grep -m1 '^pkgver=' "$KERNEL_PKG_DIR/APKBUILD" 2>/dev/null | cut -d= -f2)
KREL=$(grep -m1 '^pkgrel=' "$KERNEL_PKG_DIR/APKBUILD" 2>/dev/null | cut -d= -f2)
if [ -n "$KVER" ]; then
    note "  linux-$KERNEL $KVER-$KREL"
    # The release and the modules have to agree: r93 is the first one with
    # the voice capture switch, and the device configuration refuses to work
    # with anything older.
    if [ -n "$KREL" ] && [ "$KREL" -lt 93 ] 2>/dev/null; then
        warn "o pkgrel é $KREL; a configuração do dispositivo exige 93 ou mais"
    fi
else
    warn "não foi possível ler o APKBUILD do kernel"
fi

for p in libcamera libqmi hexagonrpcd; do
    if [ -f "$PMAPORTS/temp/$p/APKBUILD" ]; then
        v=$(grep -m1 '^pkgver=' "$PMAPORTS/temp/$p/APKBUILD" | cut -d= -f2)
        r=$(grep -m1 '^pkgrel=' "$PMAPORTS/temp/$p/APKBUILD" | cut -d= -f2)
        good "$p $v-$r"
    else
        bad "$p não está em temp/"
    fi
done
echo

# ---------------------------------------------------------------------------
# A running phone.

if [ -n "$DEVICE_HOST" ]; then
    say "o telefone em $DEVICE_HOST"
    rel=$(ssh "$DEVICE_HOST" uname -r 2>/dev/null || echo "")
    if [ -n "$rel" ]; then
        note "  uname -r: $rel"
        case "$rel" in
            *+) bad "o release tem um '+' — o build do kernel foi feito sem LOCALVERSION=" ;;
            *)  good "o release está limpo" ;;
        esac
        ssh "$DEVICE_HOST" 'ls /lib/modules/' 2>/dev/null | while read -r d; do
            note "    /lib/modules/$d"
        done
        if ssh "$DEVICE_HOST" "test -d /lib/modules/$rel" 2>/dev/null; then
            good "os módulos instalados correspondem ao kernel que está a correr"
        else
            bad "os módulos instalados NÃO correspondem ao kernel que está a correr"
        fi
    else
        bad "não foi possível falar com o telefone"
    fi
    echo
fi

# ---------------------------------------------------------------------------

if [ "$fail" -eq 0 ]; then
    ok "tudo verificado"
    exit 0
else
    printf '%s%s verificação(ões) falharam%s\n' "$C_RED" "$fail" "$C_RESET"
    exit 1
fi
