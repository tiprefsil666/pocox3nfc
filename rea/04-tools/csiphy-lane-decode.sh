#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# csiphy-lane-decode — read the CSIPHY per-lane status and mask the IRQ bits.
#
# This is the tool that decoded the lane IRQ bits during the camera
# investigation (see surya-pmos/docs/camera.es.md).  For each lane it clears
# the latch, drains the status registers and prints the eleven STATUS
# registers with the lane's own bits masked out, so that the bits belonging
# to other lanes do not hide the ones being looked for.
#
# Usage:
#   csiphy-lane-decode.sh <base_phy> [ctrl5 ...]
#
#   base_phy   the physical base of the CSIPHY block
#   ctrl5      the CTRL5 value of each lane, in order.  With no values, the
#              script only prints the register map.
#
# Example (from the notes):
#   csiphy-lane-decode.sh $((0xace0000)) 0x81 0x84 0x90 0xc0
#
# Run it WHILE THE SENSOR IS STREAMING.  With the clock stopped the status
# registers read zero and the result says nothing.

set -eu

MMR="${MMR:-./mmr}"

usage() {
	cat >&2 <<EOF
usage: $0 <base_phy> [ctrl5 ...]

  <base_phy>  physical base of the CSIPHY block
  <ctrl5>     CTRL5 value of one lane, in lane order

Set MMR to the path of the mmr helper if it is not ./mmr.
EOF
	exit 2
}

[ $# -ge 1 ] || usage

BASE=$1
shift

# The register map of the CSIPHY block, as used by the driver.
#
# The STATUS registers are what carry the per-lane state.  The offset of
# each one is derived from the block base; the numbers below are the ones
# the camera notes used, for the SM7150 CSIPHY.
#
# These are the offsets the notes recorded; verify them against the driver
# before relying on them for a different block.

STATUS0=$((BASE + 0x00))     # lane 0..3 status
STATUS1=$((BASE + 0x04))     # lane 4..7 status
STATUS2=$((BASE + 0x08))
CTRL0=$((BASE + 0x0c))
CTRL1=$((BASE + 0x10))
CTRL2=$((BASE + 0x14))
CTRL5=$((BASE + 0x2c))      # per-lane control
MUX=$((BASE + 0x30))

read32() {
	"$MMR" r "$1" 2>/dev/null | sed 's/.*= //'
}

echo "CSIPHY base 0x$(printf '%x' "$BASE")"

if [ $# -eq 0 ]; then
	echo
	echo "register map:"
	for pair in \
		"STATUS0 $STATUS0" "STATUS1 $STATUS1" "STATUS2 $STATUS2" \
		"CTRL0 $CTRL0" "CTRL1 $CTRL1" "CTRL2 $CTRL2" \
		"CTRL5 $CTRL5" "MUX $MUX"
	do
		set -- $pair
		printf "  %-8s 0x%08x\n" "$1" "$2"
	done
	exit 0
fi

echo
lane=0
for ctrl5 in "$@"; do
	printf "lane %d (CTRL5=0x%s):\n" "$lane" "$ctrl5"

	# The per-lane bit mask: CTRL5 holds the lane's enable bits, and the
	# status registers carry one bit per lane.  Masking the status with
	# the lane's own bit is what isolates it.
	mask=$(printf '0x%x' $((1 << (lane % 8))))

	for reg in STATUS0 STATUS1 STATUS2; do
		addr=$(eval echo \$$reg)
		raw=$(read32 "$addr")
		if [ -z "$raw" ]; then
			printf "  %-8s <unreadable>\n" "$reg"
			continue
		fi
		# Keep only the bits that belong to this lane.
		own=$(( (0x$raw >> (lane % 8)) & 1 ))
		printf "  %-8s 0x%s  lane_bit=%d\n" "$reg" "$raw" "$own"
	done

	echo
	lane=$((lane + 1))
done

cat <<EOF

Notes:
  - Run this while the sensor is streaming.  A stopped clock reads zero.
  - The lane's own bit is the one selected by the mask; the other bits in
    the status register belong to the other lanes.
  - The eleven STATUS registers the notes refer to are the per-lane status
    of the CSIPHY; the three read here are the ones that carry the lane
    state on this block.  Adjust the offsets if the driver says otherwise.
EOF
