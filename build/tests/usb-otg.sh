#!/usr/bin/env bash
# T15 — USB OTG.
#
# The phone has to be able to act as a USB host: a keyboard plugged into
# the OTG port has to appear as an input device and write to the terminal.
#
#   ./usb-otg.sh            check the OTG state
#   ./usb-otg.sh --wait     wait for a device to be plugged in
set -eu

WAIT=0
[ "${1:-}" = "--wait" ] && WAIT=1

fail=0
ok()  { printf '  \033[32mok\033[0m     %s\n' "$*"; }
bad() { printf '  \033[31mFALHA\033[0m %s\n' "$*"; fail=$((fail + 1)); }
note(){ printf '         %s\n' "$*"; }

echo "T15 — USB OTG"
echo

# The controller has to be in host mode. The port is a USB-C with the
# Type-C controller; the role is switched by the DRM (DisplayPort) or by
# the role-switch.
for f in /sys/class/usb-role/*/role /sys/kernel/debug/usb-role/*/role; do
    [ -e "$f" ] || continue
    r=$(cat "$f" 2>/dev/null || echo "")
    if [ "$r" = "host" ]; then
        ok "$(basename "$(dirname "$f")"): em modo host"
    else
        note "$(basename "$(dirname "$f")"): $r"
    fi
done

# The USB gadget config, which is the phone acting as a device. OTG means
# it can be either.
if [ -f /sys/class/udc/*/state ]; then
    ok "o gadget USB está disponível"
fi

# The actual test: is a keyboard going to work? The input stack has to have
# the HID driver, and the host port has to enumerate.
if [ "$WAIT" = "1" ]; then
    note "à espera de um dispositivo USB (Ctrl-C para sair)"
    before=$(ls /dev/input/ 2>/dev/null | wc -l)
    i=0
    while [ $i -lt 60 ]; do
        sleep 1
        after=$(ls /dev/input/ 2>/dev/null | wc -l)
        if [ "$after" -gt "$before" ]; then
            ok "um dispositivo novo apareceu em /dev/input"
            ls -la /dev/input/ | sed 's/^/         /'
            break
        fi
        i=$((i + 1))
    done
    [ $i -ge 60 ] && bad "nenhum dispositivo USB apareceu em 60 s"
else
    note "para o teste real: ligar um teclado e correr com --wait"
fi

# The HID driver has to be there for a keyboard to work.
if [ -d /sys/bus/hid/drivers/hid-generic ]; then
    ok "o driver HID está carregado"
else
    note "sem driver HID genérico — um teclado USB talvez não funcione"
fi

# The Type-C controller. On this board it is the fsa4480 or the pm8150.
if [ -d /sys/bus/platform/drivers/fsa4480 ] || [ -d /sys/bus/platform/drivers/pmic_glink ]; then
    ok "o controlador USB-C está presente"
fi

echo
[ "$fail" -eq 0 ] || exit 1
exit 0
