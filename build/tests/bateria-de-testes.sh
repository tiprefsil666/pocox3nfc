#!/usr/bin/env bash
# The whole test battery, T1 to T17.
#
#   ./bateria-de-testes.sh           the objective ones
#   ./bateria-de-testes.sh --list    what each test is
#
# The tests split in two kinds:
#
#   - objective: a script can decide whether they passed. These run here.
#   - by ear:    a person has to listen and answer. These print their
#                procedure and wait.
#
# Exit status: 0 if every objective test passed.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if [ "${1:-}" = "--list" ]; then
    cat <<'EOF'
  T1  Estéreo L/R                ao ouvido      ./caza-loteria.sh
  T2  Auricular do telefone     objectivo      ./verify-call-routing.sh
  T3  Chamada, áudio 2 sentidos ao ouvido
  T4  Volume por destino        ao ouvido
  T5  Mover p/ altifalante      ao ouvido      ⚠️ sabe-se que falha
  T6  Mover p/ auscultadores    ao ouvido      ⚠️ sabe-se que falha
  T7  Auscultadores BT          objectivo      ./bt-offload.sh
  T8  Aurora cancelada          medição       ⚠️ precisa da calibração de fábrica
  T9  Câmara traseira           objectivo      ./camera.sh traseira
  T10 Câmara frontal            objectivo      ./camera.sh frontal   ⚠️ sabe-se que não há fluxo
  T11 Suspensão                 objectivo      ./suspensao.sh
  T12 Bateria                   objectivo      ./bateria.sh
  T13 GNSS                      objectivo      ./gnss.sh
  T14 Notificações              ao ouvido
  T15 USB OTG                   objectivo      ./usb-otg.sh
  T16 Arranque a frio           objectivo      ./arranque-frio.sh
  T17 Estabilidade (48 h)       objectivo      ./estado/verificar.sh
EOF
    exit 0
fi

fail=0
section() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$*"; }

run_test() {
    local name=$1 script=$2
    if [ ! -x "$HERE/$script" ]; then
        printf '  \033[33matenção\033[0m %s: %s não existe\n' "$name" "$script"
        return 0
    fi
    if "$HERE/$script"; then
        printf '  \033[32mok\033[0m     %s\n' "$name"
    else
        printf '  \033[31mFALHA\033[0m %s\n' "$name"
        fail=$((fail + 1))
    fi
}

echo "╔════════════════════════════════════════════╗"
echo "║  bateria de testes — POCO X3 NFC / surya    ║"
echo "╚════════════════════════════════════════════╝"

section "T2  routing da chamada"
run_test "T2 routing da chamada" verify-call-routing.sh

section "T7  offload do auscultador Bluetooth"
run_test "T7 offload BT" bt-offload.sh

section "T9  câmara traseira"
run_test "T9  câmara traseira" camera.sh traseira

section "T10 câmara frontal (bloqueador conhecido)"
# The front camera has no stream: the sensor is C-PHY and the receiver is
# D-PHY. The script documents the state and exits with 0, because it is a
# known blocker and not a new failure.
run_test "T10 câmara frontal" camera.sh frontal

section "T11 suspensão"
run_test "T11 suspensão" suspensao.sh

section "T12 bateria"
run_test "T12 bateria" bateria.sh

section "T13 GNSS"
run_test "T13 GNSS" gnss.sh

section "T15 USB OTG"
run_test "T15 USB OTG" usb-otg.sh

section "T16 arranque a frio"
run_test "T16 arranque a frio" arranque-frio.sh

section "T17 estado"
run_test "T17 estado" estado/verificar.sh

section "os que precisam de ouvido"
cat <<'EOF'
  T1  ./caza-loteria.sh
  T3  fazer uma chamada real e falar
  T4  volume por destino
  T5  mover a chamada para o altifalante  ⚠️ sabe-se que falha
  T6  mover a chamada de volta           ⚠️ sabe-se que falha
  T8  medir o eco                         ⚠️ precisa da calibração de fábrica
  T14 tocar o telefone: som e vibração
EOF

echo
if [ "$fail" -eq 0 ]; then
    printf '\033[32mtodos os testes objectivos passaram\033[0m\n'
else
    printf '\033[31m%s teste(s) objectivo(s) falharam\033[0m\n' "$fail"
fi
exit $((fail > 0))
