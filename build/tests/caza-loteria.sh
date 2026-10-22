#!/usr/bin/env bash
# T1 — the stereo channels go to their own side.
#
# The two loudspeakers are on one I2S bus and each amplifier is mono: the
# bottom speaker (by the USB port, ALSA "Right") and the top one (by the
# screen, ALSA "Left"), which doubles as the earpiece for calls. The
# channel separation is done by muting the amplifier that should stay
# quiet — there is no DSP-side mixer.
#
# This plays a short tone on one channel at a time, and asks the person
# holding the phone which side they hear it on.
#
#   ./caza-loteria.sh          the two channels, one after the other
#   ./caza-loteria.sh 1        only the left
#   ./caza-loteria.sh 2        only the right
#
# The rules the tone has to follow:
#   - amplitude at or below 30 %, so a mistake cannot hurt anyone's ears
#   - duration at or below 20 s, never a long section in a loop
set -eu

# The card and the device. On this board the speaker amps are behind the
# HiFi profile, on the primary ALSA card.
CARD=${CARD:-0}
DEV=${DEV:-0}
AMP=${AMP:-30}          # percent
FREQ=${FREQ:-440}
DUR=${DUR:-10}          # seconds

which_side() {
    case "$1" in
        1) echo "esquerda (o altifalante de cima, ao lado do ecrã)" ;;
        2) echo "direita (o altifalante de baixo, ao lado da porta USB)" ;;
    esac
}

play_channel() {
    local ch=$1
    # speaker-test -l takes the list of channels of the -c set to play.
    # With -c 2, channel 0 is the left one and channel 1 the right one.
    local list
    [ "$ch" = 1 ] && list=0
    [ "$ch" = 2 ] && list=1

    echo
    echo "─── canal $ch: $(which_side "$ch") ───"
    echo "    $FREQ Hz, $DUR s, $AMP % de amplitude"
    echo
    echo "    toque com o dedo no altifalante indicado e diga se o som sai"
    echo "    do lado indicado, do outro, ou dos dois."
    echo

    speaker-test -D "$CARD" -d "$DEV" -c 2 -l "$list" \
        -r "$FREQ" -t sine -a "$AMP" -w "$DUR" 2>/dev/null || \
        warn "o speaker-test não correu — está o alsamixermodule carregado?"
}

echo "╔════════════════════════════════════════════╗"
echo "║  T1 — separação estéreo L/R                ║"
echo "╚════════════════════════════════════════════╝"
echo
echo "Precisas do telefone emHl jq hl ecrã virado para cima e sem som de fundo."
echo "Volume no mínimo."

case "${1:-}" in
    1) play_channel 1 ;;
    2) play_channel 2 ;;
    *)  play_channel 1; play_channel 2 ;;
esac

echo
echo "─── resultado ───"
echo
echo "Escreve o que ouviste para guardar a evidência:"
echo "    canal 1 (esquerda):  [ ] esquerda  [ ] direita  [ ] ambos"
echo "    canal 2 (direita):   [ ] esquerda  [ ] direita  [ ] ambos"
echo
echo "Se o canal 1 sair dos dois lados, o mux ASI1 Sel do amplificador"
echo "esquerdo não está a ser aplicado — ver device/audio/HiFi.conf."
echo "Se nenhum sair, o perfil HiFi não carregou: verificar com"
echo "    alsaucm -c $CARD list | grep -i hifi"
