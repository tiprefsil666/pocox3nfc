#!/usr/bin/env bash
# Get the pmaports checkout the overlays are copied into.
#
# This is the slow step: pmaports is a large repository. It is done once and
# then reused, and the commit that was used is recorded, so a build can
# always be traced back to what it was built from.
#
#   ./10-fetch.sh            clone or update
#   ./10-fetch.sh --pin     clone but do not update if it already exists
set -eu
. "$(dirname -- "$0")/env.sh"
. "$(dirname -- "$0")/lib.sh"

PIN=${1:-}

UPSTREAM=$PROJECT/postmarketos/upstream
PMAPORTS_URL=https://gitlab.postmarketos.org/postmarketOS/pmaports.git

mkdir -p "$UPSTREAM" "$OUT"

say "pmaports"

if [ -d "$PMAPORTS/.git" ]; then
    if [ "$PIN" = "--pin" ]; then
        ok "já existe, e --pin impede actualizar"
    else
        say "a actualizar"
        git -C "$PMAPORTS" fetch --depth=1 origin || warn "o fetch falhou, a usar o que já lá está"
        git -C "$PMAPORTS" reset --hard "origin/$(git -C "$PMAPORTS" rev-parse --abbrev-ref HEAD)" \
            || warn "o reset falhou, a usar o que já lá está"
        ok "actualizado"
    fi
else
    say "a clonar (pode demorar uns minutos)"
    # A shallow clone: pmaports is large and the history is not needed.
    git clone --depth=1 "$PMAPORTS_URL" "$PMAPORTS" \
        || die "não foi possível clonar o pmaports de $PMAPORTS_URL"
    ok "clonado"
fi

# The kernel package has to be there, or there is nothing to overlay.
#
# Where it lives moves around: the layout used to be device/testing/, and
# the current pmaports has it in device/community/. Look it up rather than
# hardcode it, and write the answer into env.sh so the other scripts agree.
KDIR=""
for d in "$PMAPORTS"/device/*/"$OVERLAY_KERNEL"; do
    [ -d "$d" ] && KDIR="$d" && break
done
[ -n "$KDIR" ] || die "o pmaports não tem o pacote $OVERLAY_KERNEL em device/*/"

REL=$(echo "$KDIR" | sed "s|$PMAPORTS/||")
if [ "$REL" != "device/community/$OVERLAY_KERNEL" ]; then
    say "o pacote está em $REL (não em device/community/)"
    # Write it into env.sh so the next run finds it without looking again.
    if grep -q '^KERNEL_PKG_DIR=' env.sh; then
        sed -i "s|^KERNEL_PKG_DIR=.*|KERNEL_PKG_DIR=\${KERNEL_PKG_DIR:-$PMAPORTS/$REL}|" env.sh
        ok "env.sh actualizado com o caminho certo"
    fi
fi
ok "$OVERLAY_KERNEL está em $REL"

# The other two overlays are built out of temp/, which pmbootstrap creates.
# Check that the ones we override exist in the distribution, so that we know
# which patches to keep.
if [ -d "$PMAPORTS/temp/libcamera" ]; then
    ok "temp/libcamera já existe"
else
    say "temp/ ainda não existe — será criado na configuração (ou em $PMB init)"
fi

# Record what we are building from.
{
    echo "pmaports:   $(git -C "$PMAPORTS" rev-parse HEAD)"
    echo "pmaports:   $(git -C "$PMAPORTS" log -1 --format=%cd --date=iso)"
    echo "branch:     $(git -C "$PMAPORTS" rev-parse --abbrev-ref HEAD)"
    echo "fetched:    $(date -Is)"
} | tee "$OUT/pmaports-version.txt"

ok "pmaports pronto em $PMAPORTS"
