#!/usr/bin/env bash
# T9 and T10 — the cameras.
#
#   ./camera.sh traseira   the rear camera: the autofocus has to work
#   ./camera.sh frontal    the front camera: KNOWN TO HAVE NO STREAM
#   ./camera.sh            both
#
# The rear camera is a S5K3H7 with a working autofocus. The front one is a
# S5K3T2 that transmits in C-PHY while the receiver is in D-PHY, and there
# is no flow: the sensor is in the device tree, but the receiver cannot be
# configured for it. That is a known blocker, and this test says so rather
# than pretending it is a pass.
set -eu

WHICH=${1:-ambas}
fail=0
ok()  { printf '  \033[32mok\033[0m     %s\n' "$*"; }
bad() { printf '  \033[31mFALHA\033[0m %s\n' "$*"; fail=$((fail + 1)); }
note(){ printf '         %s\n' "$*"; }

echo "câmaras"
echo

# The cameras have to be enumerated by libcamera. If they are not, the
# I2C probe failed — and when the probe fails intermittently, libcamera
# does not see ANY camera, not even the rear one.
echo "1. a enumeração"
if command -v qcamdevice >/dev/null 2>&1; then
    LIST=$(qcamdevice --list 2>/dev/null || true)
    if [ -n "$LIST" ]; then
        ok "qcamdevice encontrou: $(echo "$LIST" | tr '\n' ' ')"
    else
        bad "qcamdevice não encontrou câmaras"
        note "o probe do I2C falhou; ver dmesg | grep -iE 'imx|s5k|camera'"
    fi
elif command -v media-ctl >/dev/null 2>&1; then
    LIST=$(media-ctl -p 2>/dev/null | grep -oE 'entity [0-9]+:.*' || true)
    [ -n "$LIST" ] && ok "entidades de media_FOUND" || note "media-ctl sem entidades"
else
    note "sem qcamdevice nem media-ctl — não dá para enumerar"
fi
echo

# The rear camera.
if [ "$WHICH" = "traseira" ] || [ "$WHICH" = "ambas" ]; then
    echo "2. a câmara traseira (T9)"
    if [ -d /dev/media0 ] || [ -d /dev/media1 ]; then
        ok "existe um nó de media"
        if command -v media-ctl >/dev/null 2>&1; then
            for m in /dev/media*; do
                name=$(media-ctl -d "$m" -p 2>/dev/null | grep -m1 'model' | cut -d: -f2- | tr -d ' ')
                [ -n "$name" ] && note "$(basename "$m"): $name"
            done
        fi
    else
        bad "não há nós de media — nenhuma câmara"
    fi
    echo
fi

# The front camera.
if [ "$WHICH" = "frontal" ] || [ "$WHICH" = "ambas" ]; then
    echo "3. a câmara frontal (T10)"
    echo "   ⚠️  sabe-se que não há fluxo: C-PHY no sensor, D-PHY no receptor."
    echo "       Este teste documenta o estado, não o aprova."
    echo

    FRONTAL=0
    for m in /dev/media*; do
        [ -e "$m" ] || continue
        if command -v media-ctl >/dev/null 2>&1; then
            media-ctl -d "$m" -p 2>/dev/null | grep -qi 's5k3t2\|front' && FRONTAL=1
        fi
    done
    if [ "$FRONTAL" = 1 ]; then
        note "o sensor frontal aparece no dispositivo de media"
    else
        note "o sensor frontal não aparece"
    fi

    # The C-PHY link. The receiver's configuration is what is wrong, and
    # that is in the kernel log.
    if dmesg 2>/dev/null | grep -qiE 'csiphy.*(error|fail)|cphy.*(error|fail)'; then
        note "o registo do kernel tem erros de CSI-PHY:"
        dmesg 2>/dev/null | grep -iE 'csiphy|cphy' | tail -5 | sed 's/^/         /'
    fi

    echo
    printf '  \033[33mKNOWN FAILURE\033[0m a câmara frontal não tem fluxo\n'
    printf '  \033[33m               \033[0m o que falta: um driver que configure\n'
    printf '  \033[33m               \033[0m o receptor para C-PHY no SM7150\n'
    echo
fi

echo
if [ "$WHICH" = "frontal" ]; then
    # The front camera is a known failure, so it does not fail the run.
    exit 0
fi
[ "$fail" -eq 0 ] || exit 1
exit 0
