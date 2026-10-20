#!/usr/bin/env python3
"""Executable model of the Xiaomi charger authentication in batterysecret.

This is a direct transcription of the AArch64 at sub_2ae4 (0x2ae4-0x2dec) and
its call site in sub_2e0c (0x3628-0x3648). It exists so the C
reimplementation can be diffed against something that was derived from the
instruction stream rather than from a second reading of the same decompiler
output.

The quirks in the vendor's hex decoding are reproduced exactly; they are
deliberate, and the comment marks each one.

The key and seed tables below are interface facts extracted from a publicly
distributed MIUI build, published the same way this repository already
publishes the modem's QMI LOC message tables in
surya-pmos/tools/qmi-loc-idl/.

Usage: xpd_model.py <adapter_id_text> <seed_hex32>
"""
import hashlib
import hmac
import struct
import sys

# --- tables extracted from the binary -------------------------------------

# 0x50a0: 10 x 32-byte HMAC keys, one per charger model
KEY_TABLE = [
    "5c4d4179da1501ed11747492e26083d96b8fbc73c82e7bdf5d3255c2a036a1dc",
    "4554ea907fc3250d2078bd6277d6cf0cb823e62258d087378af29c466b101026",
    "83d30625cb0f7ce6d49649ff4cfcf9cebe62469b57e31ba62d01de2810ff621a",
    "a1447305166b4a786df5ddd707a8360a7328ced7038487607fa21128a15d1864",
    "e4fb00afd15186af1a44502005d3d1b0b1e9d1a636a51c26349422e7dbadc273",
    "46b8cae9a46a3254ee551282cf07b7bb6b2ef12bf615463c239bb63b984e42a9",
    "eaf45b6ff3ccce769e82bd0b007b69c406a66b98f427a2bbe455d1ffcb1ecdcc",
    "e787db568b7d704d29cc50a2bb1e971f6f1fd7fe9604deb4d4a1a7a72c63ff42",
    "b5f704a75d0db54a0b5e731779949b321105adc9d5c0858c50efc9bf92892cf4",
    "df47cc3249833bdefeb4a04a257489fc7500d827b2b66b2689bded7ffe49465e",
]

# 0x5000: 10 x 16-byte per-model seed sent to the charger (command 4)
SEED_TABLE = [
    "d6e9770506c7f5f4df7a40008c7467b8",
    "09604eb9ad37e17bd6b2a4f2a3515984",
    "f6295ce3bde8678c9ffeab616098aba0",
    "ae0c8ee9b05ba233799badcb9fa22b41",
    "56b7470c9d6f22ca003e40326fa77eb5",
    "6019b457cd77fd5fedffdc3d0ed06106",
    "09e47c32760fb2facfc5843df0716465",
    "a601934c1403bfd955ebd77f509ba17f",
    "3e02b44e19dc24f438e62f026ade4aa7",
    "343d6b41b900beb4c8bf0e8fa7df8c13",
]


def toupper(c):
    return c - 32 if 0x61 <= c <= 0x7A else c


def nibble_first_style(c):
    """sub w8,w0,#0x30 ; and w9,w8,#0xff ; add w10,w0,#9 ; csel hi

    Digits give c-0x30; letters give c+9 (NOT a nibble!).  Reproduced
    verbatim: this is the vendor's actual code.
    """
    c = toupper(c)
    w8 = (c - 0x30) & 0xFFFFFFFF
    w9 = w8 & 0xFF
    w10 = (c + 9) & 0xFFFFFFFF
    return w10 if w9 > 9 else w8


def nibble_second_style(c):
    """sub w8,w0,#0x30 ; sub w9,w0,#0x37 ; csel hi

    Digits give c-0x30; letters give c-0x37, which is the correct nibble.
    """
    c = toupper(c)
    w8 = (c - 0x30) & 0xFFFFFFFF
    w9 = (c - 0x37) & 0xFFFFFFFF
    w10 = w8 & 0xFF
    return w9 if w10 > 9 else w8


def build_index_word(adapter_id_bytes):
    """The 4 bytes written at sp+0x80, from the first 8 bytes of adapter_id.

    Transcribed from 0x2ba4-0x2ce8.  The vendor alternates two different
    nibble decoders and reverses the nibble order in the last byte.
    """
    c = list(adapter_id_bytes[:8])
    if len(c) < 8:
        c += [0] * (8 - len(c))

    # byte 0: nib(c0') + (nib(c1) << 4)
    w25 = nibble_first_style(c[0]) + (nibble_second_style(c[1]) << 4)
    # byte 1
    w26 = nibble_first_style(c[2]) + (nibble_second_style(c[3]) << 4)
    # byte 2
    w27 = nibble_first_style(c[4]) + (nibble_second_style(c[5]) << 4)
    # byte 3: REVERSED nibble order compared with bytes 0..2
    w8 = nibble_second_style(c[7]) + (nibble_first_style(c[6]) << 4)

    word = ((w25 & 0xFF) << 0) | ((w26 & 0xFF) << 8) | \
           ((w27 & 0xFF) << 16) | ((w8 & 0xFF) << 24)
    return word


def swap32(seed16):
    """The vendor's four `rev` instructions at 0x2b20-0x2b4c."""
    out = bytearray(16)
    for i in range(0, 16, 4):
        out[i:i + 4] = seed16[i:i + 4][::-1]
    return bytes(out)


def struct_pack_le32(v):
    return bytes([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF])


def expected_digest(model_index, seed16, adapter_id_bytes):
    """The full sub_2ae4 computation."""
    key = bytes.fromhex(KEY_TABLE[model_index])
    word = build_index_word(adapter_id_bytes)
    message = swap32(seed16) + struct_pack_le32(word)
    return hmac.new(key, message, hashlib.sha256).digest()[:16]


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    adapter = sys.argv[1].encode("latin-1")[:8]
    seed = bytes.fromhex(sys.argv[2])[:16]

    print("adapter_id[0:8] : %s" % adapter.hex())
    print("seed             : %s" % seed.hex())
    print("seed (swapped)   : %s" % swap32(seed).hex())
    print("index word       : %s" % struct_pack_le32(
        build_index_word(adapter)).hex())
    print()
    for i in range(len(KEY_TABLE)):
        d = expected_digest(i, seed, adapter)
        print("  model %d -> %s   (per-model seed %s)"
              % (i, d.hex(), SEED_TABLE[i]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
