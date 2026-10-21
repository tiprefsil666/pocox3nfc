#!/usr/bin/env python3
"""Summarise the factory GNSS configuration.

The GNSS configuration of the board is three files: gps.conf, flp.conf and
gps_diag.cfg.  The first decides who produces the NMEA sentences and how
the A-GPS is configured; the second configures the batched location
provider; the third is the modem's own diagnostics configuration.

The facts that matter for a port are few and easy to miss, so this tool
prints them explicitly rather than dumping the files.

Usage:
  gnss_config.py <config-dir>            the summary
  gnss_config.py <config-dir> --all      every key of every file
  gnss_config.py <config-dir> --json     machine-readable output
"""
import argparse
import json
import os
import re
import sys

# The keys that decide how the receiver behaves.
INTERESTING = (
    "NMEA_PROVIDER",
    "AGPS_CONFIG_INJECT",
    "CUSTOM_NMEA_GGA_FIX_QUALITY_ENABLED",
    "AGPS_CERT_WRITABLE_MASK",
    "SUPL_MODE",
    "GPS_CAPABILITIES",
    "ACCURACY_THRES",
    "BATCH_SIZE",
    "OUTDOOR_TRIP_BATCH_SIZE",
    "ENABLE_ONSREEN",
    "ENABLE_GEOFENCE",
    "ENABLE_MEASUREMENT",
    "SUPL_HOST",
    "SUPL_PORT",
    "ACCURACY_THRESHOLD",
)


def read_kv(path):
    """Read a key = value configuration file."""
    out = []
    if not os.path.exists(path):
        return out
    for line in open(path, errors="replace"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        out.append((k.strip(), v.strip()))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("config_dir")
    ap.add_argument("--all", action="store_true", help="every key")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    files = {
        "gps.conf": read_kv(os.path.join(args.config_dir, "gps.conf")),
        "flp.conf": read_kv(os.path.join(args.config_dir, "flp.conf")),
        "gps_diag.cfg": read_kv(os.path.join(args.config_dir, "gps_diag.cfg")),
    }

    if args.json:
        print(json.dumps({"dir": args.config_dir, "files": files}, indent=1))
        return 0

    if args.all:
        for name, kvs in files.items():
            print("== %s ==" % name)
            for k, v in kvs:
                print("  %-42s = %s" % (k, v))
            print()
        return 0

    print("== the receiver ==")
    for name, kvs in files.items():
        for k, v in kvs:
            if k in INTERESTING:
                print("  %-40s = %s" % (k, v))

    print()
    print("== what the NMEA_PROVIDER value means ==")
    nmea = dict(files.get("gps.conf", [])).get("NMEA_PROVIDER")
    if nmea == "0":
        print("  NMEA_PROVIDER=0: the application processor synthesises the NMEA")
        print("  sentences.  The modem's receiver does not emit them, so")
        print("  something on the AP side has to.")
    elif nmea == "1":
        print("  NMEA_PROVIDER=1: the modem produces the NMEA sentences.")
    else:
        print("  NMEA_PROVIDER is not set; the default is the modem.")

    print()
    print("== the A-GPS ==")
    gps = dict(files.get("gps.conf", []))
    inject = gps.get("AGPS_CONFIG_INJECT")
    if inject == "1":
        print("  AGPS_CONFIG_INJECT=1: the AP injects the A-GPS configuration")
        print("  into the modem.  The carrier's SUPL server is not configured in")
        print("  the factory file, so the assistance has to come from somewhere")
        print("  else.")
    else:
        print("  AGPS_CONFIG_INJECT is %s" % inject)

    print()
    print("== the batching ==")
    flp = dict(files.get("flp.conf", []))
    for k, v in flp.items():
        if "BATCH" in k.upper():
            print("  %-40s = %s" % (k, v))
    return 0


if __name__ == "__main__":
    sys.exit(main())
