#!/usr/bin/env python3
"""Extract the NXP PN557 firmware download sequence.

The NXP NFC controller on this board is an NXP PN557, and its firmware is
shipped as a shared library, vendor/lib/libpn557_fw.so, that exports one
thing:

    gphDnldNfc_DlSequence   the download sequence
    gphDnldNfc_DlSeqSz      its size
    gphDnldNfc_DlSeq        a pointer, zero in the shipped build

The sequence is a list of chunks:

    u16      the command
    u16      the length of the data that follows
    u8[]     the data

The commands are the NXP "download" commands the HAL sends to the chip.
The last chunk is a terminator, and the data of the large chunks is the
firmware itself.

This tool lists the chunks and can write each one's data out.

Usage:
  extract_pn557_fw.py <lib>              the chunk list
  extract_pn557_fw.py <lib> --extract D  write the chunks into D
  extract_pn557_fw.py <lib> --json       machine-readable output
"""
import argparse
import json
import os
import struct
import sys

# The exported symbols and their sizes, as the ELF declares them.
SYMBOL_SEQ = "gphDnldNfc_DlSequence"
SYMBOL_SZ = "gphDnldNfc_DlSeqSz"
SYMBOL_PTR = "gphDnldNfc_DlSeq"


def read_elf_symbols(path):
    """Return {name: (value, size)} for the dynamic symbols of an ELF."""
    import subprocess
    import re

    out = subprocess.run(["readelf", "--dyn-syms", "-W", path],
                         capture_output=True, text=True).stdout
    syms = {}
    for line in out.splitlines():
        # "   3: 0000000000010430 34462 OBJECT  GLOBAL DEFAULT  8 name"
        m = re.match(r"\s*\d+:\s+([0-9a-f]+)\s+(\d+)\s+\S+\s+\S+\s+\S+\s+\S+\s+(\S+)$",
                     line)
        if m:
            syms[m.group(3)] = (int(m.group(1), 16), int(m.group(2)))
    return syms


def vaddr_to_offset(path, vaddr):
    """Map a virtual address to a file offset using the program headers."""
    import subprocess
    import re

    out = subprocess.run(["readelf", "-l", "-W", path],
                         capture_output=True, text=True).stdout
    for line in out.splitlines():
        m = re.match(r"\s*LOAD\s+(0x[0-9a-f]+)\s+(0x[0-9a-f]+)\s+(0x[0-9a-f]+)",
                     line)
        if m:
            off = int(m.group(1), 16)
            vstart = int(m.group(2), 16)
            filesz = int(m.group(3), 16)
            if vstart <= vaddr < vstart + filesz:
                return off + (vaddr - vstart)
    return None


def read_sequence(path):
    """Read the download sequence out of the library."""
    syms = read_elf_symbols(path)
    if SYMBOL_SEQ not in syms:
        raise SystemExit("%s does not export %s" % (path, SYMBOL_SEQ))

    vaddr, size = syms[SYMBOL_SEQ]
    if SYMBOL_SZ in syms:
        sz_vaddr, sz_size = syms[SYMBOL_SZ]
        off = vaddr_to_offset(path, sz_vaddr)
        if off is not None and sz_size >= 2:
            data = open(path, "rb").read()
            declared = struct.unpack_from("<H", data, off)[0]
            if declared and declared < size:
                size = declared

    off = vaddr_to_offset(path, vaddr)
    if off is None:
        raise SystemExit("cannot map the sequence to a file offset")
    data = open(path, "rb").read()
    return data[off:off + size]


def split_chunks(seq):
    """Split the sequence into (command, data) chunks."""
    out = []
    off = 0
    while off + 4 <= len(seq):
        cmd, length = struct.unpack_from("<HH", seq, off)
        off += 4
        if off + length > len(seq):
            out.append((cmd, seq[off:]))
            break
        out.append((cmd, seq[off:off + length]))
        off += length
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("lib")
    ap.add_argument("--extract", metavar="DIR",
                    help="write the chunks into this directory")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    seq = read_sequence(args.lib)
    chunks = split_chunks(seq)

    if args.extract:
        os.makedirs(args.extract, exist_ok=True)
        total = 0
        for i, (cmd, data) in enumerate(chunks):
            name = "chunk_%03d_cmd_%04x.bin" % (i, cmd)
            with open(os.path.join(args.extract, name), "wb") as f:
                f.write(data)
            total += len(data)
        print("wrote %d chunk(s), %d bytes, into %s"
              % (len(chunks), total, args.extract))
        return 0

    if args.json:
        print(json.dumps({
            "file": args.lib,
            "size": len(seq),
            "chunks": [{"index": i, "command": "0x%04x" % c, "length": len(d)}
                       for i, (c, d) in enumerate(chunks)],
        }, indent=1))
        return 0

    print("%s: %d bytes, %d chunks" % (args.lib, len(seq), len(chunks)))
    for i, (cmd, data) in enumerate(chunks):
        print("  [%3d] cmd=0x%04x  %6d bytes" % (i, cmd, len(data)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
