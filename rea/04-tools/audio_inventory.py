#!/usr/bin/env python3
"""Inventory the vendor audio configuration.

Answers, from the factory firmware alone: which routes exist, which
amplifier and codec controls each one writes, and how the microphone routes
are wired.

This is the table the mainline audio driver has to reproduce.  The mainline
WCD9375 driver already exposes the ASoC controls; what it does not have is
the vendor's routing table, and that table is what this tool prints.

Usage:
  audio_inventory.py <audio-config-dir>            the summary
  audio_inventory.py <audio-config-dir> --routes   every route
  audio_inventory.py <audio-config-dir> --json     machine-readable output
"""
import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from parse_mixer_paths import load, flatten  # noqa: E402

# The control names that name a piece of hardware.
# The control names of an amplifier, e.g. "TAS256X ASI1 SEL LEFT".
AMPLIFIER = re.compile(r"^(TAS2562|TAS256X|AW882|WCS|MQA)\b")
CODEC = re.compile(r"\b(WCD9\d{3}|WCD9\d{2})\w*", re.I)
MICROPHONE = re.compile(r"\b(DEC[01]|ADC[0-9]|DMIC\d?|SMIC\d?|SWR_MIC|"
                        r"IIR[01]|AIF\d?|CDC_[A-Z0-9_]+)\b")
# The routes that matter for a phone.
KEY_ROUTES = (
    "speaker", "earpiece", "headset", "headphones",
    "voice-rec-mic", "voice-speaker-mic", "voice-dmic-ef",
    "voice-rec-dmic-ef", "voice-headset-mic",
    "echo-reference speaker", "echo-reference handset",
    "echo-reference headphones",
    "low-latency-playback speaker", "low-latency-playback voice-rx",
    "deep-buffer-playback speaker",
    "audio-record voice-rec-mic",
    "incall-rec-uplink voice-rec-uplink",
)


def inventory(directory):
    """Build the inventory from every mixer paths file in the directory."""
    out = []
    for name in sorted(os.listdir(directory)):
        if not name.startswith("mixer_paths"):
            continue
        path = os.path.join(directory, name)
        routes, order = load(path)
        for rname in order:
            flat = flatten(routes, rname)
            names = [c["name"] for c in flat]
            out.append({
                "file": name,
                "route": rname,
                "controls": len(flat),
                "amplifier": sorted({n for n in names if AMPLIFIER.search(n)}),
                "codec": sorted({n for n in names if CODEC.search(n)}),
                "microphone": sorted({n for n in names if MICROPHONE.search(n)}),
            })
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("audio_config_dir")
    ap.add_argument("--routes", action="store_true",
                    help="list every route")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    inv = inventory(args.audio_config_dir)

    if args.json:
        print(json.dumps({"dir": args.audio_config_dir, "routes": inv}, indent=1))
        return 0

    print("%s: %d routes across the mixer paths files"
          % (args.audio_config_dir, len(inv)))

    if args.routes:
        for r in inv:
            print("  %-28s %-46s %3d controls" % (r["file"], r["route"],
                                                  r["controls"]))
        return 0

    print()
    print("the routes that matter for a phone:")
    seen = set()
    for r in inv:
        if r["route"] not in KEY_ROUTES or r["route"] in seen:
            continue
        seen.add(r["route"])
        print()
        print("  %s" % r["route"])
        if r["amplifier"]:
            print("    amplifier : %s" % ", ".join(r["amplifier"]))
        if r["codec"]:
            print("    codec     : %s" % ", ".join(r["codec"]))
        if r["microphone"]:
            print("    mic path  : %s" % ", ".join(r["microphone"][:12]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
