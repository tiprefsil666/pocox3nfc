#!/usr/bin/env bash
# T7 — the Bluetooth headset offload is real.
#
# When a call is on a Bluetooth headset, the audio should be handled by the
# Bluetooth chip, not by the CPU: the phone's own codec stays idle and the
# "SCO Data TX" counter in the HCI trace stops.
#
# The check: with a call on the headset, btmon must show no SCO data being
# sent, and the phone's own codec must not be active.
#
#   ./bt-offload.sh            check
#   ./bt-offload.sh --capture  capture 10 s of btmon to a file
set -eu

CAPTURE=${1:-}

fail=0
ok()  { printf '  \033[32mok\033[0m     %s\n' "$*"; }
bad() { printf '  \033[31mFALHA\033[0m %s\n' "$*"; fail=$((fail + 1)); }
note(){ printf '         %s\n' "$*"; }

echo "T7 — offload do auscultador Bluetooth"
echo

# The tools.
for t in btmon hcitool; do
    command -v "$t" >/dev/null 2>&1 || {
        bad "$t não está instalado"
        note "    sudo apk add bluez   # btmon e hcitool"
    }
done
[ "$fail" -eq 0 ] || exit 1

# The headset has to be connected.
CONN=$(hcitool con 2>/dev/null | head -1 || true)
if [ -z "$CONN" ]; then
    bad "não há nenhum auscultador Bluetooth ligado"
    note "ligar o auscultador e repetir"
    exit 1
fi
ok "auscultador ligado: $CONN"

# The codec of the phone itself must not be busy during the call — that is
# what the offload means.
if [ -d /sys/class/sound ]; then
    busy=0
    for c in /sys/class/sound/card*/codec*; do
        [ -e "$c" ] || continue
        n=$(cat "$c/device/power/runtime_status" 2>/dev/null || echo "")
        [ "$n" = "active" ] && busy=$((busy + 1))
    done
    if [ "$busy" -eq 0 ]; then
        ok "o codec do telefone está inactivo — o áudio não passa pela CPU"
    else
        bad "$busy codec(s) do telefone activo(s) durante a chamada"
        note "o offload não está a funcionar: o audio passa pela CPU"
    fi
fi

# The HCI trace: the SCO data must not be there.
if [ "$CAPTURE" = "--capture" ]; then
    note "a capturar 10 s de btmon — fazer uma chamada entretanto"
    timeout 10 btmon > /tmp/btmon-call.txt 2>/dev/null || true
    TX=$(grep -c 'SCO Data TX' /tmp/btmon-call.txt 2>/dev/null || echo 0)
    RX=$(grep -c 'SCO Data RX' /tmp/btmon-call.txt 2>/dev/null || echo 0)
    note "SCO Data TX: $TX   SCO Data RX: $RX"
    if [ "$TX" -eq 0 ]; then
        ok "nenhum SCO Data TX — o offload é real"
    else
        bad "$TX pacotes SCO Data TX — o offload não está activo"
    fi
    note "a captura ficou em /tmp/btmon-call.txt"
else
    note "para a medição: ./bt-offload.sh --capture durante uma chamada"
fi

echo
[ "$fail" -eq 0 ] || exit 1
exit 0
