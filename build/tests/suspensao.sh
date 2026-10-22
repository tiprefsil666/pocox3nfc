#!/usr/bin/env bash
# T11 — the phone suspends, and the idle draw is low.
#
#   ./suspensao.sh          check that suspend is available and the state is right
#   ./suspensao.sh --measure  measure the idle draw over 60 s
set -eu

MEASURE=0
[ "${1:-}" = "--measure" ] && MEASURE=1

fail=0
ok()  { printf '  \033[32mok\033[0m     %s\n' "$*"; }
bad() { printf '  \033[31mFALHA\033[0m %s\n' "$*"; fail=$((fail + 1)); }
note(){ printf '         %s\n' "$*"; }

echo "T11 — suspensão"
echo

# The kernel has to have the sleep states compiled in.
if [ -f /sys/power/mem_sleep ]; then
    s=$(cat /sys/power/mem_sleep)
    note "mem_sleep: $s"
    case "$s" in
        *suspend*) ok "a suspensão está disponível" ;;
        *) bad "a suspensão não está disponível ($s)" ;;
    esac
else
    bad "/sys/power/mem_sleep não existe"
fi

# The states themselves.
for d in /sys/power/state; do
    [ -f "$d" ] && note "estados: $(cat "$d")"
done

# The runtime PM of the USB and the Bluetooth. The power scripts turn these
# off; if they are still on, the phone draws much more while idle.
echo
echo "runtime PM:"
for dev in /sys/bus/usb/devices/*/power/control /sys/class/bluetooth/*/device/power/control; do
    [ -f "$dev" ] || continue
    v=$(cat "$dev")
    name=$(echo "$dev" | sed 's|/power/control||')
    if [ "$v" = "auto" ]; then
        ok "$(basename "$(dirname "$name")"): auto"
    else
        note "$(basename "$name"): $v (esperado auto)"
    fi
done

# The UFS scaling. Left and right scaling off is what the power script
# does; with it on the idle draw is noticeably higher.
echo
echo "UFS scaling:"
for f in /sys/class/scsi_host/host*/device/left_scaling_factor \
         /sys/class/scsi_host/host*/device/right_scaling_factor; do
    [ -f "$f" ] || continue
    v=$(cat "$f")
    name=$(basename "$f")
    if [ "$v" = "0" ]; then
        ok "$name = 0 (escalado)"
    else
        note "$name = $v (esperado 0)"
    fi
done

# The suspend of the Wi-Fi, which is the one that keeps the phone awake.
echo
if [ -f /sys/module/wlan_halt_cpucfg/parameters/enable_suspend ]; then
    v=$(cat /sys/module/wlan_halt_cpucfg/parameters/enable_suspend)
    [ "$v" = "1" ] && ok "wlan halt: a suspensão da Wi-Fi está activa" \
                   || note "wlan halt: enable_suspend = $v"
fi

# The measurement.
if [ "$MEASURE" = "1" ]; then
    echo
    echo "a medir o consumo em repouso durante 60 s..."
    B=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null || echo 0)
    V=$(cat /sys/class/power_supply/battery/voltage_now 2>/dev/null || echo 0)
    sleep 60
    A=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null || echo 0)
    if [ "$B" != "0" ] && [ "$A" != "0" ] && [ -n "$V" ] && [ "$V" != "0" ]; then
        # current_now is in microamps, voltage_now in microvolts.
        MW=$(awk "BEGIN{printf \"%.1f\", ($A*$V)/1000000000}")
        note "consumo actual: ${MW} mW"
        note "corrente: $A uA   voltagem: $V uV"
    else
        note "não foi possível ler o consumo deste carregador"
    fi
fi

echo
[ "$fail" -eq 0 ] || exit 1
exit 0
