#!/usr/bin/env python3
"""Disassemble an AArch64 ELF, for when Hopper's output is ambiguous.

Hopper's decompiler names stack slots in ways that can hide the data flow,
and the PLT thunks it reports as sub_XXXX need resolving.  This tool gives a
plain disassembly to read alongside it.

It uses capstone, which must be available:

    python3 -m venv /tmp/capvenv
    /tmp/capvenv/bin/pip install capstone

Usage:
    disasm.py <elf> --range <start> <end>
    disasm.py <elf> <addr> [<addr> ...]
    disasm.py <elf> --prologue <addr>    a function's first instructions
"""
import argparse
import os
import struct
import sys

try:
    from capstone import Cs, CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN
except ImportError:
    sys.exit("capstone is required: pip install capstone")


def load(path):
    """Return (data, md) for an AArch64 ELF, honouring its program headers."""
    data = open(path, "rb").read()

    if data[:4] != b"\x7fELF":
        sys.exit("not an ELF file")
    if data[4] != 2 or data[18] != 0xB7:
        sys.exit("not a little-endian AArch64 ELF")

    # Map virtual addresses to file offsets using the PT_LOAD headers.
    phoff = struct.unpack_from("<Q", data, 0x20)[0]
    phentsize = struct.unpack_from("<H", data, 0x36)[0]
    phnum = struct.unpack_from("<H", data, 0x38)[0]

    segments = []
    for i in range(phnum):
        off = phoff + i * phentsize
        p_type = struct.unpack_from("<I", data, off)[0]
        if p_type != 1:            # PT_LOAD
            continue
        p_offset = struct.unpack_from("<Q", data, off + 8)[0]
        p_vaddr = struct.unpack_from("<Q", data, off + 16)[0]
        p_filesz = struct.unpack_from("<Q", data, off + 32)[0]
        segments.append((p_vaddr, p_vaddr + p_filesz, p_offset))

    return data, segments


def to_offset(data, segments, vaddr):
    for lo, hi, off in segments:
        if lo <= vaddr < hi:
            return off + (vaddr - lo)
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("elf")
    ap.add_argument("addrs", nargs="*")
    ap.add_argument("--range", nargs=2, metavar=("START", "END"))
    ap.add_argument("--prologue", metavar="ADDR",
                    help="print 40 instructions from ADDR")
    args = ap.parse_args()

    data, segments = load(args.elf)
    md = Cs(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN)

    def disasm(vaddr, count):
        off = to_offset(data, segments, vaddr)
        if off is None:
            print("0x%x: not mapped" % vaddr)
            return
        chunk = data[off:off + count * 4]
        for i in md.disasm(chunk, vaddr):
            print("  0x%x: %-10s %s" % (i.address, i.mnemonic, i.op_str))

    if args.range:
        start = int(args.range[0], 0)
        end = int(args.range[1], 0)
        disasm(start, (end - start) // 4)
        return 0

    if args.prologue:
        disasm(int(args.prologue, 0), 40)
        return 0

    for a in args.addrs:
        disasm(int(a, 0), 1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
