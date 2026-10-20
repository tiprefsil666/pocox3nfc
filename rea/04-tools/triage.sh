#!/usr/bin/env bash
# Fast static triage of one ELF: identity, sections, imports, exports, and
# the strings most likely to describe its protocol/state machine.
#
# Usage: triage.sh <elf> [outdir]
#   outdir defaults to ../05-scratch/triage/<basename>
#
# This is a triage aid only. It produces no authority over what the binary
# does; only REA (Hopper) analysis does that.
set -euo pipefail

elf="${1:?usage: triage.sh <elf> [outdir]}"
out="${2:-}"
if [ -z "$out" ]; then
    base="$(basename "$elf")"
    out="$(cd "$(dirname "$0")/.." && pwd)/05-scratch/triage/${base}"
fi
mkdir -p "$out"

b="$(basename "$elf")"

{
    echo "=== identity ==="
    file -b "$elf"
    echo
    echo "sha256: $(sha256sum "$elf" | cut -d' ' -f1)"
    echo "bytes:  $(stat -c%s "$elf")"
    echo
    echo "=== elf header ==="
    readelf -h "$elf" 2>/dev/null || echo "(readelf failed)"
    echo
    echo "=== needed libraries ==="
    readelf -d "$elf" 2>/dev/null | grep -E 'NEEDED|SONAME' || echo "(none)"
    echo
    echo "=== dynamic symbols (defined) ==="
    readelf --dyn-syms -W "$elf" 2>/dev/null | awk '$7 != "UND" && $4 != "FILE"' || echo "(none)"
    echo
    echo "=== imported functions ==="
    readelf --dyn-syms -W "$elf" 2>/dev/null | awk '$7 == "UND" {print $8}' | sed 's/@.*//' | sort -u || echo "(none)"
    echo
    echo "=== sections ==="
    readelf -S -W "$elf" 2>/dev/null | awk '/\[/{print}' || echo "(none)"
} > "$out/elf-report.txt" 2>&1

# Strings worth reading first: protocol, sysfs, i2c, charger, and error text.
strings -a -n 4 "$elf" > "$out/strings.txt"

{
    echo "=== sysfs paths ==="
    grep -E '^/(sys|dev|proc)/' "$out/strings.txt" | sort -u
    echo
    echo "=== property / setprop ==="
    grep -E '^[a-z]+\.[a-z0-9_.]+$' "$out/strings.txt" | grep -vE '^/(|[a-z]{1,3}\.[a-z]{1,3}$)' | sort -u | head -60
    echo
    echo "=== charge / usb / pd vocabulary ==="
    grep -iE 'hvdcp|usb.?pd|pdo|psr|voltage.?current|vbus|charger|battery|authentic|verif' "$out/strings.txt" | sort -u | head -80
} > "$out/vocabulary.txt" 2>&1

echo "wrote:"
echo "  $out/elf-report.txt"
echo "  $out/strings.txt"
echo "  $out/vocabulary.txt"
