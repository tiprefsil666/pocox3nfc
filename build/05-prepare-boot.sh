#!/usr/bin/env bash
# Get the two things the phone needs before it can boot postmarketOS, and that
# the image build does not produce:
#
#   - the u-boot for this phone's panel
#   - the empty vbmeta images that turn verified boot off
#
#   ./05-prepare-boot.sh              fetch or re-fetch
#   ./05-prepare-boot.sh --panel tianma
set -eu
. "$(dirname -- "$0")/env.sh"
. "$(dirname -- "$0")/lib.sh"

PANEL=${PANEL:-huaxing}
if [ "${1:-}" = "--panel" ]; then PANEL=$2; fi

BOOTDIR=$PROJECT/postmarketos/prebuilt
UBOOT_URL=https://github.com/sm7150-mainline/u-boot/releases/latest/download/u-boot-sm7150-xiaomi-surya-$PANEL.img
UBOOT=$BOOTDIR/u-boot-sm7150-xiaomi-surya-$PANEL.img

mkdir -p "$BOOTDIR" "$OUT"

say "u-boot para o painel $PANEL"

# Which panel is this phone? The stock Android build.prop says so.
if [ -f "$PROJECT/android/extracted/rootfs/vendor/build.prop" ]; then
    model=$(grep -E 'ro.product.(model|device)' "$PROJECT/android/extracted/rootfs/vendor/build.prop" | head -2)
    echo "  $model"
fi

if [ -s "$UBOOT" ]; then
    ok "já está em $UBOOT ($(du -h "$UBOOT" | cut -f1))"
else
    which_of curl >/dev/null 2>&1 || die "sem curl"
    say "a descarregar"
    curl -fL --progress-bar -o "$UBOOT.tmp" "$UBOOT_URL" \
        || die "não foi possível descarregar $UBOOT_URL"
    mv "$UBOOT.tmp" "$UBOOT"
    ok "descarregado ($(du -h "$UBOOT" | cut -f1))"
fi

# Record which release it came from, so a phone that boots can be traced back
# to the exact bootloader.
curl -fsSL https://api.github.com/repos/sm7150-mainline/u-boot/releases/latest \
    2>/dev/null | grep '"tag_name"' | head -1 | cut -d'"' -f4 > "$OUT/uboot-release.txt" || true
[ -s "$OUT/uboot-release.txt" ] && ok "release $(cat "$OUT/uboot-release.txt")"

# ---------------------------------------------------------------------------
# The empty vbmeta.
#
# Android Verified Boot has to be off. Do not hunt for the stock vbmeta:
# generate an empty one. avbtool is Apache-2.0 and is a single file.
#
# The same image goes to both the vbmeta and the vbmeta_system partition.

say "vbmeta vazio"

AVBTOOL=$BOOTDIR/avbtool.py
if [ ! -s "$AVBTOOL" ]; then
    which_of curl >/dev/null 2>&1 || die "sem curl"
    which_of base64 >/dev/null 2>&1 || die "sem base64"
    # The official source. The GitHub mirror does not exist, and the
    # googlesource one serves the file base64-encoded.
    curl -sfL "https://android.googlesource.com/platform/external/avb/+/refs/heads/main/avbtool.py?format=TEXT" \
        | base64 -d > "$AVBTOOL" || die "não foi possível descarregar o avbtool"
    chmod +x "$AVBTOOL"
    ok "avbtool descarregado ($(wc -l < "$AVBTOOL") linhas)"
fi

if [ -s "$BOOTDIR/vbmeta.img" ] && [ -s "$BOOTDIR/vbmeta_system.img" ]; then
    ok "os vbmeta já existem"
else
    python3 "$AVBTOOL" make_vbmeta_image --flags 2 --padding_size 4096 \
        --output "$BOOTDIR/vbmeta.img" || die "o avbtool falhou"
    cp "$BOOTDIR/vbmeta.img" "$BOOTDIR/vbmeta_system.img"
    ok "vbmeta.img e vbmeta_system.img gerados"
fi

# ---------------------------------------------------------------------------

say "ficou pronto em $BOOTDIR"
ls -lh "$BOOTDIR"/*.img "$BOOTDIR"/avbtool.py 2>/dev/null || true
echo
echo "  Painel: $PANEL"
echo
echo "Para saber qual é o seu painel, com o Android a correr:"
echo "    adb shell getprop ro.product.device"
echo "    # surya  → Huaxing"
echo "    # surya_tianma → Tianma"
echo
ok "pronto para o flash"
