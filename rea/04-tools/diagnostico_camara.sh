#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# diagnostico-camara — read-only snapshot of the camera subsystem.
#
# The camera investigation needed a way to see the state of the camera stack
# at a glance, without changing anything.  This script only reads: it never
# writes a register and never restarts a service.
#
# It reports:
#   - the sensors the kernel knows about
#   - the media pipeline and the format of each video node
#   - the CSI PHY and the interrupt state
#   - the power supply and thermal state
#   - the loaded camera modules
#
# Usage:
#   diagnostico-camara.sh [output-dir]
#
# With an output directory, everything is written there as well as printed.

set -u

OUT=${1:-}

if [ -n "$OUT" ]; then
	mkdir -p "$OUT"
fi

emit() {
	# emit <title> <command...>
	title=$1
	shift
	echo
	echo "=== $title ==="
	if [ -n "$OUT" ]; then
		{
			echo "=== $title ==="
			"$@" 2>&1
		} >> "$OUT/diagnostico.txt"
	fi
	"$@" 2>&1 | sed 's/^/  /'
}

emit "sensor devices" sh -c \
	'ls -l /sys/class/video4linux 2>/dev/null; echo; cat /proc/bus/input/devices 2>/dev/null | head -0'

emit "media entities" sh -c \
	'for d in /sys/class/video4linux/v4l-subdev*; do [ -e "$d" ] || continue; echo "$d: $(cat $d/name 2>/dev/null)"; done'

emit "video node formats" sh -c \
	'for d in /sys/class/video4linux/video*; do [ -e "$d" ] || continue; n=$(cat $d/name 2>/dev/null); f=$(cat $d/format 2>/dev/null); s=$(cat $d/size 2>/dev/null); echo "$n ($d): format=$f size=$s"; done'

emit "csiphy nodes" sh -c \
	'for d in /sys/devices/*qcom,camss*; do [ -e "$d" ] || continue; echo "$d"; ls $d 2>/dev/null | head -20; done'

emit "csiphy interrupt state" sh -c \
	'for f in /sys/kernel/debug/*csiphy*/status /sys/kernel/debug/*camss*/status; do [ -e "$f" ] || continue; echo "--- $f"; cat $f 2>/dev/null; done'

emit "qcom_camss parameters" sh -c \
	'cat /sys/module/qcom_camss/parameters/* 2>/dev/null'

emit "loaded camera modules" sh -c \
	'cat /proc/modules 2>/dev/null | grep -Ei "cam|csiphy|v4l2|imgsensor"'

emit "power supply" sh -c \
	'for d in /sys/class/power_supply/*; do [ -e "$d" ] || continue; n=$(cat $d/name 2>/dev/null); t=$(cat $d/type 2>/dev/null); s=$(cat $d/status 2>/dev/null); echo "$n ($d): type=$t status=$s"; done'

emit "thermal zones" sh -c \
	'for z in /sys/class/thermal/thermal_zone*; do [ -e "$z" ] || continue; echo "$(cat $z/type 2>/dev/null): $(cat $z/temp 2>/dev/null)"; done'

emit "camera service state" sh -c \
	'ps -A 2>/dev/null | grep -Ei "camera|cameraserver|provider" ; echo; getprop 2>/dev/null | grep -Ei "camera" | head -20'

emit "i2c devices" sh -c \
	'for d in /sys/bus/i2c/devices/*; do [ -e "$d" ] || continue; n=$(cat $d/name 2>/dev/null); a=$(cat $d/address 2>/dev/null); echo "$n: $a"; done'

emit "dmesg camera lines" sh -c \
	'dmesg 2>/dev/null | grep -Ei "camss|csiphy|imgsensor|camera" | tail -60'

if [ -n "$OUT" ]; then
	echo
	echo "written to $OUT/diagnostico.txt"
fi
