#!/usr/bin/env bash
# Build the kernel on its own, for a fast iteration cycle.
#
# The full image takes between 20 and 90 minutes. The kernel alone takes
# about 15, and that is the cycle to use while chasing a patch.
#
#   ./25-build-kernel.sh              fetch the source and build
#   ./25-build-kernel.sh --no-fetch   build what is already there
#   ./25-build-kernel.sh --clean      throw the build tree away
#
# The result goes to build/out/kernel/ and can be compared with the kernel
# that is in the image.
set -eu
. "$(dirname -- "$0")/env.sh"
. "$(dirname -- "$0")/lib.sh"

FETCH=1
CLEAN=0
for a in "$@"; do
    case "$a" in
        --no-fetch) FETCH=0 ;;
        --clean)    CLEAN=1 ;;
    esac
done

KSRC=$BUILD/out/kernel/src
KSTAGE=$BUILD/out/kernel/staging
KBUILD=$BUILD/out/kernel/build
KVER=7.1_rc3
KTAG=v$KVER
KURL=https://github.com/sm7150-mainline/linux
KTARBALL=$BUILD/out/kernel/linux-postmarketos-qcom-sm7150-v$KVER.tar.gz

mkdir -p "$BUILD/out/kernel"

if [ "$CLEAN" = "1" ]; then
    say "a limpar a árvore do kernel"
    rm -rf "$KSRC" "$KBUILD" "$KSTAGE"
    ok "limpo"
    exit 0
fi

# ---------------------------------------------------------------------------
# The source.

if [ "$FETCH" = "1" ]; then
    say "a obter o fonte do kernel ($KTAG)"
    if [ ! -s "$KTARBALL" ]; then
        curl -fL --progress-bar -o "$KTARBALL.tmp" \
            "$KURL/archive/$KTAG.tar.gz" || die "não foi possível descarregar $KTAG"
        mv "$KTARBALL.tmp" "$KTARBALL"
    fi
    ok "fonte pronto ($(du -h "$KTARBALL" | cut -f1))"

    if [ ! -d "$KSRC" ]; then
        say "a extrair"
        mkdir -p "$KSRC"
        tar -xf "$KTARBALL" -C "$KSRC" --strip-components=1
        ok "extraído"
    fi
else
    [ -d "$KSRC" ] || die "não há fonte em $KSRC — corra sem --no-fetch"
fi

# ---------------------------------------------------------------------------
# The patches.
#
# The 140 patches of surya-pmos/kernel, applied in order. The Subject:
# counters were renormalised by 20-overlay.sh, but this works on a copy
# anyway, so it does not depend on that.

say "a aplicar os 140 patches"
cd "$KSRC"

applied=0
for p in $PROJECT/surya-pmos/kernel/*.patch; do
    name=$(basename "$p")
    if git apply --check "$p" 2>/dev/null; then
        git apply "$p" || die "falhou ao aplicar $name"
        applied=$((applied + 1))
    elif patch -p1 --dry-run --silent < "$p" >/dev/null 2>&1; then
        patch -p1 --silent < "$p" || die "falhou ao aplicar $name"
        applied=$((applied + 1))
    else
        die "o patch $name não se aplica — a árvore já está modificada?"
    fi
done
ok "$applied patches aplicados"

# The configuration.
cp "$PROJECT/surya-pmos/kernel/config-postmarketos-qcom-sm7150.aarch64" .config
ok "configuração copiada"

# ---------------------------------------------------------------------------
# The build.
#
# LOCALVERSION= is **mandatory**, and this is the reason the kernel and the
# modules have to be built together. Without it, setlocalversion appends a
# '+' to the release, and then the module directory does not match the
# kernel that is running. A .scmversion file that is empty is not enough:
# the variable itself has to be set.
#
# The kernel and the modules have to come from the same build. Installing a
# new vmlinuz with the old modules gives a phone that boots, reaches greetd
# and dies silently at about 25 seconds, with no Oops and nothing in
# ramoops: CONFIG_MODVERSIONS is off, and nothing notices the mismatch.

say "a compilar o kernel"
echo "  isto demora cerca de 15 minutos"
echo

make -C "$KSRC" LLVM=1 ARCH=arm64 LOCALVERSION= \
     -j"$(nproc)" vmlinuz.efi modules 2>&1 | tee "$LOG/kernel.log" \
    || die "a compilação falhou — ver $LOG/kernel.log"

# ---------------------------------------------------------------------------
# The staging: the kernel and the modules, together, ready to be installed.

say "a preparar a instalação"
rm -rf "$KSTAGE"
mkdir -p "$KSTAGE"

make -C "$KSRC" LLVM=1 ARCH=arm64 LOCALVERSION= INSTALL_MOD_STRIP=1 \
     INSTALL_MOD_PATH="$KSTAGE" modules_install 2>&1 | tail -3

cp "$KSRC/arch/arm64/boot/Image" "$KSTAGE/" 2>/dev/null || true
cp "$KSRC/arch/arm64/boot/vmlinuz.efi" "$KSTAGE/" 2>/dev/null || true

REL=$(cat "$KSRC/include/config/kernel.release" 2>/dev/null || echo "?")
ok "release: $REL"
case "$REL" in
    *+) bad "o release tem um '+' — o LOCALVERSION= não chegou ao build" ;;
    *)  ok "o release está limpo" ;;
esac

# The modules have to be in a directory named after the release.
if [ -d "$KSTAGE/lib/modules/$REL" ]; then
    n=$(find "$KSTAGE/lib/modules/$REL" -name '*.ko*' | wc -l)
    ok "$n módulos em lib/modules/$REL — a mesma compilação do kernel"
else
    bad "lib/modules/$REL não existe"
    echo "  disponível: $(ls "$KSTAGE/lib/modules" 2>/dev/null | tr '\n' ' ')"
fi

# The size, with and without the strip, for comparison.
du -sh "$KSTAGE/lib/modules/$REL" 2>/dev/null | sed 's/^/  /'

say "pronto"
echo "  kernel e módulos: $KSTAGE"
echo "  release:          $REL"
echo
echo "Para comparar com o kernel da imagem:"
echo "    $BUILD/50-verify.sh"
echo
echo "Para instalar no telefone, a partir do chroot do pmbootstrap:"
echo "    # o caminho normal é copiar para a raiz montada do telefone"
echo "    # e reiniciar; o pmbootstrap tem o comando certo para isto:"
echo "    $PMB flasher flash_kernel"
