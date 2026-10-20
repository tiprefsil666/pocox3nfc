#!/usr/bin/env python3
"""Extract (or regenerate) the Xiaomi charger authentication key table.

The key table lives at virtual address 0x50a0 in vendor/bin/batterysecret and
holds 10 entries of 32 bytes.

There are two modes:

  --generate <out.c>   write the C source with the real key values
  --check <in.c>       verify a C source against the binary
  --redact <out.c>     write the C source with the key values redacted, for a
                       public copy of the repository

The redacted form keeps the structure and the byte counts but replaces every
key with zeros, so the public tree shows the shape of the algorithm without
redistributing Xiaomi's protocol constants.  The real values stay in the
private working copy, from which the redacted file is produced.

Usage:
  extract_keytable.py <elf> --generate <out.c>
  extract_keytable.py <elf> --check <in.c>
  extract_keytable.py <elf> --redact <out.c>
"""
import re
import sys

TABLE_VADDR = 0x50A0
ENTRY_SIZE = 32
ENTRY_COUNT = 10

HEADER = """/* SPDX-License-Identifier: GPL-2.0-or-later
 *
 * The Xiaomi charger authentication key table.
 *
 * The real values are {MODE_NOTE}
 *
 * GENERATED FILE — do not edit by hand. Regenerate with:
 *   04-tools/extract_keytable.py \\
 *       <batterysecret> --{MODE} \\
 *       03-c-reimplementation/src/xpd_keytable.c
 *
 * LICENCE NOTE: these are Xiaomi protocol constants recovered from a Xiaomi
 * binary. The redacted form is what belongs in a public repository; the real
 * values stay in the private working copy.
 */

#include "xpd_auth.h"

#include <string.h>

static const uint8_t g_key_table[XPD_INDEX_COUNT][XPD_INDEX_KEY_LEN] = {
"""

FOOTER = """};

const uint8_t *xpd_key_table(unsigned slot)
{
	if (slot >= XPD_INDEX_COUNT)
		return NULL;
	return g_key_table[slot];
}
"""


def read_table(path):
    data = open(path, "rb").read()
    out = []
    for i in range(ENTRY_COUNT):
        off = TABLE_VADDR + i * ENTRY_SIZE
        chunk = data[off:off + ENTRY_SIZE]
        if len(chunk) != ENTRY_SIZE:
            raise SystemExit("short read at slot %d" % i)
        out.append(chunk)
    return out


def render(entries, mode):
    mode_note = {
        "generate": "in the private working copy of this tree, not here.",
        "redact": "REDACTED in this public copy. The real values are not\n"
                  " * redistributed; regenerate them from your own copy of the\n"
                  " * firmware with --generate.",
    }[mode]

    body = ""
    for i, e in enumerate(entries):
        body += "\t{ /* [%2d] */\n" % i
        for r in range(0, ENTRY_SIZE, 8):
            row = ", ".join("0x%02x" % b for b in e[r:r + 8])
            body += "\t  %s%s\n" % (row, "," if r + 8 < ENTRY_SIZE else "")
        body += "\t}%s\n" % ("," if i + 1 < len(entries) else "")

    return (HEADER.replace("{MODE_NOTE}", mode_note)
                    .replace("{MODE}", mode)
            + body + FOOTER)


def parse_c(path):
    text = open(path).read()
    parts = re.split(r"\{ /\* \[", text)[1:]
    out = []
    for p in parts:
        body = p.split("}")[0]
        bs = re.findall(r"0x([0-9a-fA-F]{2})", body)
        out.append(bytes(int(b, 16) for b in bs))
    return out


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    elf, mode, target = sys.argv[1], sys.argv[2], sys.argv[3]
    entries = read_table(elf)

    if mode in ("--generate", "--redact"):
        if mode == "--redact":
            entries = [bytes(ENTRY_SIZE) for _ in entries]
        open(target, "w").write(render(entries, mode.lstrip("-")))
        print("wrote %s (%d entries, mode %s)"
              % (target, len(entries), mode.lstrip("-")))
        return 0

    if mode == "--check":
        got = parse_c(target)
        bad = 0
        for i, e in enumerate(entries):
            if i >= len(got) or got[i] != e:
                bad += 1
                print("slot %d MISMATCH" % i)
                print("  file: %s" % (got[i].hex() if i < len(got) else "<missing>"))
                print("  bin : %s" % e.hex())
        if bad:
            print("\n%d slot(s) differ" % bad)
            return 1
        print("all %d slots match the binary" % len(entries))
        return 0

    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
