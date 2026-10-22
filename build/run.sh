#!/usr/bin/env bash
# Run the whole build, in order.
#
#   ./run.sh                 everything, from the host check to the image
#   ./run.sh --from 20       start at a step
#   ./run.sh --to 30         stop after a step
#   ./run.sh --list          list the steps
#
# The steps are numbered so that they can be run on their own while a
# problem is being chased, and so that a long build can be resumed.
# The numbers are the numeric prefixes of the file names: --from 20
# starts at 20-overlay.sh.
set -eu
. "$(dirname -- "$0")/env.sh"
. "$(dirname -- "$0")/lib.sh"

STEPS="00-check-host.sh 05-prepare-boot.sh 10-fetch.sh 20-overlay.sh 30-build.sh 50-verify.sh"

start=""
stop=""
LIST_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --from) start=$2; shift 2 ;;
        --to)   stop=$2; shift 2 ;;
        --list) LIST_ONLY=1; shift ;;
        -h|--help)
            sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) die "opção desconhecida: $1" ;;
    esac
done

if [ "$LIST_ONLY" = "1" ]; then
    say "os passos"
    while read -r n d; do
        printf '  %s. %-22s %s\n' "$n" "$d" ""
    done <<'EOF'
00 check-host       as dependências do host
05 prepare-boot     o u-boot do painel e os vbmeta vazios
10 fetch            o pmaports
20 overlay          os quatro overlays
30 build            a configuração e a imagem
50 verify           a imagem e o kernel
EOF
    echo
    note "25-build-kernel.sh  compila só o kernel, para iterar sobre os patches"
    note "40-flash.sh         grava o telefone — corra-o à mão, e só"
    note "                    depois de confirmar o painel"
    exit 0
fi

ran=0
for s in $STEPS; do
    n=${s%%-*}
    if [ -n "$start" ] && [ "$n" -lt "$start" ] 2>/dev/null; then continue; fi
    if [ -n "$stop" ] && [ "$n" -gt "$stop" ] 2>/dev/null; then break; fi

    printf '\n%s━━━ %s ━━━%s\n' "$C_BOLD$C_BLUE" "$s" "$C_RESET"
    "$BUILD/$s"
    ran=$((ran + 1))
done

[ "$ran" -gt 0 ] || die "nenhum passo correu — verifique o --from/--to"

printf '\n%s━━━ pronto ━━━%s\n' "$C_BOLD$C_GREEN" "$C_RESET"
echo
echo "  imagens:   $WORK/images"
echo "  logs:      $LOG"
echo "  manifesto: $MANIFEST"
echo
echo "Falta gravar o telefone:"
echo "    $BUILD/40-flash.sh            # pré-visualização"
echo "    $BUILD/40-flash.sh --run      # grava"
echo
echo "Depois de gravar, a configuração do dispositivo:"
echo "    surya-pmos/scripts/install-on-device.sh <host>"
