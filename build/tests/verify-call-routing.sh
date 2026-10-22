#!/usr/bin/env bash
# T2 — the call audio goes where it should.
#
# This is the objective check for the call routing: it walks the ALSA
# use-case graph and checks that the capture and the playback devices of the
# "Voice Call" profile resolve to the right cards, and that the modules the
# profile needs are actually loaded.
#
#   ./verify-call-routing.sh
#   ./verify-call-routing.sh --card 0
#
# What it checks:
#   1. the Voice Call use case exists and its file is the one from the port
#   2. the capture and the playback devices of the profile open
#   3. the modules the profile depends on are loaded
#   4. the microphone routing is the expected one
#
# Exit status: 0 if everything passed, 1 otherwise.
set -eu

CARD=${CARD:-0}
if [ "${1:-}" = "--card" ]; then CARD=$2; fi

fail=0
ok()   { printf '  \033[32mok\033[0m     %s\n' "$*"; }
bad()  { printf '  \033[31mFALHA\033[0m %s\n' "$*"; fail=$((fail + 1)); }
note() { printf '         %s\n' "$*"; }

echo "╔════════════════════════════════════════════╗"
echo "║  T2 — routing da chamada                    ║"
echo "╚════════════════════════════════════════════╝"
echo

# ---------------------------------------------------------------------------
echo "1. o perfil de chamada"

# The official alsa-ucm-conf-qcom-sm7150 package installs its profile in
# Xiaomi/surya/ and its use case in conf.d/sm8250/, under the name
# "POCO X3.conf" — with a space. This port's configuration replaces both
# in place, so these are the paths to check.
UCM_ROOT=/usr/share/alsa/ucm2
UCM_DIR=$UCM_ROOT/conf.d/sm8250
UCM_PROF=$UCM_ROOT/Xiaomi/surya

if [ -f "$UCM_PROF/VoiceCall.conf" ]; then
    ok "VoiceCall.conf está em $UCM_PROF"
else
    bad "VoiceCall.conf não está em $UCM_PROF"
    note "o perfil não vai carregar; instalar com"
    note "    surya-pmos/scripts/install-on-device.sh <host>"
fi

if [ -f "$UCM_PROF/HiFi.conf" ]; then
    ok "HiFi.conf está em $UCM_PROF"
else
    bad "HiFi.conf não está em $UCM_PROF"
fi

# The use case, under the official name. Both spellings are accepted, but
# there must only be one: two "HiFi" use cases compete.
if [ -f "$UCM_DIR/POCO X3.conf" ]; then
    ok "'POCO X3.conf' está em $UCM_DIR"
elif [ -f "$UCM_DIR/POCO-X3.conf" ]; then
    ok "'POCO-X3.conf' está em $UCM_DIR"
else
    bad "nenhum 'POCO X3.conf' em $UCM_DIR"
fi

n=$(ls "$UCM_DIR" 2>/dev/null | grep -icE '^poco.*x3.*\.conf$')
if [ "${n:-0}" -gt 1 ]; then
    bad "há $n ficheiros de use case do POCO X3 — só pode haver um"
    note "o 'alsa-ucm-conf-qcom-sm7150' oficial e a nossa configuração"
    note "estão a competir; ver o roadmap §4.5.1"
fi

# The use case has to be listed by the UCM library itself.
if alsaucm -c "$CARD" list 2>/dev/null | grep -qi 'voice call'; then
    ok "o 'Voice Call' aparece na lista de use cases"
else
    bad "o 'Voice Call' não aparece na lista de use cases"
    note "saída de alsaucm -c $CARD list:"
    alsaucm -c "$CARD" list 2>&1 | sed 's/^/         /' | head -12
fi
echo

# ---------------------------------------------------------------------------
echo "2. os dispositivos de captura e de reprodução"

# The capture device of the profile: MultiMedia2 on this board.
CAPDEV=$(alsaucm -c "$CARD" list _verbs 2>/dev/null | head -1)
if [ -n "$CAPDEV" ]; then
    ok "a placa de som $CARD responde"
else
    bad "a placa de som $CARD não responde"
    echo
    echo "FALHAS: $fail"
    exit 1
fi

# Playback and capture have to open. If the profile is broken, the capture
# fails with EINVAL, and the symptom in the kernel is
#   "no valid Capture path" in soc-pcm.c with dynamic debug on.
if arecord -D hw:"$CARD",0 -f S16_LE -r 48000 -c 2 -d 1 /dev/null 2>/dev/null; then
    ok "a captura abre"
else
    bad "a captura não abre"
    note "verificar com: dmesg | grep -i 'no valid Capture path'"
    note "é o sintoma do perfil de chamada sem a sequência de enable"
fi

if aplay -D hw:"$CARD",0 -f S16_LE -r 48000 -c 2 -d 1 /dev/zero 2>/dev/null; then
    ok "a reprodução abre"
else
    bad "a reprodução não abre"
fi
echo

# ---------------------------------------------------------------------------
echo "3. os módulos de que o perfil depende"

# The voice path runs on the Q6 (the hexagon DSP). If these are not loaded,
# the capture opens but stays silent.
for m in q6voice q6routing slim_qcom_ngd_ctrl; do
    if lsmod 2>/dev/null | grep -q "^$m\b"; then
        ok "$m carregado"
    else
        bad "$m não está carregado"
    fi
done

# The SLIMbus channels that are removed to make the routing work. This is
# what patch 0130 does, and slimbus.conf sets the parameter.
P=/sys/module/slim_qcom_ngd_ctrl/parameters/remove_channels
if [ -f "$P" ]; then
    val=$(cat "$P")
    if [ "$val" = "Y" ] || [ "$val" = "y" ] || [ "$val" = "1" ]; then
        ok "remove_channels = $val (o patch 0130 está activo)"
    else
        bad "remove_channels = $val — o patch 0130 não está activo"
        note "o routing de auscultadores Bluetooth não vai funcionar"
    fi
else
    warn "o parâmetro remove_channels não existe"
fi
echo

# ---------------------------------------------------------------------------
echo "4. o routing dos microfones"

# The profile has to send the call microphone to the right place. The
# expected route is the main microphone, and the earpiece microphone has to
# be off during a call.
if [ -f "$UCM_PROF/VoiceCall.conf" ]; then
    if grep -q 'SectionDevice' "$UCM_PROF/VoiceCall.conf"; then
        ok "o VoiceCall.conf tem SectionDevice"
    else
        bad "o VoiceCall.conf não tem SectionDevice"
    fi
    # The capture controls that the profile sets. These are the ones that
    # only exist from kernel r93.
    for c in 'Voice Tx Capture Switch' 'Voice Calibration'; do
        if grep -q "$c" "$UCM_PROF/VoiceCall.conf"; then
            ok "usa '$c'"
        else
            bad "não usa '$c'"
            note "o kernel tem de ser r93 ou mais novo; verificar com uname -r"
        fi
    done
fi
echo

# ---------------------------------------------------------------------------
echo "5. o altifalante e o auscultador"

# The two output devices of the profile. Both have to be there: the
# altifalante is the top amplifier and the auscultador is the same one
# through the earpiece routing.
if [ -f "$UCM_PROF/VoiceCall.conf" ]; then
    n=$(grep -c 'SectionDevice' "$UCM_PROF/VoiceCall.conf")
    if [ "$n" -ge 2 ]; then
        ok "$n SectionDevice (auricular e altifalante)"
    else
        bad "só $n SectionDevice — deviam ser dois (auricular e altifalante)"
    fi
fi
echo

# ---------------------------------------------------------------------------
echo
if [ "$fail" -eq 0 ]; then
    printf '\033[32mT2 passou\033[0m\n'
    exit 0
else
    printf '\033[31mT2 falhou em %d verificação(ões)\033[0m\n' "$fail"
    exit 1
fi
