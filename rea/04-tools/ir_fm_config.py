#!/usr/bin/env python3
"""Extract the infrared and FM radio configuration from the factory firmware.

The two subsystems look alike from the outside and are nothing alike
inside:

  - The infrared *remote control* emitter is an SPI LED on the QUPv3
    SPI0, driven by the Android HAL through /dev/spidev0.1.
  - The FM radio is not a separate chip at all on this board: it is the
    WCN3990 ("cherokee"), and the Android HAL reaches it through the
    Bluetooth HCI transport.

The camera's own infrared LED and its IR-cut filter are a third, separate
thing, and are reported too, because they are easy to confuse with the
remote control emitter.

This tool reports all of it, from the device tree overlays and the
vendor's binaries, so that the two can be told apart.

Usage:
  ir_fm_config.py <dtbo.img>                the device tree side
  ir_fm_config.py --vendor <vendor-dir>     the vendor binary side
  ir_fm_config.py <dtbo.img> --vendor <dir>  both
"""
import argparse
import os
import re
import struct
import subprocess
import sys
import tempfile


# ---------------------------------------------------------------- device tree


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


def entry_to_dts(blob):
    """Decompile one DTBO entry with dtc."""
    with tempfile.NamedTemporaryFile(suffix=".dtb", delete=False) as f:
        f.write(blob)
        p = f.name
    try:
        r = subprocess.run(["dtc", "-I", "dtb", "-O", "dts", p],
                           capture_output=True, text=True)
        return r.stdout
    finally:
        os.unlink(p)


def find_nodes(dts, pattern):
    """Find every node whose body matches, returning (name, body)."""
    out = []
    lines = dts.splitlines()
    for i, l in enumerate(lines):
        m = re.match(r"^(\t+)(\S+):\s*(\S+)\s*\{", l)
        if not m:
            continue
        indent, label, name = m.group(1), m.group(2), m.group(3)
        if not re.search(pattern, name):
            continue
        # collect the body
        body = []
        depth = 0
        for j in range(i, len(lines)):
            body.append(lines[j])
            depth += lines[j].count("{") - lines[j].count("}")
            if j > i and depth <= 0:
                break
        out.append((label, name, "\n".join(body)))
    return out


def report_dtbo(path):
    print("== the device tree side (%s) ==" % os.path.basename(path))
    print()
    found = False

    for idx, blob in dtbo_entries(path):
        dts = entry_to_dts(blob)
        if not dts:
            continue

        # The remote control emitter: an SPI LED.
        for label, name, body in find_nodes(dts, r"ir|ir-led|ir-leds"):
            if "spi" not in body and "ir-led-src" not in body:
                continue
            if "camera-ir-led" in name:
                continue
            print("entry %d: the infrared emitter" % idx)
            for l in body.splitlines():
                if re.search(r"compatible|reg =|spi-max|led-active|duty|"
                            r"gpio|status|label", l):
                    print("    %s" % l.strip())
            found = True

        # The camera's infrared LED and its IR-cut filter.
        for label, name, body in find_nodes(dts, r"camera-ir-led"):
            print("entry %d: the camera's infrared LED (not the remote control)" % idx)
            for l in body.splitlines():
                if re.search(r"compatible|reg =|pwms|gpio|label|"
                            r"gpio-ir|status|enable-active", l):
                    print("    %s" % l.strip())
            found = True

        # The IR-cut filter of the front camera.
        for label, name, body in find_nodes(dts, r"cam_sensor_ir_led_(on|off)"):
            print("entry %d: the IR-cut filter, %s" % (idx, name))
            for l in body.splitlines():
                if "pins" in l or "bias" in l:
                    print("    %s" % l.strip())
            found = True

    if not found:
        print("  nothing found")
    print()


# ------------------------------------------------------------------- vendor


def strings_of(path):
    try:
        r = subprocess.run(["strings", "-a", path], capture_output=True, text=True)
        return r.stdout.splitlines()
    except OSError:
        return []


def report_vendor(vdir):
    print("== the vendor binary side (%s) ==" % vdir)
    print()

    # The infrared HAL: which device does it open?
    ir = os.path.join(vdir, "lib64/hw/consumerir.default.so")
    if os.path.exists(ir):
        print("the infrared HAL, lib64/hw/consumerir.default.so:")
        for s in strings_of(ir):
            if re.search(r"/dev/|spidev|lirc|carrier_freq|pattern_len|"
                         r"transmit|open", s):
                print("    %s" % s)
        print()

    # The infrared service: is it a service or a factory test?
    d = os.path.join(vdir, "bin/consumerird")
    if os.path.exists(d):
        print("bin/consumerird:")
        for s in strings_of(d):
            if re.search(r"spidev|lirc|test implement|auto test", s):
                print("    %s" % s)
        print()

    # The FM HAL: what does it talk to?
    fm = os.path.join(vdir, "lib64/hw/vendor.qti.hardware.fm@1.0-impl.so")
    if os.path.exists(fm):
        print("the FM HAL, lib64/hw/vendor.qti.hardware.fm@1.0-impl.so:")
        for s in strings_of(fm):
            if re.search(r"Hci|hci|bluetooth|Bluetooth|FmHci|"
                         r"sendDataToController|fmOff|SoC", s):
                print("    %s" % s)
        print()

    # The FM firmware downloader: which chip, which transport.
    p = os.path.join(vdir, "bin/fm_qsoc_patches")
    if os.path.exists(p):
        print("the FM firmware downloader, bin/fm_qsoc_patches:")
        for s in strings_of(p):
            if re.search(r"chip version|Bahama|Cherokee|WCN2243|"
                         r"i2c-|Patches|Spur|Patch \[|notch|"
                         r"patch download|DAC", s):
                print("    %s" % s)
        print()

    # The build properties: which chip, and whether FM is on.
    bp = os.path.join(vdir, "build.prop")
    if os.path.exists(bp):
        print("the build properties:")
        for line in open(bp, errors="replace"):
            if re.search(r"bluetooth.soc|hw\.fm|feature\.fm|fm\.", line):
                print("    %s" % line.strip())
        print()

    # The init script: how the FM firmware gets loaded.
    init = os.path.join(vdir, "bin/init.qti.fm.sh")
    if os.path.exists(init):
        print("the FM init script, bin/init.qti.fm.sh:")
        for line in open(init, errors="replace"):
            if re.search(r"mode|fm_qsoc_patches|fmsmd_set|setprop|"
                         r"radio_iris|firmware download", line):
                print("    %s" % line.rstrip())
        print()


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dtbo", nargs="?", help="the dtbo.img of the factory firmware")
    ap.add_argument("--vendor", metavar="DIR",
                    help="the vendor directory of the factory firmware")
    args = ap.parse_args()

    if not args.dtbo and not args.vendor:
        ap.error("give a dtbo.img, a --vendor directory, or both")

    if args.dtbo:
        report_dtbo(args.dtbo)
    if args.vendor:
        report_vendor(args.vendor)
    return 0


if __name__ == "__main__":
    sys.exit(main())
