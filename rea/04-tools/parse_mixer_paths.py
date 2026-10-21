#!/usr/bin/env python3
"""Summarise a Qualcomm mixer_paths file.

The vendor's audio configuration is a tree of playback and capture routes.
A route either carries controls, or refers to other routes by name:

    <path name="voice-rec-mic">
        <path name="handset-mic" />
    </path>

    <path name="speaker">
        <ctl name="TAS256X RX MODE RIGHT" value="Speaker" />
        ...
    </path>

This tool flattens that tree: for each route it lists the controls that
apply to it, with the ones inherited from the routes it refers to.  It is
the quickest way to see which amplifier, which codec and which microphone a
given route uses, and it is what the audio notes in
surya-pmos/docs/audio.es.md are written against.

Usage:
  parse_mixer_paths.py <file>               every route
  parse_mixer_paths.py <file> --route NAME  one route, flattened
  parse_mixer_paths.py <file> --devices     the devices and the routes
  parse_mixer_paths.py <file> --json        machine-readable output
"""
import argparse
import json
import sys
import xml.etree.ElementTree as ET


def load(path):
    """Parse the file into {route name: {"controls": [...], "refs": [...]}}."""
    root = ET.parse(path).getroot()

    routes = {}
    order = []
    for path_el in root.findall("path"):
        name = path_el.get("name")
        if name is None:
            continue
        controls = []
        refs = []
        for ctl in path_el.findall("ctl"):
            controls.append({
                "name": ctl.get("name"),
                "id": ctl.get("id"),
                "value": ctl.get("value"),
            })
        for ref in path_el.findall("path"):
            refs.append(ref.get("name"))
        if name in routes:
            # A route may be extended; keep both.
            routes[name]["controls"].extend(controls)
            routes[name]["refs"].extend(refs)
        else:
            routes[name] = {"controls": controls, "refs": refs}
            order.append(name)
    return routes, order


def flatten(routes, name, seen=None):
    """Flatten a route: its own controls plus those of the routes it names."""
    if seen is None:
        seen = set()
    if name in seen or name not in routes:
        return []
    seen.add(name)
    out = []
    for c in routes[name]["controls"]:
        out.append(c)
    for ref in routes[name]["refs"]:
        out.extend(flatten(routes, ref, seen))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file")
    ap.add_argument("--route", help="show one route, flattened")
    ap.add_argument("--devices", action="store_true",
                    help="show the devices and the routes that use them")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    routes, order = load(args.file)

    if args.json:
        out = []
        for name in order:
            out.append({
                "name": name,
                "refs": routes[name]["refs"],
                "controls": flatten(routes, name),
            })
        print(json.dumps({"file": args.file, "routes": out}, indent=1))
        return 0

    if args.route:
        if args.route not in routes:
            print("route %r not found" % args.route)
            return 1
        print("route %s" % args.route)
        if routes[args.route]["refs"]:
            print("  refers to: %s" % ", ".join(routes[args.route]["refs"]))
        for c in flatten(routes, args.route):
            print("  %-46s id=%-4s value=%s"
                  % (c["name"], c["id"], c["value"]))
        return 0

    if args.devices:
        by_dev = {}
        for name in order:
            for c in flatten(routes, name):
                v = c.get("value") or ""
                if v and (v.startswith("/dev/snd") or v in (
                        "Speaker", "Earpiece", "Headset", "Mic",
                        "Built-in Mic", "headset-mic", "dmic-endfire")):
                    by_dev.setdefault(v, set()).add(name)
        for d in sorted(by_dev):
            print("%-30s %d route(s)" % (d, len(by_dev[d])))
        return 0

    print("%s: %d routes" % (args.file, len(order)))
    for name in order:
        flat = flatten(routes, name)
        distinct = len({c["name"] for c in flat})
        print("  %-50s %3d controls, %d distinct%s"
              % (name, len(flat), distinct,
                 "  <- %s" % ", ".join(routes[name]["refs"])
                 if routes[name]["refs"] else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
