# Clean-room reimplementation of the Xiaomi USB-PD authentication handshake

This directory holds a C reimplementation of the protocol observed in Xiaomi's
`vendor/bin/batterysecret`, reconstructed from static analysis with REA/Hopper.

The analysis is documented in
[`../02-notes/batterysecret-hvdcp.md`](../02-notes/batterysecret-hvdcp.md).
The evidence bundle is in
[`../01-evidence/batterysecret-session.json`](../01-evidence/batterysecret-session.json).

## What is confirmed vs. what is inferred

| Element | Status | Basis |
|---|---|---|
| The MAC is **HMAC-SHA-256** | **confirmed** | SHA-256 initial values and all 64 round constants found byte-exact in the file at `0x16f0` / `0x1710`; the `sub_26e4` structure is textbook ipad/opad HMAC (key hashing above 64 bytes, `0x36`/`0x5c` blocks) |
| The key table is 10 × 32 bytes at `0x50a0` | **confirmed** | byte read via REA; regenerated from the binary by `extract_keytable.py` |
| The key is indexed by charger model (0–9) | **confirmed** | `sub_2e0c` picks the slot with `model`, and the per-model seed table at `0x5000` has exactly 10 entries |
| The inner message is 20 bytes | **confirmed** | `mov w3, #0x14` at `0x2cdc`, message pointer `sp+0x70` |
| The message is `byte_swap32(seed) ‖ index_word` | **confirmed** | four `rev` instructions at `0x2b30`–`0x2b4c`; the index word is written to `sp+0x80`, immediately after the seed |
| The index word is built from the charger's `adapter_id` text | **confirmed** | the 8 bytes at `sp+0x10..0x17` are the first 8 bytes of the `adapter_id` string read by `sub_30a8` |
| The index word's nibble decoding | **confirmed** | transcribed instruction by instruction, including two *different* decoders |
| Only 16 bytes of the digest are compared | **confirmed** | `sub_4eb0(..., 0x10)` — a `memcmp` of 16 bytes |
| The per-model seed at `0x5000` is sent to the charger | **confirmed** | `sub_30a8` writes it to `current_pr` with command `4` |
| The VDM wire format | **unknown** | only the sysfs-level behaviour is established |
| How the charger combines the seed and the index | **unknown** | the charger must compute the same digest, so both must reach it; the transport is not reconstructed |

## The algorithm, as implemented

```
seed_be   = byte_swap32(seed)                  /* the vendor's four `rev`s     */
index     = adapter_id[0..7] -> 4 bytes        /* two different hex decoders   */
message   = seed_be || index                    /* 20 bytes                     */
expected  = HMAC-SHA256(key = table[model], message)
accept  if  memcmp(expected[0..15], charger_digest[0..15]) == 0
```

The `adapter_id` → index word conversion deserves a note. The vendor uses
**two different hex decoders**, alternating between them, and one of them is
not a nibble decoder at all:

```
A(c) = (c - '0')        if toupper(c) is a digit
     = toupper(c) + 9    otherwise          <-- NOT a nibble
B(c) = (c - '0')        if toupper(c) is a digit
     = toupper(c) - 0x37 otherwise          <-- the real nibble
```

and the last byte reverses the nibble order compared with the first three:

```
byte 0 = A(c[0]) + (B(c[1]) << 4)
byte 1 = A(c[2]) + (B(c[3]) << 4)
byte 2 = A(c[4]) + (B(c[5]) << 4)
byte 3 = B(c[7]) + (A(c[6]) << 4)
```

Both quirks are the vendor's actual code and are reproduced verbatim, because a
reimplementation has to be byte-compatible with it. `decoder_a()` in
`src/xpd_auth.c` is marked accordingly. Do not "fix" it.

## Files

| File | Purpose |
|---|---|
| `include/xpd_auth.h` | Public API |
| `src/sha256.c` | SHA-256 and HMAC-SHA-256, from FIPS 180-4 / RFC 2104 |
| `src/xpd_auth.c` | The handshake: index word, seed swap, digest compare |
| `src/xpd_keytable.c` | **Generated** from the binary — the 10 HMAC keys |
| `src/xpd_auth_cli.c` | CLI: verify a charger digest, or print the expected one |
| `tests/test_xpd_auth.c` | Self-tests |
| `tests/vectors.h` | **Generated** test vectors |
| `Makefile` | Build |

## Build and test

```sh
make
make test
```

## Verification

Three independent layers, because a transcription error in a crypto routine
is easy to make and hard to see:

1. **Published test vectors.** SHA-256 against FIPS 180-4, HMAC-SHA-256
   against RFC 4231. These check the primitives without reference to Xiaomi.
2. **Generated xpd vectors.** `tests/vectors.h` is produced from the binary by
   `../04-tools/gen_test_vectors.py`, which also self-checks the RFC vectors
   against a reference implementation before writing them out.
3. **Differential test against an independent transcription.**
   `../04-tools/xpd_model.py` transcribes the same AArch64 in Python by a
   different route; `../04-tools/differential_test.py` runs both over hundreds
   of inputs and requires them to agree:

   ```sh
   make -C ../03-c-reimplementation
   ../04-tools/differential_test.py ../03-c-reimplementation/build/xpd_auth
   # 580 comparisons, 0 mismatches
   ```

## Regenerating the artefacts

```sh
# The key table, from the binary
../04-tools/extract_keytable.py ../00-inputs/charge-stack/batterysecret \
    --generate src/xpd_keytable.c
../04-tools/extract_keytable.py ../00-inputs/charge-stack/batterysecret \
    --check src/xpd_keytable.c

# The test vectors
../04-tools/gen_test_vectors.py ../00-inputs/charge-stack/batterysecret \
    tests/vectors.h
```

## Deliberate omissions

- **The transport is not reimplemented.** Every channel is a Qualcomm
  downstream sysfs attribute under `/sys/class/usbpd/usbpd0/`, and on
  mainline postmarketOS none of it exists. Writing a USB-PD policy engine and
  a VDM transport from scratch is a much larger job than the crypto, and it is
  not what this directory is for.
- **The charge pump is not reimplemented.** That is the BQ2597x driver, which
  already exists in the overlay as a kernel patch.
- **The table is not shipped as a public constant without review.** The 10 keys
  are Xiaomi protocol constants. They are here because the algorithm is
  meaningless without them, but check the licensing position of the rest of
  the repository before publishing this directory.
- **No attempt is made to attack the scheme.** The truncated comparison and the
  weak `rand()` seed are documented as observations about the vendor's
  implementation, not as a recipe.
