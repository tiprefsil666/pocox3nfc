#!/usr/bin/env python3
"""Parse an NXP NFC RF configuration file.

The NXP NFC controller on this board is configured from a plain text file
with blocks of raw bytes.  Each block is a calibration table for one RF
parameter.

The vendor's own file, libnfc-nxp_RF.conf, writes the blocks with one
register write per line:

    NXP_RF_CONF_BLK_1={
        20, 02, E7, 1B,
        A0, 0D, 06, 06, 37, 08, 76, 00, 00,
        A0, 0D, 03, 24, 03, 7E,
        ...
    }

The first line of a block is its header.  Every line after it is one
register write:

    byte 0..1  the I2C address of the configuration register
    byte 2     the register
    byte 3..   the value

The address 0xA00D is the NXP RF configuration register; the value of the
register selects which calibration table is written, and the data that
follows is the table itself.

The line layout is the vendor's, and it is what makes the format readable:
the lines are not a fixed width.  The parser therefore splits on the
formatting rather than on a byte count.

TWO BLOCK LAYOUTS
-----------------
Not every block is written one register per line.  Blocks 1 and 4 are;
blocks 2 and 3 are a single long line each, and in those the bytes after
the four-byte header are a packed table rather than a list of writes.  The
parser reports the header and the byte count for those, and does not guess
at a register breakdown it cannot justify.  The vendor's own header
(the `20 02` marker, then a length-like word) is what distinguishes them.

Usage:
  parse_nxp_rf.py <file>              the blocks, decoded
  parse_nxp_rf.py <file> --block N    one block, with its register writes
  parse_nxp_rf.py <file> --json       machine-readable output
"""
import argparse
import json
import re
import sys

BLOCK_RE = re.compile(
    r"^\s*(#\s*)?NXP_RF_CONF_BLK_(\d+)\s*=\s*\{(.*?)\}", re.S | re.M)
BYTE_RE = re.compile(r"\b([0-9a-fA-F]{2})\b")


class Write:
    """One register write: an address, a register and a value."""

    __slots__ = ("addr", "reg", "value")

    def __init__(self, addr, reg, value):
        self.addr = addr
        self.reg = reg
        self.value = value

    def to_dict(self):
        return {"addr": "0x%04x" % self.addr,
                "reg": "0x%02x" % self.reg,
                "value": self.value.hex()}


def parse_blocks(text):
    """Return a list of (number, header, writes) for every block."""
    out = []
    for m in BLOCK_RE.finditer(text):
        number = int(m.group(2))
        body = m.group(3)
        lines = [ln for ln in body.splitlines() if BYTE_RE.search(ln)]
        if not lines:
            out.append((number, b"", [], b""))
            continue

        def bytes_of(line):
            return bytes(int(h, 16) for h in BYTE_RE.findall(line))

        # The header is the first four bytes of the block, whatever the
        # line layout is.
        allbytes = b"".join(bytes_of(ln) for ln in lines)
        header = allbytes[:4]
        writes = []
        packed = b""
        # Skip the four header bytes; what is left is either a list of
        # register writes (one per line) or a packed table (one long
        # line).
        rest = allbytes[4:]
        for line in lines[1:]:
            b = bytes_of(line)
            if len(b) < 3:
                continue
            if len(b) > 32:
                # A long line: the block is a packed table.
                packed += b
                continue
            writes.append(Write((b[0] << 8) | b[1], b[2], b[3:]))
        if not writes:
            # The first line carried everything; take the table from it.
            packed = rest
        out.append((number, header, writes, packed))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file")
    ap.add_argument("--block", type=int, help="decode only this block")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    text = open(args.file, errors="replace").read()
    blocks = parse_blocks(text)

    if not blocks:
        print("no NXP_RF_CONF_BLK blocks in %s" % args.file)
        return 1

    if args.json:
        out = []
        for number, header, writes in blocks:
            out.append({
                "block": number,
                "header": header.hex(),
                "writes": [w.to_dict() for w in writes],
            })
        print(json.dumps({"file": args.file, "blocks": out}, indent=1))
        return 0

    for number, header, writes, packed in blocks:
        if args.block is not None and number != args.block:
            continue
        kind = "%d register writes" % len(writes) if writes \
            else "%d packed bytes" % len(packed)
        print("NXP_RF_CONF_BLK_%d: header %s, %s"
              % (number, header.hex(), kind))
        if args.block is not None:
            for w in writes:
                print("  0x%04x  reg 0x%02x  = %s" % (w.addr, w.reg, w.value.hex()))
            if packed:
                print("  packed: %s" % packed.hex())
            print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
