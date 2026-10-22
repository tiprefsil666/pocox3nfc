#!/usr/bin/env bash
# Check that the patch series still applies to the kernel it was written
# against.
#
# The series is 140 patches, and the base is a *tag* in somebody else's
# repository. A tag can move, and a patch that no longer applies is a
# build that fails halfway through with an unhelpful error — or, worse,
# one that applies with an offset and silently changes the result.
#
# This checks every patch against the exact base, using a sparse checkout
# of only the files the patches touch.
#
#   ./15-verify-series.sh            check against the pinned base
#   ./15-verify-series.sh --apply   apply them, to a tree
#   ./15-verify-series.sh --kernel <tag>   against a different tag
set -eu
. "$(dirname -- "$0")/env.sh"
. "$(dirname -- "$0")/lib.sh"

APPLY=0
KTAG=${KERNEL_TAG:-v7.1_rc3}
KREPO=${KERNEL_REPO:-https://github.com/sm7150-mainline/linux}
for a in "$@"; do
    case "$a" in
        --apply) APPLY=1 ;;
        --kernel) shift; KTAG=$1 ;;
    esac
done

KERNEL=$PROJECT/surya-pmos/kernel
[ -d "$KERNEL" ] || die "não há patches em $KERNEL"

WORK=$OUT/series-check
SERIES=$WORK/tree
rm -rf "$WORK"
mkdir -p "$SERIES"

# ---------------------------------------------------------------------------
# The base.
#
# The *tarball*, not a git checkout: it is exactly what the build
# downloads and unpacks, so a check against it is a check against the
# build. A sparse git checkout would be quicker to fetch, but a file
# that failed to materialise would look like a patch that does not
# apply — a false failure, which is worse than no check at all.

say "a obter a base ($KTAG)"
TARBALL=$WORK/kernel-$KTAG.tar.gz
if [ ! -s "$TARBALL" ]; then
    curl -fL -sS -o "$TARBALL.tmp" \
        "$KREPO/archive/$KTAG.tar.gz" \
        || die "não foi possível descarregar $KTAG"
    mv "$TARBALL.tmp" "$TARBALL"
fi
ok "tarball ($(du -h "$TARBALL" | cut -f1))"

# The tarball unpacks into linux-<tag without the leading v>.
DEST=${KTAG#v}
if [ ! -d "$SERIES/linux-$DEST" ]; then
    say "a extrair"
    tar -xf "$TARBALL" -C "$SERIES"
    ok "extraído"
fi
TREE=$SERIES/linux-$DEST
[ -d "$TREE" ] || die "a extracção não produziu linux-$DEST"

# The commit the tag points at. A tag can move, and that is a build
# that changes under you, so it has to be written down.
BASE_COMMIT=$(git ls-remote "$KREPO" "refs/tags/$KTAG" 2>/dev/null | cut -f1)
ok "tag $KTAG -> ${BASE_COMMIT:-desconhecido}"

# ---------------------------------------------------------------------------
# The check.

say "a verificar os 140 patches"
ok_count=0
fail_count=0
failed=""

# The patches have to be checked **in order**, against the state the
# previous ones left behind. A patch that depends on an earlier one
# fails when checked against the bare base, even though the series
# applies perfectly well.
#
# So each one is checked and then applied, and the first failure stops
# the run: everything after it would be checked against a tree that is
# already wrong.
cd "$TREE"
for p in "$KERNEL"/*.patch; do
    name=$(basename "$p")
    if git apply --check "$p" 2>/dev/null; then
        git apply "$p" 2>/dev/null || die "o check passou mas a aplicação falhou: $name"
        ok_count=$((ok_count + 1))
    else
        fail_count=$((fail_count + 1))
        failed="$failed $name"
        echo
        say "a primeira falha: $name"
        git apply --check "$p" 2>&1 | sed 's/^/    /' | head -10
        break
    fi
done

echo
if [ "$fail_count" -eq 0 ]; then
    ok "$ok_count patches aplicam"
else
    bad "$fail_count patches não aplicam:"
    for f in $failed; do echo "       $f"; done
    echo
    echo "  A base pode ter-se movido. O que a build usa é o tag, e o tag"
    echo "  está em $BASE_COMMIT."
fi

if [ "$fail_count" -eq 0 ]; then
    ok "a série completa aplica-se em $TREE"
    if [ "$APPLY" = "0" ]; then
        say "(a árvore ficou com a série aplicada, para inspecionar)"
    fi
fi

# Record it, so a later run can be compared with this one.
{
    echo "tag:    $KTAG"
    echo "commit: $BASE_COMMIT"
    echo "aplicam: $ok_count"
    echo "não aplicam: $fail_count"
} | tee "$OUT/series-check.txt"

[ "$fail_count" -eq 0 ] || exit 1
