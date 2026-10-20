#!/usr/bin/env python3
"""Generate tests/vectors.h for the xpd_auth self-test.

Two kinds of vector are emitted:

1. The published HMAC-SHA-256 test vectors from RFC 4231, given as hex so
   that no C string-escape mistake can creep in.
2. The xpd-level vectors, computed by this script from the binary's key
   table and the transcribed algorithm.  They are the same values the
   independent model in 04-tools/xpd_model.py produces.

Usage: gen_test_vectors.py <elf> <out.h> [--redact]

With --redact, the xpd-level vectors are replaced by placeholders, so the
public tree does not carry HMAC values that were computed with Xiaomi's keys.
The RFC 4231 vectors are public and are always included.
"""
import hashlib
import hmac
import struct
import sys

TABLE_VADDR = 0x50A0
ENTRY_SIZE = 32
ENTRY_COUNT = 10

SEED_TABLE_VADDR = 0x5000

# RFC 4231, as (key_hex, data_hex, expected_hex).
RFC4231 = [
    ("0b" * 20,
     "4869205468657265",
     "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"),
    ("4a656665",
     "7768617420646f2079612077616e7420666f72206e6f7468696e673f",
     "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"),
    ("aa" * 20,
     "dd" * 50,
     "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe"),
    ("0102030405060708090a0b0c0d0e0f10111213141516171819",
     "cd" * 50,
     "82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b"),
    ("0c" * 20,
     "546573742057697468205472756e636174696f6e",
     "a3b6167473100ee06e0c796c2955552bfa6f7c0a6a8aef8b93f860aab0cd20c5"),
    ("aa" * 131,
     "54657374205573696e67204c6172676572205468616e20426c6f636b"
     "2d53697a65204b6579202d2048617368204b6579204669727374",
     "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"),
]

# Self-check: every published vector must match a reference implementation.
# If this raises, the table above was mistyped.
for _k, _d, _e in RFC4231:
    _got = hmac.new(bytes.fromhex(_k), bytes.fromhex(_d),
                     hashlib.sha256).hexdigest()
    if _got != _e:
        raise SystemExit("RFC 4231 vector mismatch: %s != %s" % (_got, _e))


def toupper(c):
    return c - 32 if 0x61 <= c <= 0x7A else c


def dec_a(c):
    c = toupper(c)
    w8 = (c - 0x30) & 0xFFFFFFFF
    w9 = w8 & 0xFF
    w10 = (c + 9) & 0xFFFFFFFF
    return w10 if w9 > 9 else w8


def dec_b(c):
    c = toupper(c)
    w8 = (c - 0x30) & 0xFFFFFFFF
    w9 = (c - 0x37) & 0xFFFFFFFF
    w10 = w8 & 0xFF
    return w9 if w10 > 9 else w8


def build_index_word(adapter):
    c = list(adapter[:8]) + [0] * 8
    c = c[:8]
    w25 = dec_a(c[0]) + (dec_b(c[1]) << 4)
    w26 = dec_a(c[2]) + (dec_b(c[3]) << 4)
    w27 = dec_a(c[4]) + (dec_b(c[5]) << 4)
    w8 = dec_b(c[7]) + (dec_a(c[6]) << 4)
    return struct.pack("<BBBB", w25 & 0xFF, w26 & 0xFF, w27 & 0xFF, w8 & 0xFF)


def swap32(seed):
    return b"".join(seed[i:i + 4][::-1] for i in range(0, 16, 4))


def expected_digest(key, seed, word):
    msg = swap32(seed) + word
    return hmac.new(key, msg, hashlib.sha256).digest()


def c_hex_bytes(hexstr, name):
    """Render a hex string as a C array initialiser."""
    b = bytes.fromhex(hexstr)
    rows = []
    for i in range(0, len(b), 12):
        rows.append("\t" + " ".join("0x%02x," % c for c in b[i:i + 12]))
    return "static const uint8_t %s[%d] = {\n%s\n};\n" % (name, len(b), "\n".join(rows))


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    elf, out = sys.argv[1], sys.argv[2]
    redact = "--redact" in sys.argv[3:]
    data = open(elf, "rb").read()

    keys = [data[TABLE_VADDR + i * ENTRY_SIZE:
                  TABLE_VADDR + (i + 1) * ENTRY_SIZE] for i in range(ENTRY_COUNT)]

    adapter = b"0123456789abcdef"
    seed = bytes(range(16))
    word = build_index_word(adapter)

    out_lines = []
    out_lines.append("/* SPDX-License-Identifier: GPL-2.0-or-later")
    out_lines.append(" *")
    out_lines.append(" * GENERATED FILE — do not edit by hand.")
    if redact:
        out_lines.append(" *")
        out_lines.append(" * The xpd-level vectors are REDACTED in this public copy. They are")
        out_lines.append(" * HMAC values computed with Xiaomi's keys, so they are not")
        out_lines.append(" * redistributed here.")
    out_lines.append(" * Regenerate with:")
    out_lines.append(" *   04-tools/gen_test_vectors.py \\")
    out_lines.append(" *       00-inputs/charge-stack/batterysecret \\")
    out_lines.append(" *       03-c-reimplementation/tests/vectors.h")
    out_lines.append(" */")
    out_lines.append("")
    out_lines.append("#ifndef XPD_TEST_VECTORS_H")
    out_lines.append("#define XPD_TEST_VECTORS_H")
    out_lines.append("")
    out_lines.append("#include <stdint.h>")
    out_lines.append("")

    # RFC 4231 vectors
    out_lines.append("struct xpd_hmac_vector {")
    out_lines.append("\tconst uint8_t *key;")
    out_lines.append("\tsize_t keylen;")
    out_lines.append("\tconst uint8_t *data;")
    out_lines.append("\tsize_t datalen;")
    out_lines.append("\tconst char *expected;")
    out_lines.append("};")
    out_lines.append("")

    for i, (k, d, e) in enumerate(RFC4231):
        out_lines.append(c_hex_bytes(k, "g_rfc_key_%d" % i))
        out_lines.append(c_hex_bytes(d, "g_rfc_data_%d" % i))

    out_lines.append("static const struct xpd_hmac_vector g_rfc_vectors[] = {")
    for i, (k, d, e) in enumerate(RFC4231):
        out_lines.append("\t{ g_rfc_key_%d, %d, g_rfc_data_%d, %d, \"%s\" },"
                         % (i, len(k) // 2, i, len(d) // 2, e))
    out_lines.append("};")
    out_lines.append("")

    # xpd-level vectors
    out_lines.append(c_hex_bytes(adapter.hex(), "g_xpd_adapter"))
    out_lines.append(c_hex_bytes(seed.hex(), "g_xpd_seed"))
    out_lines.append(c_hex_bytes(word.hex(), "g_xpd_index_word"))
    out_lines.append("")
    out_lines.append("struct xpd_vector {")
    out_lines.append("\tunsigned slot;")
    out_lines.append("\tconst char *expected;")
    out_lines.append("};")
    out_lines.append("")
    out_lines.append("static const struct xpd_vector g_xpd_vectors[] = {")
    for i, key in enumerate(keys):
        if redact:
            out_lines.append("\t{ %d, \"<redacted>\" }," % i)
        else:
            dig = expected_digest(key, seed, word)
            out_lines.append("\t{ %d, \"%s\" }," % (i, dig.hex()[:32]))
    out_lines.append("};")
    out_lines.append("")
    out_lines.append("#endif /* XPD_TEST_VECTORS_H */")

    open(out, "w").write("\n".join(out_lines) + "\n")
    print("wrote %s" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
