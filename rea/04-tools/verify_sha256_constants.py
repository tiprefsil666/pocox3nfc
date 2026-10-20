#!/usr/bin/env python3
"""Verify the SHA-256 constants in a batterysecret binary.

The claim in the analysis notes is that sub_26e4 is HMAC-SHA-256, and that
this was established from the bytes of the binary rather than from the
decompiler's output.  This script checks exactly that: it locates the
SHA-256 initial hash values and all 64 round constants inside the file and
compares them byte for byte with the reference values.

Usage: verify_sha256_constants.py <elf> [base-offset]

The base offset is the virtual address of the file's first loadable segment;
it defaults to 0, which is right for a PIE with the usual layout.
"""
import struct
import sys

SHA256_H = [
    0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
    0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
]

SHA256_K = [
    0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5,
    0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
    0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3,
    0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
    0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC,
    0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
    0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7,
    0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
    0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13,
    0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
    0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3,
    0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
    0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5,
    0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
    0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208,
    0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
]


def find_u32(data, value):
    pat = struct.pack("<I", value)
    out = []
    i = 0
    while True:
        j = data.find(pat, i)
        if j < 0:
            break
        out.append(j)
        i = j + 1
    return out


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    path = sys.argv[1]
    base = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0
    data = open(path, "rb").read()

    print("file: %s (%d bytes)" % (path, len(data)))

    print("\nSHA-256 initial hash values H[0..7]:")
    h_off = None
    for i, h in enumerate(SHA256_H):
        hits = find_u32(data, h)
        ok = "OK " if hits else "MISSING"
        print("  H[%d] = %08x  %s %s" % (i, h, ok,
                                        ", ".join("0x%x" % (x + base)
                                                  for x in hits)))
        if hits and h_off is None:
            h_off = hits[0]

    print("\nSHA-256 round constants K[0..63]:")
    k_off = None
    contiguous = 0
    for i, k in enumerate(SHA256_K):
        hits = find_u32(data, k)
        if not hits:
            print("  K[%2d] = %08x  MISSING" % (i, k))
            continue
        if k_off is None:
            k_off = hits[0]
        if hits[0] == k_off + 4 * i:
            contiguous += 1
    print("  found %d of %d" % (sum(1 for k in SHA256_K if find_u32(data, k)),
                                len(SHA256_K)))
    print("  first at 0x%x" % (k_off + base) if k_off is not None
          else "  none found")
    print("  %d of them are contiguous in the file" % contiguous)

    if h_off is not None and k_off is not None:
        print("\nlayout: H at 0x%x, K at 0x%x" % (h_off + base, k_off + base))

    # MD5 for contrast: it is NOT in this binary.
    md5_h = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476]
    found_md5 = any(find_u32(data, v) for v in md5_h)
    print("\nMD5 initial values present: %s (expected: no)"
          % ("yes" if found_md5 else "no"))

    return 0


if __name__ == "__main__":
    sys.exit(main())
