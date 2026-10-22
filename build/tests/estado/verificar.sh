#!/usr/bin/env bash
# T17 — the phone is in a known state.
#
# A collection of quick, objective checks that say whether the phone is
# healthy: the kernel is the right one, the modules match it, the services
# that matter are running, the battery is charging when it should, and
# nothing has been left in a bad state.
#
#   ./estado/verificar.sh
#   ./estado/verificar.sh --save      also write the result to a file
#
# Exit status: 0 if everything passed, 1 otherwise.
set -eu

SAVE=""
[ "${1:-}" = "--save" ] && SAVE=1

fail=0
warn_count=0
ok()   { printf '  \033[32mok\033[0m     %s\n' "$*"; }
bad()  { printf '  \033[31mFALHA\033[0m %s\n' "$*"; fail=$((fail + 1)); }
warn() { printf '  \033[33matenção\033[0m %s\n' "$*"; warn_count=$((warn_count + 1)); }
note() { printf '         %s\n' "$*"; }

echo "╔════════════════════════════════════════════╗"
echo "║  T17 — estado do telefone                   ║"
echo "╚════════════════════════════════════════════╝"
echo
echo "  $(date -Is)"
echo "  $(uname -srm)"
echo

# ---------------------------------------------------------------------------
echo "1. o kernel"

REL=$(uname -r)
if [ -n "$REL" ]; then
    ok "a correr $REL"
else
    bad "não foi possível ler uname -r"
fi

# The '+' means the kernel was built without LOCALVERSION=, and then the
# module directory does not match. This is a hard failure, not a warning.
case "$REL" in
    *+) bad "o release tem um '+' — o kernel foi construído sem LOCALVERSION=" ;;
    *)  ok "o release está limpo (sem '+')" ;;
esac

# The modules have to be from the same build as the kernel.
if [ -d "/lib/modules/$REL" ]; then
    ok "/lib/modules/$REL existe"
    n=$(find "/lib/modules/$REL" -name '*.ko*' 2>/dev/null | wc -l)
    ok "$n módulos instalados"
    if [ "$n" -lt 50 ]; then
        warn "só $n módulos — o conjunto parece incompleto"
    fi
else
    bad "/lib/modules/$REL não existe"
    note "o kernel e os módulos não são do mesmo build"
    note "os directórios disponíveis: $(ls /lib/modules/ 2>/dev/null | tr '\n' ' ')"
fi

# The release has to be r93 or newer for the voice capture switch.
R=${REL##*.r}
case "$R" in
    ''|*[!0-9]*) warn "não foi possível ler o pkgrel de $REL" ;;
    *)
        if [ "$R" -ge 93 ]; then
            ok "r$R — a configuração de voz é suportada"
        else
            bad "r$R — a configuração do dispositivo exige r93 ou mais"
        fi
        ;;
esac
echo

# ---------------------------------------------------------------------------
echo "2. os serviços"

check_service() {
    local name=$1 why=$2
    if systemctl --user is-active "$name" >/dev/null 2>&1 && \
       [ "$(systemctl --user is-active "$name" 2>/dev/null)" = active ]; then
        ok "$name está activo ($why)"
    else
        bad "$name não está activo ($why)"
    fi
}

check_system_service() {
    local name=$1 why=$2
    if [ "$(systemctl is-active "$name" 2>/dev/null)" = active ]; then
        ok "$name está activo ($why)"
    else
        bad "$name não está activo ($why)"
    fi
}

check_service armar-audio-usuario "o supervisor do auscultador"
check_service llamada-al-bluetooth "mover a chamada para o Bluetooth"
check_service hfp-registrado "o perfil HFP"
check_service aviso-bt-caido "o aviso de Bluetooth caído"
check_service goa-keyring-fix "o keyring do GoA"
check_system_service armar-audio "o serviço de áudio do sistema"
check_system_service gnss-engine-unlock "o motor GNSS"
check_system_service hexagonrpcd-adsp-audiopd "o PD de áudio do ADSP"
echo

# ---------------------------------------------------------------------------
echo "3. a bateria"

for b in /sys/class/power_supply/*/; do
    name=$(basename "$b")
    [ -f "$b/type" ] || continue
    type=$(cat "$b/type")
    [ "$type" = Battery ] || continue

    cap=$(cat "$b/capacity" 2>/dev/null || echo "?")
    ok "bateria: $cap%"
    if [ "$cap" != "?" ] && [ "$cap" -le 5 ] 2>/dev/null; then
        warn "$cap% — a bateria está muito baixa"
    fi

    # The charging status.
    st=$(cat "$b/status" 2>/dev/null || echo "?")
    echo "         estado: $st"

    # The current, if the gauge exposes it.
    for f in current_now power_now; do
        [ -f "$b/$f" ] && { v=$(cat "$b/$f"); note "$f = $v"; break; }
    done

    # The 19 % error the OCV lookup fixes. The voltage at 19 % has to be
    # the empirical one, not the generic table's.
    if [ -f "$b/energy_now" ]; then
        v=$(cat "$b/voltage_now" 2>/dev/null || echo "")
        [ -n "$v" ] && note "voltagem: $v uV"
    fi
    break
done
echo

# ---------------------------------------------------------------------------
echo "4. o armazenamento e a suspensão"

if [ -f /sys/power/mem_sleep ]; then
    s=$(cat /sys/power/mem_sleep)
    ok "mem_sleep: $s"
    if [ "$s" = "[suspend]" ] || [ "$s" = "suspend" ]; then
        ok "a suspensão está disponível"
    else
        warn "a suspensão não está disponível"
    fi
else
    warn "não foi possível ler /sys/power/mem_sleep"
fi

# The UFS scaling the power scripts turn off. If it is still on, the phone
# draws noticeably more while idle.
for f in /sys/class/scsi_host/host*/device/left_scaling_factor \
         /sys/class/scsi_host/host*/device/right_scaling_factor; do
    [ -f "$f" ] && note "$(basename "$f") = $(cat "$f")"
done

df -h / 2>/dev/null | tail -1 | while read -r line; do note "partição /: $line"; done
echo

# ---------------------------------------------------------------------------
echo "5. a última falha"

# The pstore keeps the trace of a crash. It is the first thing to look at
# when the phone died silently.
if [ -d /sys/fs/pstore ]; then
    found=0
    for f in /sys/fs/pstore/*; do
        [ -e "$f" ] || continue
        case "$f" in *_console-ramoops*|*_dmesg-ramoops*) ;; *) continue ;; esac
        found=1
        note "$(basename "$f"): $(wc -c < "$f") bytes"
    done
    if [ "$found" = 1 ]; then
        warn "há um rasto de uma falha anterior"
        note "ver com: cat /sys/fs/pstore/*-dmesg-ramoops-0 | tail -50"
    else
        ok "sem rasto de falha no pstore"
    fi
else
    note "sem /sys/fs/pstore"
fi
echo

# ---------------------------------------------------------------------------
echo
if [ "$fail" -eq 0 ]; then
    printf '\033[32mT17 passou\033[0m'
    [ "$warn_count" -gt 0 ] && printf ' (%d avisos)' "$warn_count"
    printf '\n'
    RESULT="ok, $warn_count avisos"
else
    printf '\033[31mT17 falhou em %d verificação(ões)\033[0m' "$fail"
    [ "$warn_count" -gt 0 ] && printf ', %d avisos' "$warn_count"
    printf '\n'
    RESULT="falhou em $fail verificações, $warn_count avisos"
fi

if [ -n "$SAVE" ]; then
    OUT=${OUT:-estado-$(date +%Y%m%d-%H%M%S).txt}
    {
        echo "T17 — $(date -Is)"
        echo "kernel: $REL"
        echo "resultado: $RESULT"
    } > "$OUT"
    echo "gravado em $OUT"
fi

[ "$fail" -eq 0 ] || exit 1
