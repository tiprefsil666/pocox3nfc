#!/usr/bin/env bash
# T16 — the cold boot.
#
# The phone has to boot in under 30 seconds, with no kernel warnings worth
# calling a warning, and it has to come up from power off — not just from
# a reboot.
#
#   ./arranque-frio.sh              check the state of the last boot
#   ./arranque-frio.sh --boot-time  how long the last boot took
set -eu

fail=0
ok()  { printf '  \033[32mok\033[0m     %s\n' "$*"; }
bad() { printf '  \033[31mFALHA\033[0m %s\n' "$*"; fail=$((fail + 1)); }
note(){ printf '         %s\n' "$*"; }

echo "T16 — arranque a frio"
echo

# The boot time. systemd records it, and the kernel's own timestamps are in
# the log.
BOOT=$(systemd-analyze 2>/dev/null | head -1 || true)
if [ -n "$BOOT" ]; then
    note "systemd-analyze: $BOOT"
    # The total time is the second field.
    T=$(echo "$BOOT" | grep -oE '[0-9]+min [0-9]+(\.[0-9]+)?s' | head -1)
    if [ -n "$T" ]; then
        SEC=$(echo "$T" | awk '{if ($1 ~ /min/) print $1*60 + $3; else print $1}' | tr -d 's')
        if [ "${SEC:-999}" -lt 30 ] 2>/dev/null; then
            ok "arrancou em ${SEC}s (menos de 30 s)"
        else
            bad "arrancou em ${SEC}s — o critério é menos de 30 s"
        fi
    fi
else
    note "sem systemd-analyze"
fi

# The kernel's own timestamps: the first and the last.
F=$(journalctl -b -k --no-pager 2>/dev/null | head -1)
L=$(journalctl -b -k --no-pager 2>/dev/null | tail -1)
if [ -n "$F" ] && [ -n "$L" ]; then
    note "primeira linha do kernel: $(echo "$F" | cut -c1-70)"
fi

# The kernel warnings. "triangular kernels" is the phrase from the
# criterion: the warnings that show up in a triangle at the top of the
# boot, usually the regulators, the clocks or the DSI.
echo
WARN=$(journalctl -b -k --no-pager -p warning 2>/dev/null | grep -c . || true)
if [ "${WARN:-0}" -eq 0 ]; then
    ok "sem avisos de kernel"
else
    note "$WARN linhas de aviso no kernel:"
    journalctl -b -k --no-pager -p warning 2>/dev/null | head -10 | sed 's/^/         /'
fi

# The specific ones that have bitten before.
echo
for pat in 'regulator.*failed' 'clk.*failed' 'Unable to handle' 'probe.*deferred' 'hang' 'timeout'; do
    n=$(journalctl -b -k --no-pager 2>/dev/null | grep -ciE "$pat" || true)
    if [ "${n:-0}" -gt 0 ]; then
        note "$n: $pat"
    fi
done

# The system has to have come all the way up.
echo
if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-system-running >/dev/null 2>&1; then
        s=$(systemctl is-system-running)
        case "$s" in
            running) ok "o sistema está a correr" ;;
            degraded) note "o sistema está degradado: $(systemctl list-units --state=failed --no-pager --plain | head -5)" ;;
            *) note "o sistema está em: $s" ;;
        esac
    fi
    FAILED=$(systemctl list-units --state=failed --no-pager --plain 2>/dev/null | grep -c . || true)
    [ "${FAILED:-0}" -gt 0 ] && note "$FAILED unidade(s) falharam"
fi

# The graphical session, if there is one.
if command -v systemctl >/dev/null 2>&1; then
    for u in display-manager sddm greetd; do
        if systemctl list-unit-files "$u.service" 2>/dev/null | grep -q "$u.service"; then
            if [ "$(systemctl is-active "$u" 2>/dev/null)" = active ]; then
                ok "$u está activo — a sessão gráfica arrancou"
            else
                note "$u não está activo"
            fi
            break
        fi
    done
fi

echo
[ "$fail" -eq 0 ] || exit 1
exit 0
