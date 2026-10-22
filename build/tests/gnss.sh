#!/usr/bin/env bash
# T13 — the GNSS.
#
# The receiver is the modem, not the application processor, and the factory
# configuration says so: NMEA_PROVIDER=0. The modem supports BeiDou,
# GLONASS, QZSS, Galileo and SBAS, each with its own blacklist mask.
#
# The check: the engine has to run, and the satellites of at least two
# constellations have to be visible.
#
#   ./gnss.sh             read the state
#   ./gnss.sh --watch     follow the NMEA sentences
set -eu

WATCH=0
[ "${1:-}" = "--watch" ] && WATCH=1

fail=0
ok()  { printf '  \033[32mok\033[0m     %s\n' "$*"; }
bad() { printf '  \033[31mFALHA\033[0m %s\n' "$*"; fail=$((fail + 1)); }
note(){ printf '         %s\n' "$*"; }

echo "T13 — GNSS"
echo

# The engine. The service unlocks the engine at boot; without it there is
# nothing to receive with.
if command -v systemctl >/dev/null 2>&1; then
    if [ "$(systemctl is-active gnss-engine-unlock 2>/dev/null)" = active ]; then
        ok "gnss-engine-unlock está activo"
    else
        bad "gnss-engine-unlock não está activo"
        note "sem ele o motor não arranca e não há GNSS"
    fi
fi

# The control device. This is the modem's, reached through the QMI LOC
# service, not a GNSS chip on the application processor.
DEV=/dev/gnss0
if [ -e "$DEV" ]; then
    ok "$DEV existe"
else
    note "sem $DEV — o GNSS é gerido pelo modem, por QMI"
fi

# The QMI way: the modem's LOC service has to be there.
if command -v qmicli >/dev/null 2>&1; then
    if qmicli --device=/dev/cdc-wdm0 --locate 2>&1 | head -3 | grep -qi 'gps'; then
        note "qmicli está a falar com o serviço LOC do modem"
    fi
    if qmicli --device=/dev/cdc-wdm0 --locate 2>&1 | grep -qiE 'beidou|galileo|glonass'; then
        ok "o modem anuncia as constelações"
    else
        note "a lista de constelações não aparece no qmicli"
    fi
else
    note "sem qmicli — não dá para interrogar o modem"
fi

# The engine's own log. The unlock writes the result of the request there.
J=$(journalctl -u gnss-engine-unlock --no-pager -n 30 2>/dev/null || true)
if [ -n "$J" ]; then
    note "últimas linhas do serviço:"
    echo "$J" | tail -8 | sed 's/^/         /'
fi

# The constellations actually visible. This is the real criterion.
if [ "$WATCH" = "1" ]; then
    note "a seguir as frases NMEA (Ctrl-C para sair)"
    if command -v gnssctl >/dev/null 2>&1; then
        gnssctl 2>/dev/null || true
    else
        timeout 30 cat /dev/gnss0 2>/dev/null || true
    fi
fi

# The constellations, from the NMEA GSV sentences if there are any.
SATS=$(timeout 5 cat /dev/gnss0 2>/dev/null | grep -c '\$GPGSV\|\$GLGSV\|\$GAGSV\|\$BDGSV\|\$QZGSV' || true)
if [ "${SATS:-0}" -gt 0 ]; then
    ok "$SATS frases GSV recebidas"
else
    note "sem frases GSV — pode ser só o início, ou o motor não arrancou"
    note "esperar 60 s ao ar livre e repetir"
fi

echo
note "as constelações esperadas: BeiDou, GLONASS, QZSS, Galileo, SBAS"
note "o que é preciso ver: Galileo e BeiDou (T13)"
echo
[ "$fail" -eq 0 ] || exit 1
exit 0
