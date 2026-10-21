#!/usr/bin/env python3
"""Summarise every camera sensormodule blob of the factory firmware.

For each blob it reports the sensor, the module, the number of power-up
steps and the number of registers in each step.  This is the table the
mainline drivers are written against: which sensor, which I2C slave, which
registers and in which order.

Usage:
  camera_inventory.py <camera-dir>            a table of every blob
  camera_inventory.py <camera-dir> --json     machine-readable output
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from parse_sensormodule import (  # noqa: E402
    parse_header, parse_tags, decode_reg_setting, decode_string, u32)
from dump_regtable import group_settings  # noqa: E402


def summarise(path):
    """Summarise one blob."""
    d = open(path, "rb").read()
    hdr = parse_header(d)
    tags = parse_tags(d, hdr)
    idmap = {t.tag_id: t.name for t in tags}

    def first_string(name):
        for t in tags:
            if t.name == name:
                return decode_string(d, t)
        return ""

    # The regSetting whose records actually name the register tables.
    best = None
    for cand in (t for t in tags if t.name == "regSetting"):
        recs = decode_reg_setting(d, cand)
        n = sum(1 for k, _ in recs if idmap.get(k) == "registerData")
        if best is None or n > best[0]:
            best = (n, cand, recs)

    steps = []
    if best is not None:
        for e in group_settings(best[2], idmap):
            count = 0
            for t in tags:
                if t.tag_id == e.get("registerData"):
                    count = u32(d, t.payload_offset)
                    break
            steps.append({"reg_table": e.get("registerData"),
                          "count": count,
                          "delay": e.get("delay_id")})

    # Distinct sensors in the blob, by their sensorName section.
    sensors = []
    for t in tags:
        if t.name == "sensorName":
            s = decode_string(d, t)
            if s and s not in sensors:
                sensors.append(s)

    return {
        "file": os.path.basename(path),
        "sensor": first_string("sensorName"),
        "module": first_string("moduleName"),
        "eeprom": first_string("eepromName"),
        "flash": first_string("flashName"),
        "pdaf": first_string("PDAFName"),
        "tags": len(tags),
        "sensors": sensors,
        "steps": steps,
        "total_registers": sum(s["count"] for s in steps),
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("camera_dir")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    blobs = sorted(
        os.path.join(args.camera_dir, f)
        for f in os.listdir(args.camera_dir)
        if f.startswith("com.qti.sensormodule") and f.endswith(".bin"))

    if not blobs:
        print("no sensormodule blobs in %s" % args.camera_dir)
        return 1

    out = []
    for b in blobs:
        try:
            out.append(summarise(b))
        except SystemExit as e:
            print("skip %s: %s" % (b, e))

    if args.json:
        print(json.dumps(out, indent=1))
        return 0

    print("%-32s %-16s %-6s %5s %9s" % ("blob", "sensor", "module", "steps", "regs"))
    print("-" * 74)
    for r in out:
        name = r["file"].replace("com.qti.sensormodule.j20c_", "")
        name = name[:-4] if name.endswith(".bin") else name
        print("%-32s %-16s %-6s %5d %9d"
              % (name, r["sensor"], r["module"], len(r["steps"]),
                 r["total_registers"]))
    print("\n%d blob(s), %d steps, %d register writes in total"
          % (len(out), sum(len(r["steps"]) for r in out),
             sum(r["total_registers"] for r in out)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
