#!/usr/bin/env python3
"""Resolve the PLT stub names of an AArch64 ELF without a disassembler.

Hopper names the thunks `sub_XXXX`; the .rela.plt section says what each
GOT slot actually points at. This maps thunk address -> symbol name so the
REA decompilation can be read with real names.

Usage: resolve_plt.py <elf> [start] [end]
"""
import re
import struct
import subprocess
import sys


def relocations(path):
    out = subprocess.run(
        ["readelf", "-r", "-W", path], capture_output=True, text=True
    ).stdout
    got = {}
    for line in out.splitlines():
        m = re.match(
            r"^([0-9a-f]{16})\s+\S+\s+R_AARCH64_JUMP_SLOT\s+\S+\s+(\S+)", line
        )
        if m:
            got[int(m.group(1), 16)] = m.group(2)
    return got


def adrp_target(pc, insn):
    """Return the page address an ADRP points at."""
    immlo = (insn >> 29) & 0x3
    immhi = (insn >> 5) & 0x7FFFF
    imm = (immhi << 2) | immlo
    if imm & (1 << 20):
        imm -= 1 << 21
    return (pc & ~0xFFF) + (imm << 12)


def resolve(path, start=0x4D00, end=0x4F40):
    data = open(path, "rb").read()
    got = relocations(path)
    out = {}
    for addr in range(start, end, 0x10):
        if addr + 12 > len(data):
            break
        i0, i1, _ = struct.unpack_from("<III", data, addr)
        if (i0 & 0x9F000000) != 0x90000000:      # ADRP
            continue
        if (i1 & 0xFFC00000) != 0xF9400000:      # LDR (64-bit, unsigned imm)
            continue
        page = adrp_target(addr, i0)
        offset = ((i1 >> 10) & 0xFFF) * 8
        slot = page + offset
        out[addr] = got.get(slot, f"<unresolved@got {slot:#x}>")
    return out


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    path = sys.argv[1]
    start = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0x4D00
    end = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0x4F40
    for addr, name in sorted(resolve(path, start, end).items()):
        print(f"  sub_{addr:x}  ->  {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
