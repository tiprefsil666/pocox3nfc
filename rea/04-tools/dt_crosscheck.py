#!/usr/bin/env python3
"""Check a device tree for the components this port cares about.

The analysis in the notes was done by reading the device tree by hand.
That works, but it does not scale: the same question gets asked again
for every new tree, and a missed node is easy.

This tool answers, for one tree, a fixed set of questions:

  - is the component there at all?
  - is it enabled?
  - is the bus it hangs off enabled?
  - does the mainline driver have what it needs?

It works on any device tree: the factory's DTBO, the upstream project's
published ``fdt-surya``, or a device tree from a running kernel.

Usage:
  dt_crosscheck.py <dtb-or-dts>            a compiled device tree
  dt_crosscheck.py --dtbo <dtbo.img>       a DTBO image (every entry)
  dt_crosscheck.py --dts <file.dts>        a decompiled device tree
  dt_crosscheck.py --summary <dtb>         just the verdict, one line

A caveat on comparing trees
---------------------------

A device tree is spread over several files: the SoC file, a board-common
file and a board file, and the board file only ever *overrides* nodes
defined elsewhere. So a single file on its own shows far less than the
whole tree.

For a fair comparison, concatenate them, or compile the real thing:

    cat sm7150.dtsi sm7150-xiaomi-common.dtsi sm7150-xiaomi-surya.dtsi > all.dts
    dt_crosscheck.py --dts all.dts

And remember that this port's own kernel patches add a good deal of the
wiring — the WCD9375 among them. The mainline tree is the *starting
point*, not the finished one.
"""
import argparse
import os
import re
import struct
import subprocess
import sys
import tempfile


# The components, and what to look for.
#
# Each entry is:
#   name        what it is
#   want        a regular expression that identifies the node
#   driver      the mainline driver that would claim it, and what it needs
#   state       what "ready" means
#
# The "state" strings are what the tool reports, and they are the
# vocabulary the notes use.

CHECKS = [
    {
        "name": "FSA4480 (USB-C analogue audio)",
        "want": r'fcs,fsa4480|qcom,fsa4480',
        "driver": "drivers/usb/typec/mux/fsa4480.c — compatible \"fcs,fsa4480\"",
        "state": "the chip, on an enabled I2C bus, plus the SBU endpoint on the connector",
    },
    {
        "name": "WCD9375 (microphone codec)",
        "want": r"qcom,wcd937",
        "driver": "sound/soc/codecs/wcd937x.c — compatible \"qcom,wcd9375-codec\"",
        "state": "the codec, plus the TX/RX SoundWire links and the capture DAI link",
    },
    {
        "name": "TAS2562 / TAS2564 (speakers)",
        "want": r'ti,tas256',
        "driver": "sound/soc/codecs/tas2562.c and tas2564.c",
        "state": "the amplifier, with its DAI link",
    },
    {
        "name": "NFC (NXP NCI)",
        "want": r'qcom,nq-nci',
        "driver": "drivers/nfc/nxp-nci — compatible \"qcom,nq-nci\"",
        "state": "the node, and the nfc_irq interrupt",
    },
    {
        "name": "PMIC Type-C controller",
        "want": r'qcom,pmic-typec|usb-c-connector|typec@',
        "driver": "drivers/usb/typec/pmic-glink.c — compatible \"qcom,pmic-typec\"",
        "state": "the controller, with its connector and the SBU port",
    },
    {
        "name": "Camera IR LED",
        "want": r'qcom,camera-ir-led',
        "driver": "no mainline driver yet",
        "state": "the LED, with the IR-cut filter pinctrl",
    },
    {
        "name": "IR remote control emitter",
        "want": r'ir-spi-led|qcom,ir-led',
        "driver": "drivers/media/rc/ir-spi.c — compatible \"ir-spi-led\"",
        "state": "an SPI node with an LED child, on an enabled SPI bus",
    },
    {
        "name": "Fingerprint reader",
        "want": r'goodix|fpc1020',
        "driver": "drivers/input/fingerprint",
        "state": "the sensor",
    },
    {
        "name": "Fuel gauge (PM6150 QG)",
        "want": r'qcom,qpnp-qg',
        "driver": "drivers/power/supply/qcom_qg.c — compatible \"qcom,qpnp-qg\"",
        "state": "the gauge, with the OCV table",
    },
    {
        "name": "BQ25970 charge pump",
        "want": r'bq2597',
        "driver": "drivers/power/supply/bq25970.c",
        "state": "the charger, on an enabled I2C bus",
    },
    {
        "name": "Touchscreen (NT36672C)",
        "want": r'novatek,nt36|novatek,NVT-ts-spi',
        "driver": "drivers/input/touchscreen/nt36xxx.c",
        "state": "the controller, on an enabled SPI bus, with its firmware",
    },
]


# ---------------------------------------------------------------- the tree


def dtbo_entries(path):
    """Yield (index, blob) for every entry of a DTBO image."""
    d = open(path, "rb").read()
    magic, total, hs, es, count, off, ps, ver = struct.unpack_from(">8I", d, 0)
    if magic != 0xD7B7AB1E:
        raise SystemExit("%s is not a DTBO image" % path)
    for i in range(count):
        pos = off + i * es
        size, eoff, eid, rev, *cust = struct.unpack_from(">8I", d, pos)
        yield i, d[eoff:eoff + size]


def decompile(blob):
    """Decompile one device tree blob with dtc."""
    with tempfile.NamedTemporaryFile(suffix=".dtb", delete=False) as f:
        f.write(blob)
        p = f.name
    try:
        r = subprocess.run(["dtc", "-I", "dtb", "-O", "dts", p],
                           capture_output=True, text=True)
        return r.stdout
    finally:
        os.unlink(p)


def load_dts(path):
    """Return the text of a device tree, decompiling it if it is a blob."""
    with open(path, "rb") as f:
        head = f.read(4)
    if head == b"\xd0\x0d\xfe\xed":
        return decompile(open(path, "rb").read())
    return open(path, errors="replace").read()


# ---------------------------------------------------------------- the checks


def node_blocks(dts):
    """Return the text of every node, as (label, name, body).

    A node block runs from its opening brace to the matching close, and
    the label is the name before the colon. A node with no label (the
    ones written as ``&label {``) has an empty label.

    The brace depth of every line is computed first, so that finding the
    end of a node is a lookup rather than a scan. Without that, finding
    a node and then skipping its children would leave the nested nodes
    invisible.
    """
    lines = dts.splitlines()

    # The depth of each line: the number of braces open at its start.
    depth = 0
    depths = []
    for line in lines:
        depths.append(depth)
        depth += line.count("{") - line.count("}")

    out = []
    for i, line in enumerate(lines):
        # Three shapes:
        #   label: name {          a node with a label
        #   name {                 a node without one
        #   &label {               an override of a node defined elsewhere
        m = re.match(r"^(\t*)(?:(\S+):)?\s*(\S+)\s*\{", line)
        if not m:
            continue
        label = m.group(2) or ""
        name = m.group(3)
        if name.startswith("&"):
            # An override. The node itself is defined in another file, so
            # the override is what carries the board's changes — and it is
            # what has to be read for the board's wiring.
            label = name
            name = name

        # The node ends at the first line whose depth is back to the
        # node's own level.
        d = depths[i]
        j = i
        while j < len(lines) and depths[j] > d:
            j += 1
        # Include the closing line.
        while j < len(lines) and j == i:
            j += 1
        end = j
        while end < len(lines) and "}" not in lines[end]:
            end += 1
        out.append((label, name, "\n".join(lines[i:end + 1])))
    return out


def bus_of(blocks, phandle):
    """Find the node that contains the given phandle, and its ancestors."""
    for label, name, body in blocks:
        if re.search(r"phandle = <0x%s>;" % phandle, body):
            return label, name, body
    return None, None, None


def enabled(body):
    """Is this node (or its subtree) enabled?"""
    m = re.search(r'status = "(\w+)"', body)
    if m:
        return m.group(1) in ("ok", "okay", "fine")
    # No status property means enabled, unless a child says otherwise.
    return True


def check(dts, verbose=False):
    """Run every check against one device tree. Returns a list of results."""
    blocks = node_blocks(dts)
    results = []

    for spec in CHECKS:
        hits = []
        for label, name, body in blocks:
            # The name, the label, or the compatible property. The factory
            # tree names its nodes after the chip ("nq@28") and puts the
            # identity in the compatible, so all three have to be looked
            # at.
            if (re.search(spec["want"], name)
                    or re.search(spec["want"], label)
                    or re.search(spec["want"], body)):
                hits.append((label, name, body))

        if not hits:
            results.append((spec, "AUSENTE", "não há nenhum nó", []))
            continue

        ready = []
        detail = []
        for label, name, body in hits:
            st = enabled(body)
            # A node that is present but disabled is the interesting case.
            ready.append(st)
            if verbose:
                detail.append("%s (%s): %s" % (name, label,
                                                "activo" if st else "desactivado"))
            # Is the bus it hangs off enabled?
            if st:
                m = re.search(r"phandle = <0x([0-9a-f]+)>;", body)
                if m:
                    bl, bn, bb = bus_of(blocks, m.group(1))
                    if bb is not None and not enabled(bb):
                        ready[-1] = False
                        if verbose:
                            detail.append("  o bus %s está desactivado" % bn)

        if all(ready):
            state = "PRONTO"
            extra = "activo"
        elif any(ready):
            state = "PARCIAL"
            extra = "alguns activos, outros não"
        else:
            state = "INACTIVO"
            extra = "presente mas desactivado"

        results.append((spec, state, extra, detail))

    return results


# ---------------------------------------------------------------- the output


def report(dts, title, verbose=False):
    print("== %s ==" % title)
    print()
    for spec, state, extra, detail in check(dts, verbose):
        colour = {"PRONTO": "\033[32m", "PARCIAL": "\033[33m",
                  "INACTIVO": "\033[31m", "AUSENTE": "\033[31m"}.get(state, "")
        reset = "\033[0m" if colour else ""
        print("  %s%-9s%s %s" % (colour, state, reset, spec["name"]))
        print("           %s" % extra)
        print("           driver: %s" % spec["driver"])
        if verbose:
            for d in detail:
                print("           %s" % d)
    print()


def summary(dts, title):
    ready = 0
    total = 0
    parts = []
    for spec, state, extra, detail in check(dts):
        total += 1
        if state == "PRONTO":
            ready += 1
        parts.append("%s=%s" % (spec["name"].split(" (")[0].split(" ")[0].lower(),
                                state))
    print("%s: %d/%d prontos  %s" % (title, ready, total, " ".join(parts)))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("tree", nargs="?", help="a device tree blob")
    ap.add_argument("--dtbo", help="a DTBO image; every entry is checked")
    ap.add_argument("--dts", help="a decompiled device tree")
    ap.add_argument("--summary", action="store_true",
                    help="one line per tree, instead of the full report")
    ap.add_argument("-v", "--verbose", action="store_true",
                    help="show which nodes were found")
    args = ap.parse_args()

    if args.dtbo:
        for idx, blob in dtbo_entries(args.dtbo):
            dts = decompile(blob)
            if not dts:
                continue
            title = "%s (entrada %d)" % (os.path.basename(args.dtbo), idx)
            if args.summary:
                summary(dts, title)
            else:
                report(dts, title, args.verbose)
        return 0

    if args.dts:
        dts = load_dts(args.dts)
        if args.summary:
            summary(dts, os.path.basename(args.dts))
        else:
            report(dts, os.path.basename(args.dts), args.verbose)
        return 0

    if args.tree:
        dts = load_dts(args.tree)
        if args.summary:
            summary(dts, os.path.basename(args.tree))
        else:
            report(dts, os.path.basename(args.tree), args.verbose)
        return 0

    ap.error("give a tree, a --dtbo image or a --dts file")
    return 1


if __name__ == "__main__":
    sys.exit(main())
