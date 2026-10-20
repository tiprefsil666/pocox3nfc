#!/usr/bin/env python3
"""A small AArch64 decoder for the instruction forms used in the batterysecret
analysis: add/sub immediate, logical immediate, conditional select, bitfield
insert/extract, and unsigned-offset load/store.

Only the forms the analysis depends on are decoded; anything else is printed
as the raw word so it can be checked by hand.

Usage: aarch64_decode.py <elf> <addr> [<addr> ...]
       aarch64_decode.py <elf> --range <start> <end>
"""
import struct
import sys

REG = ["x%d" % i for i in range(31)] + ["sp", "xzr"]
REG32 = ["w%d" % i for i in range(31)] + ["wsp", "wzr"]


def sx(value, bits):
    if value & (1 << (bits - 1)):
        value -= 1 << bits
    return value


def decode(word, pc=0):
    """Return a human-readable form of one AArch64 instruction word."""
    op = word & 0xFFFFFFFF

    # --- Add/subtract (immediate), 32-bit -------------------------------
    if (op & 0x7F000000) == 0x11000000 and (op >> 31) == 0:
        sf = (op >> 31) & 1
        rd = op & 0x1F
        rn = (op >> 5) & 0x1F
        imm = (op >> 10) & 0xFFF
        shift = (op >> 22) & 0x3
        if (op & 0x40000000) == 0:          # ADD
            if shift:
                imm <<= 12
            return "%s = %s + #%d" % (REG32[rd] if not sf else REG[rd],
                                      REG32[rn] if not sf else REG[rn], imm)
        if (op & 0x20000000) == 0:          # SUB (immediate)
            return "%s = %s - #%d" % (REG32[rd], REG32[rn], imm)
        if (op & 0x20000000) == 0x20000000:  # SUBS
            return "%s = %s - #%d (flags)" % (REG32[rd], REG32[rn], imm)
        return None

    # --- Logical (immediate) --------------------------------------------
    if (op & 0x7F800000) == 0x12000000:
        rd = op & 0x1F
        rn = (op >> 5) & 0x1F
        n = (op >> 22) & 1
        immr = (op >> 16) & 0x3F
        imms = (op >> 10) & 0x3F
        if (op & 0x3F800000) == 0x12000000 or (op & 0x3F800000) == 0x32000000:
            # Decode the bitmask immediate
            length = 0
            if n == 1:
                length = 6
            else:
                length = 6
            # element size from imms
            if imms == 0x3F:
                width = 64
            else:
                width = 6
            # Reconstruct: the standard algorithm
            if imms == 0x3F:
                if immr == 0:
                    val = 0xFFFFFFFFFFFFFFFF
                else:
                    val = (0xFFFFFFFFFFFFFFFF >> (immr - 1)) & 0xFFFFFFFFFFFFFFFF
                    val = ((val >> 1) | (val << 63)) & 0xFFFFFFFFFFFFFFFF
            else:
                hi = imms + 1
                lo = immr
                if hi >= 64:
                    val = 0xFFFFFFFFFFFFFFFF
                else:
                    val = ((1 << (hi - lo)) - 1) << lo
                    val &= 0xFFFFFFFFFFFFFFFF
            names = {0x0: "AND", 0x1: "ORR", 0x2: "EOR", 0x3: "ANDS"}
            opcode = (op >> 29) & 0x3
            return "%s %s, %s, #0x%x" % (names[opcode], REG32[rd], REG32[rn], val & 0xFFFFFFFF)

    # --- Conditional select ---------------------------------------------
    if (op & 0x1FE00000) == 0x1A800000:
        rd = op & 0x1F
        rn = (op >> 5) & 0x1F
        rm = (op >> 16) & 0x1F
        cond = (op >> 12) & 0xF
        op2 = (op >> 10) & 0x3
        conds = {0: "eq", 1: "ne", 2: "hs", 3: "lo", 4: "mi", 5: "pl",
                 6: "vs", 7: "vc", 8: "hi", 9: "ls", 10: "ge", 11: "lt",
                 12: "gt", 13: "le", 14: "al", 15: "nv"}
        if op2 == 0:
            return "csel %s, %s, %s, %s" % (REG32[rd], REG32[rn], REG32[rm], conds[cond])
        if op2 == 1:
            return "csinc %s, %s, %s, %s" % (REG32[rd], REG32[rn], REG32[rm], conds[cond])
        return "csel? %08x" % op

    # --- Bitfield extract / insert --------------------------------------
    if (op & 0x7F800000) == 0x13000000:
        sf = (op >> 31) & 1
        n = (op >> 22) & 1
        immr = (op >> 16) & 0x3F
        imms = (op >> 10) & 0x3F
        rd = op & 0x1F
        rn = (op >> 5) & 0x1F
        r = REG32[rd]
        if n == 0:      # BFM
            return "bfm %s, %s, #%d, #%d" % (r, REG32[rn], immr, imms)
        if (op & 0x00200000) == 0:   # BFXIL: opc=00 -> BFM, opc=01 -> BFXIL
            pass
        # decide BFM vs BFXIL vs UBFX by the pattern
        if imms == 0x1F and sf:
            return "ubfx %s, %s, #%d, #%d" % (r, REG32[rn], immr, imms + 1)
        return "bfxil %s, %s, #%d, #%d" % (r, REG32[rn], immr, imms + 1)

    # --- Unsigned-offset load/store -------------------------------------
    if (op & 0x3B000000) == 0x39000000:
        size = (op >> 30) & 0x3
        opc = (op >> 22) & 0x3
        imm = (op >> 10) & 0xFFF
        rn = (op >> 5) & 0x1F
        rt = op & 0x1F
        scale = {0: 4, 1: 8, 2: 16, 3: 4}[size]
        if opc == 0:
            return "str %s, [%s, #%d]" % (REG32[rt], REG[rn], imm * scale)
        if opc == 1:
            return "ldr %s, [%s, #%d]" % (REG32[rt], REG[rn], imm * scale)
        if opc == 2:
            return "ldrsw %s, [%s, #%d]" % (REG32[rt], REG[rn], imm * scale)
        if opc == 3:
            return "ldrb %s, [%s, #%d]" % (REG32[rt], REG[rn], imm)
        return "ldr? %08x" % op

    # --- LDR/STR (immediate, unsigned offset, 64-bit) --------------------
    if (op & 0xFFC00000) == 0xF9400000:
        imm = ((op >> 10) & 0xFFF) * 8
        rn = (op >> 5) & 0x1F
        rt = op & 0x1F
        return "ldr %s, [%s, #%d]" % (REG[rt], REG[rn], imm)
    if (op & 0xFFC00000) == 0xF9000000:
        imm = ((op >> 10) & 0xFFF) * 8
        rn = (op >> 5) & 0x1F
        rt = op & 0x1F
        return "str %s, [%s, #%d]" % (REG[rt], REG[rn], imm)
    if (op & 0xFFC00000) == 0x79400000:
        imm = ((op >> 10) & 0xFFF) * 2
        rn = (op >> 5) & 0x1F
        rt = op & 0x1F
        return "ldrh %s, [%s, #%d]" % (REG32[rt], REG[rn], imm)
    if (op & 0xFFC00000) == 0xB9000000:
        imm = ((op >> 10) & 0xFFF) * 4
        rn = (op >> 5) & 0x1F
        rt = op & 0x1F
        return "str %s, [%s, #%d]" % (REG32[rt], REG[rn], imm)

    # --- ADRP / ADD immediate -------------------------------------------
    if (op & 0x9F000000) == 0x90000000:
        immlo = (op >> 29) & 0x3
        immhi = (op >> 5) & 0x7FFFF
        imm = (immhi << 2) | immlo
        imm = sx(imm, 21) << 12
        rd = op & 0x1F
        return "adrp %s, #0x%x" % (REG[rd], (pc & ~0xFFF) + imm)

    if (op & 0x7F000000) == 0x11000000:
        imm = (op >> 10) & 0xFFF
        shift = (op >> 22) & 0x3
        if shift:
            imm <<= 12
        rd = op & 0x1F
        rn = (op >> 5) & 0x1F
        if (op & 0x40000000):
            return "sub %s, %s, #%d" % (REG[rd], REG[rn], imm)
        return "add %s, %s, #%d" % (REG[rd], REG[rn], imm)

    # --- BL / B ---------------------------------------------------------
    if (op & 0xFC000000) == 0x94000000:
        imm = sx(op & 0x3FFFFFF, 26) << 2
        return "bl #0x%x" % (pc + imm)
    if (op & 0xFC000000) == 0x14000000:
        imm = sx(op & 0x3FFFFFF, 26) << 2
        return "b #0x%x" % (pc + imm)

    # --- STP / LDP ------------------------------------------------------
    if (op & 0x7FC00000) == 0x29000000:
        L = (op >> 22) & 1
        imm7 = (op >> 15) & 0x7F
        imm7 = sx(imm7, 7)
        rt = op & 0x1F
        rt2 = (op >> 10) & 0x1F
        rn = (op >> 5) & 0x1F
        opc = (op >> 30) & 0x3
        sz = 4 if opc == 0 else 8
        return "%s %s, %s, [%s, #%d]" % ("ldp" if L else "stp",
                                         REG32[rt], REG32[rt2], REG[rn], imm7 * sz)

    # --- Move wide ------------------------------------------------------
    if (op & 0x7F800000) == 0x12800000:
        hw = (op >> 21) & 0x3
        imm = (op >> 5) & 0xFFFF
        rd = op & 0x1F
        if imm == 0:
            return "mov %s, #0" % REG32[rd]
        if (imm & 0xFF00) == 0:
            return "mov %s, #%d" % (REG32[rd], imm)
        return "movz %s, #0x%x, lsl #%d" % (REG32[rd], imm, hw * 16)

    if (op & 0x7F800000) == 0x12000000 or (op & 0x7F800000) == 0x12800000:
        pass

    # --- BFI / BFXIL alias of BFM (handled above) ------------------------

    # --- MADD / MSUB ----------------------------------------------------
    if (op & 0xFFE08000) == 0x1B000000:
        rd = op & 0x1F
        rn = (op >> 5) & 0x1F
        ra = (op >> 10) & 0x1F
        rm = (op >> 16) & 0x1F
        if (op & 0x00200000):
            return "msub %s, %s, %s, %s" % (REG32[rd], REG32[rn], REG32[rm], REG32[ra])
        return "madd %s, %s, %s, %s" % (REG32[rd], REG32[rn], REG32[rm], REG32[ra])

    return "%08x" % op


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    data = open(sys.argv[1], "rb").read()
    if sys.argv[2] == "--range":
        start = int(sys.argv[3], 0)
        end = int(sys.argv[4], 0)
        addrs = range(start, end, 4)
    else:
        addrs = [int(a, 0) for a in sys.argv[2:]]

    for a in addrs:
        word = struct.unpack_from("<I", data, a)[0]
        print("0x%x: %08x  %s" % (a, word, decode(word, a)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
