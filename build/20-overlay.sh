#!/usr/bin/env bash
# Copy the four overlays over pmaports.
#
# The kernel, libcamera, libqmi and hexagonrpcd are the pieces this port
# changes. Everything else comes from pmaports as it is.
#
#   ./20-overlay.sh            copy the overlays
#   ./20-overlay.sh --clean    remove them again
set -eu
. "$(dirname -- "$0")/env.sh"
. "$(dirname -- "$0")/lib.sh"

CLEAN=${1:-}

SRC=$PROJECT/surya-pmos
[ -d "$SRC" ] || die "surya-pmos não está em $SRC"

[ -d "$PMAPORTS" ] || die "o pmaports não está clonado — corra 10-fetch.sh primeiro"

mkdir -p "$OUT"

# ---------------------------------------------------------------------------
# The kernel series.
#
# The 140 patches carry a Subject: field with an inconsistent counter: 30 of
# them lost it entirely ([PATCH] instead of [PATCH N/M]) and the denominators
# are wrong (/106, /113, /2). The APKBUILD only cares about the file names, so
# the pmbootstrap build works either way — but `git am` does not, because the
# indices do not form a continuous series. Renormalising it here means the
# kernel source tree in the build can also be patched with git am.
#
# Only the Subject: line is touched. The diffs are left exactly as they are.
renormalise_series() {
    local dir=$1 count=$2 changed=0 f n i
    for f in "$dir"/*.patch; do
        [ -e "$f" ] || continue
        n=${f##*/}
        n=${n%%-*}
        i=$((10#$n))
        local before after
        before=$(sed -n 's/^Subject: \(\[[^]]*\]\).*/\1/p' "$f" | head -1)
        after="[PATCH $i/$count]"
        if [ "$before" != "$after" ]; then
            # The subject can span two lines: the indented continuation is
            # part of it. The sed only touches the first line, which is the
            # one that carries the counter.
            sed -i "s|^Subject: \[[^]]*\]|Subject: $after|" "$f"
            changed=$((changed + 1))
        fi
    done
    echo "$changed"
}

# ---------------------------------------------------------------------------

if [ "$CLEAN" = "--clean" ]; then
    say "a remover os overlays"
    rm -f "$KERNEL_PKG_DIR"/*.patch
    rm -f "$KERNEL_PKG_DIR"/APKBUILD
    rm -f "$KERNEL_PKG_DIR"/config-*
    rm -rf "$PMAPORTS/temp/libcamera" "$PMAPORTS/temp/libqmi" "$PMAPORTS/temp/hexagonrpcd"
    ok "removidos (o pmaports está outra vez como estava)"
    exit 0
fi

# --- 1. the kernel ---------------------------------------------------------

say "kernel: 140 patches, a receita e a config"
KDIR=$KERNEL_PKG_DIR
[ -d "$KDIR" ] || die "$KDIR não existe — corra 10-fetch.sh primeiro"

# The pmaports kernel is replaced wholesale: our APKBUILD lists all 140
# patches, and its own recipe and config do not apply.
rm -f "$KDIR"/*.patch "$KDIR"/APKBUILD "$KDIR"/config-*

cp "$SRC"/kernel/*.patch "$KDIR"/
cp "$SRC"/kernel/APKBUILD "$KDIR"/
cp "$SRC"/kernel/config-* "$KDIR"/

n=$(ls "$KDIR"/*.patch 2>/dev/null | wc -l)
[ "$n" -eq 140 ] || warn "esperados 140 patches, copiados $n"

# The APKBUILD has to list exactly the patches that are there, in order.
listed=$(grep -cE '^\s+[0-9]{4}-.*\.patch$' "$KDIR/APKBUILD" || true)
[ "$listed" -eq "$n" ] || warn "o APKBUILD lista $listed patches mas há $n ficheiros"

changed=$(renormalise_series "$KDIR" "$n")
if [ "$changed" -gt 0 ]; then
    ok "$n patches copiados, $changed com o contador do Subject: corrigido"
else
    ok "$n patches copiados, os contadores já estavam certos"
fi

# Verify the series really is continuous now, which is what `git am` needs.
bad_count=0
for f in "$KDIR"/*.patch; do
    num=${f##*/}; num=${num%%-*}
    i=$((10#$num))
    subj=$(sed -n 's/^Subject: \[\(PATCH[^]]*\)\].*/\1/p' "$f" | head -1)
    case "$subj" in
        "PATCH $i/$n") : ;;
        *) bad_count=$((bad_count + 1))
           [ "$bad_count" -le 3 ] && warn "$(basename "$f"): Subject: $subj" ;;
    esac
done
[ "$bad_count" -eq 0 ] && ok "a série é contínua" \
                        || warn "$bad_count patches com o Subject: irregular"

# --- 2. libcamera ----------------------------------------------------------
#
# The recipe was forked from a specific pmaports state, so the base has to
# come from that exact commit and not from whatever the checkout has today.
#
# The current pmaports dropped the PinePhone patches, renamed the others and
# changed the sensor tuning files, so building against it fails on the
# missing sources and on the checksums. The base is restored from the
# pinned commit instead.

say "libcamera: autofocus"
LC=$PMAPORTS/temp/libcamera
# The directory is rebuilt from scratch: what is there now comes from
# whatever the pmaports checkout had, and the recipe is pinned to a
# different set of files. Leaving the old ones behind would only confuse
# the checksum step.
rm -rf "$LC"
mkdir -p "$LC"

# The pinned commit has to be in the checkout.
if ! git -C "$PMAPORTS" cat-file -e "$LIBCAMERA_BASE^{commit}" 2>/dev/null; then
    say "a buscar o commit de base do libcamera ($LIBCAMERA_BASE)"
    git -C "$PMAPORTS" fetch -q origin "$LIBCAMERA_BASE" 2>/dev/null \
        || die "não foi possível buscar o commit $LIBCAMERA_BASE do pmaports"
fi
git -C "$PMAPORTS" cat-file -e "$LIBCAMERA_BASE^{commit}" 2>/dev/null \
    || die "o commit $LIBCAMERA_BASE não está no checkout"

# Take the base files out of that commit: the three patches, the tuning
# files and the desktop file.
BASE_FILES=$(git -C "$PMAPORTS" ls-tree --name-only "$LIBCAMERA_BASE:temp/libcamera")
n=0
for f in $BASE_FILES; do
    case "$f" in
        *.patch|*.yaml|*.desktop)
            git -C "$PMAPORTS" show "$LIBCAMERA_BASE:temp/libcamera/$f" \
                > "$LC/$f" || die "não foi possível extrair $f"
            n=$((n + 1))
            ;;
    esac
done
ok "$n ficheiros de base extraídos de $LIBCAMERA_BASE"

# Our patches go on top, numbered after the base ones.
for p in "$SRC"/packages/libcamera/*.patch; do
    [ -e "$p" ] || continue
    cp "$p" "$LC"/
done
cp "$SRC"/packages/libcamera/APKBUILD "$LC"/
n=$(ls "$LC"/*.patch 2>/dev/null | wc -l)
ok "$n patches em temp/libcamera"

# The recipe lists five sources; they all have to be there.
missing=""
for f in $(grep -oE '[0-9]{4}-[^ ]+\.patch' "$LC/APKBUILD" | sort -u); do
    [ -e "$LC/$f" ] || missing="$missing $f"
done
if [ -n "$missing" ]; then
    bad "a receita lista patches que não estão lá:$missing"
    die "o build do libcamera falharia"
fi
ok "todos os patches da receita estão presentes"

# The reverse check too: a patch in the directory that the recipe does not
# list is dead weight, and it is usually a rename that was only done in
# one of the two places.
for f in "$LC"/*.patch; do
    b=$(basename "$f")
    grep -q "$b" "$LC/APKBUILD" || bad "$b está no directório mas não na receita"
done

# --- 3. libqmi -------------------------------------------------------------
#
# libqmi is not in pmaports at all, so it is built out of temp/ from scratch.
# It is optional: the constellation messages are a bonus, everything else
# works without it.

say "libqmi: as mensagens das constelações GNSS"
LQ=$PMAPORTS/temp/libqmi
# libqmi is not in pmaports at all, so this directory is entirely ours.
rm -rf "$LQ"
mkdir -p "$LQ"
cp "$SRC"/packages/libqmi/*.patch "$LQ"/
cp "$SRC"/packages/libqmi/APKBUILD "$LQ"/
n=$(ls "$LQ"/*.patch 2>/dev/null | wc -l)
ok "$n patches em temp/libqmi"

# --- 4. hexagonrpcd --------------------------------------------------------
#
# Serves the ADSP's audio PD (the echo canceller) and can write the sensor
# registry. Also built out of temp/, over the distribution's package.
#
# At the moment this overlay is identical to what pmaports already has, so
# the copy is a no-op. It is kept because it is the place to put the next
# change, and because a mismatch between the two is worth knowing about.

say "hexagonrpcd: o PD de áudio do ADSP e o registo de sensores"
HX=$PMAPORTS/temp/hexagonrpcd
if [ -d "$HX" ]; then
    if diff -rq "$HX" "$SRC/packages/hexagonrpcd" >/dev/null 2>&1; then
        ok "temp/hexagonrpcd já é igual ao overlay"
    else
        warn "temp/hexagonrpcd difere do overlay — a cópia vai sobrescrever"
        cp -a "$SRC"/packages/hexagonrpcd/. "$HX"/
        ok "$(ls "$HX" | wc -l) ficheiros em temp/hexagonrpcd"
    fi
else
    mkdir -p "$HX"
    cp -a "$SRC"/packages/hexagonrpcd/. "$HX"/
    ok "$(ls "$HX" | wc -l) ficheiros em temp/hexagonrpcd"
fi

# --- 5. the rest -----------------------------------------------------------
#
# The device configuration — the wireplumber scripts, the audio UCM
# configuration, the services — is not an overlay. It is installed onto the
# phone afterwards, by surya-pmos/scripts/install-on-device.sh.

say "os overlays estão em $PMAPORTS"
echo
echo "  kernel        ${KDIR#$PMAPORTS/}"
echo "  libcamera     temp/libcamera"
echo "  libqmi        temp/libqmi"
echo "  hexagonrpcd   temp/hexagonrpcd"
echo
ok "pronto para o build"
