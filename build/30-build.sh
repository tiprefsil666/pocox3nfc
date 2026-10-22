#!/usr/bin/env bash
# Build the image.
#
# This drives pmbootstrap through its whole cycle: the configuration, the
# checksums, and the install that produces the image.
#
#   ./30-build.sh                the whole thing
#   ./30-build.sh --config       only the configuration
#   ./30-build.sh --checksum     only the checksums
#   ./30-build.sh --install      only the install
#   ./30-build.sh --no-image     install into the chroot, without an image
#
# Why the configuration is written by hand
# ----------------------------------------
#
# This pmbootstrap is the 3.12.1, whose `init` is **interactive**: it asks
# for the work path, the pmaports path, the channel, the device, the
# keymap, the user, the UI, the service manager, the timezone, the locale,
# the hostname, the SSH keys and the extra packages — fourteen questions,
# every one of them able to be answered wrong by a script.
#
# The configuration is a plain INI file, so this script writes it directly
# and the build never has to be answered. It also uses its own config file
# (`build/out/pmbootstrap_v3.cfg`) instead of the global one in
# `~/.config/`, so that this project cannot disturb another one — and so
# that the settings of the build are recorded with it.
#
# The work folder is created here too, with the version marker that
# `init` would have written. The chroot itself is created later, when the
# first package is built.
set -eu
. "$(dirname -- "$0")/env.sh"
. "$(dirname -- "$0")/lib.sh"

STEP=${1:-all}

mkdir -p "$LOG" "$OUT"

PMB_CFG=$OUT/pmbootstrap_v3.cfg

# ---------------------------------------------------------------------------
# The configuration.

do_config() {
    say "a configurar o pmbootstrap"
    echo "  device:  $DEVICE"
    echo "  kernel:  $KERNEL"
    echo "  ui:      $UI"
    echo "  work:    $WORK"
    echo "  aports:  $PMAPORTS"
    echo "  config:  $PMB_CFG"
    echo

    # `work` and `aports` have to be absolute: pmbootstrap stores them in
    # its configuration and uses them in every later command, and a
    # relative path breaks half way through.
    #
    # `build_default_device_arch False` matters: this pmbootstrap builds
    # the device package for the host's architecture by default, which is
    # wrong for an arm64 target.
    cat > "$PMB_CFG" <<EOF
[pmbootstrap]
aports = $PMAPORTS
device = $DEVICE
kernel = $KERNEL
ui = $UI
work = $WORK
build_default_device_arch = False
hostname = $PMOS_HOSTNAME
user = $USER_NAME
timezone = $TIMEZONE
locale = $LOCALE
keymap = $KEYMAP
extra_packages = none
boot_size = 512
EOF
    ok "configuração escrita em $PMB_CFG"

    # The work folder, with the version marker that `pmbootstrap init`
    # would have written. Without it, every command complains that the
    # folder needs migrating.
    mkdir -p "$WORK"
    if [ ! -f "$WORK/version" ]; then
        echo "8" > "$WORK/version"
        ok "work folder preparado em $WORK"
    fi

    # Check that pmbootstrap agrees with what was written.
    say "o que o pmbootstrap leu"
    $PMB_NOSUDO status 2>&1 | sed 's/^/  /' || warn "o status falhou"
    echo
}

# ---------------------------------------------------------------------------
# The checksums.

do_checksum() {
    say "a calcular as checksums"
    # The sources have to be downloaded and hashed before the build. The
    # four packages are the ones that were overlaid.
    $PMB checksum "$OVERLAY_KERNEL" "$OVERLAY_LIBCAMERA" \
                  "$OVERLAY_LIBQMI" "$OVERLAY_HEXAGON" 2>&1 \
        | tee "$LOG/checksum.log"

    # pmbootstrap leaves the chroot mounted after a checksum, and the next
    # build then fails with:
    #   "Failed to umount ... /mnt/pmbootstrap/packages"
    # This one command is the difference between a build that works and one
    # that fails halfway through with an unhelpful error.
    say "a desmontar o chroot (senão o build seguinte falha)"
    $PMB shutdown 2>&1 | tee -a "$LOG/checksum.log" \
        || warn "o shutdown falhou, pode ser inofensivo"

    ok "checksums prontas"
}

# ---------------------------------------------------------------------------
# The install.

do_install() {
    say "a construir a imagem"
    echo "  isto demora entre 20 e 90 minutos, conforme a máquina"
    echo

    if [ "$NO_IMAGE" = "1" ]; then
        $PMB install --no-image 2>&1 | tee "$LOG/install.log"
    else
        $PMB install 2>&1 | tee "$LOG/install.log"
    fi

    ok "imagem construída"
}

# ---------------------------------------------------------------------------

case "$STEP" in
    --config)   do_config ;;
    --checksum) do_checksum ;;
    --install)  do_install ;;
    --no-image) NO_IMAGE=1; do_install ;;
    all)
        do_config
        do_checksum
        do_install
        ;;
    *) die "opção desconhecida: $STEP" ;;
esac

# ---------------------------------------------------------------------------
# Where the result is, and what it is made of.

say "resultado"
if [ -d "$WORK/images" ]; then
    ls -lh "$WORK/images"/*.img 2>/dev/null || true
    echo
    for img in "$WORK"/images/*.img; do
        [ -e "$img" ] || continue
        echo "  $(basename "$img")  $(sha256sum "$img" | cut -c1-16)..."
    done
    echo
    echo "  imagens em: $WORK/images"
else
    warn "não há directório de imagens — o install pode ter falhado"
    echo "  ver $LOG/install.log"
fi

# Record what was built.
{
    echo "device:     $DEVICE"
    echo "kernel:     $KERNEL"
    echo "ui:         $UI"
    echo "hostname:   $PMOS_HOSTNAME"
    echo "built:      $(date -Is)"
    [ -d "$PMAPORTS/.git" ] && echo "pmaports:   $(git -C "$PMAPORTS" rev-parse HEAD)"
} | tee "$MANIFEST"

echo
ok "pronto"
