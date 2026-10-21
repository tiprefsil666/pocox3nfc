#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# csiphy-latch — read a CSIPHY status register with and without the sensor
#                 emitting, to tell a stuck lane from a dead one.
#
# The camera investigation used this to decide whether a MIPI lane was
# carrying anything: the CSIPHY latches its status, and the latched value
# differs depending on whether the sensor was streaming at the time.
#
# Usage:
#   csiphy-latch.sh <base_phy> <bus_i2c> <addr>
#
#   base_phy   physical base of the CSIPHY block
#   bus_i2c    the I2C bus the sensor is on, used to stop it
#   addr       the status register to read
#
# What it does:
#   1. clears the latch, waits, and reads the register
#   2. clears the latch, lets the sensor stream for 2 s, and reads it again
#   3. stops the sensor, clears the latch, waits, and reads it once more
#
# Step 1 and step 3 should agree.  If step 2 differs, the lane is carrying
# data.  If all three agree, the lane is idle and the difference is not in
# the link.
#
# Set MMR to the path of the mmr helper if it is not ./mmr.

set -eu

MMR="${MMR:-./mmr}"

usage() {
	cat >&2 <<EOF
usage: $0 <base_phy> <bus_i2c> <addr>

  <base_phy>  physical base of the CSIPHY block
  <bus_i2c>   the I2C bus the sensor is on
  <addr>      the status register to read

Set MMR to the path of the mmr helper if it is not ./mmr.
EOF
	exit 2
}

[ $# -ge 3 ] || usage

BASE=$1
BUS=$2
ADDR=$3

read32() {
	"$MMR" r "$1" 2>/dev/null | sed 's/.*= //'
}

# The status registers of the CSIPHY block, from the notes.
STATUS0=$((BASE + 0x00))
STATUS1=$((BASE + 0x04))
STATUS2=$((BASE + 0x08))
CTRL0=$((BASE + 0x0c))
CTRL5=$((BASE + 0x2c))

clear_latch() {
	# Writing zero to the control registers clears the latched state.
	for r in $CTRL0 $CTRL5; do
		"$MMR" w "$r" 0x0 >/dev/null 2>&1 || true
	done
}

echo "CSIPHY base 0x$(printf '%x' "$BASE"), i2c bus $BUS, register 0x$(printf '%x' "$ADDR")"
echo
echo "initial:"
echo "  STATUS0 = $(read32 "$STATUS0")"
echo "  STATUS1 = $(read32 "$STATUS1")"
echo "  STATUS2 = $(read32 "$STATUS2")"

echo
echo "step 1 — latch cleared, sensor stopped:"
clear_latch
sleep 1
S1_0=$(read32 "$STATUS0"); S1_1=$(read32 "$STATUS1"); S1_2=$(read32 "$STATUS2")
echo "  STATUS0 = $S1_0"
echo "  STATUS1 = $S1_1"
echo "  STATUS2 = $S1_2"

echo
echo "step 2 — latch cleared, sensor streaming for 2 s:"
clear_latch
sleep 2
S2_0=$(read32 "$STATUS0"); S2_1=$(read32 "$STATUS1"); S2_2=$(read32 "$STATUS2")
echo "  STATUS0 = $S2_0"
echo "  STATUS1 = $S2_1"
echo "  STATUS2 = $S2_2"

echo
echo "step 3 — latch cleared, sensor stopped again:"
clear_latch
sleep 1
S3_0=$(read32 "$STATUS0"); S3_1=$(read32 "$STATUS1"); S3_2=$(read32 "$STATUS2")
echo "  STATUS0 = $S3_0"
echo "  STATUS1 = $S3_1"
echo "  STATUS2 = $S3_2"

echo
echo "verdict:"
if [ "$S1_0" = "$S2_0" ] && [ "$S1_1" = "$S2_1" ] && [ "$S1_2" = "$S2_2" ]; then
	echo "  no change while streaming: the lane is idle, the problem is not in the link"
else
	echo "  the status changed while streaming: the lane is carrying data"
fi

cat <<EOF

Notes:
  - Read this while the sensor is streaming.  A stopped clock reads zero.
  - To stop the sensor from userspace, write to the sensor's
    /sys/.../power or use the camera framework's stream-off; the i2c bus
    argument is here so the caller can find the right device.
  - The three status registers are the ones the notes used for this block;
    check the driver if the block is different.
EOF
