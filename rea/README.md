# Reverse-engineering workspace

Reverse-engineering of the Xiaomi proprietary binaries from the POCO X3 NFC
(`surya`) factory firmware, with [REA](https://github.com/morluto/rea) and
Hopper as the analysis engine, and a clean-room C reimplementation of what was
recovered.

## Layout

| Directory | Contents |
|---|---|
| `00-inputs/` | The configuration and init files that describe the components being analysed. **The vendor binaries themselves are not here** — they are proprietary and stay out of this tree |
| `01-evidence/` | The REA evidence bundle for each analysed target: every tool result, with its evidence ID, subject digest, provider and limitations |
| `02-notes/` | The written analysis: what was found, how it was confirmed, and what is still unknown |
| `03-c-reimplementation/` | A C reimplementation of the recovered behaviour, with its own tests |
| `04-tools/` | The tools written for this work: triage, PLT resolution, AArch64 decoding, table extraction, vector generation, differential testing |

## The current analysis

### `batterysecret` — the USB-PD / HVDCP authentication handshake

Xiaomi's `vendor/bin/batterysecret` performs the mutual authentication with the
charger that unlocks the high-power charging mode. It is the half of fast
charge that is *not* the charge pump.

The recovered scheme:

```
seed     = 16 bytes from rand()
index    = 4 bytes built from the charger's adapter_id text
message  = byte_swap32(seed) || index
expected = HMAC-SHA256( key = table[charger_model], message )
accept  if  memcmp(expected[0..15], charger_digest[0..15]) == 0
```

Full write-up, with the evidence IDs and the confirmed/inferred split:
[`02-notes/batterysecret-hvdcp.md`](02-notes/batterysecret-hvdcp.md).

Reimplementation and its verification:
[`03-c-reimplementation/`](03-c-reimplementation/).

## Using REA on this tree

```sh
# Is REA ready? Which provider is available?
rea doctor

# Triage a binary without a disassembler
rea/04-tools/triage.sh <elf>

# Resolve Hopper's sub_XXXX thunks to real symbol names
rea/04-tools/resolve_plt.py <elf>

# Then open it in REA and work with the focused tools
mcp__rea rea_open_binary {path: "<elf>"}
mcp__rea rea_binary_overview {}
mcp__rea rea_procedure_assembly {procedure: "0x2ae4"}
mcp__rea rea_procedure_pseudo_code {procedure: "0x2ae4"}
mcp__rea rea_search_strings {pattern: "..."}
mcp__rea rea_xrefs {address: "0x..."}
mcp__rea rea_export_evidence_bundle {path: "<out>/session.json"}
```

Two providers are configured on this host: **Hopper** (available) and
**Ghidra** (not configured — set `GHIDRA_INSTALL_DIR` to enable it). An IDA
registration is also supported but not configured.

### A note on reading Hopper's output

Hopper names imported-function thunks `sub_XXXX` and its decompiler can
mangle stack layouts. Two things that cost real time here:

- **Resolve the PLT first.** `sub_4ea0` looked like a hex-nibble helper and
  was assumed to be one; it is `toupper`. `04-tools/resolve_plt.py` maps every
  thunk to its real symbol from `.rela.plt`.
- **Check the raw instruction encodings.** Where the decompiler's variable
  names made the data flow ambiguous, the instruction stream settled it. The
  `csel` pattern in `sub_2ae4` in particular only makes sense once decoded by
  hand.

## Reproducing the verification

```sh
# 1. The primitives, against the published RFC and FIPS vectors
make -C 03-c-reimplementation test

# 2. The xpd-level vectors, regenerated from the binary
04-tools/gen_test_vectors.py <batterysecret> 03-c-reimplementation/tests/vectors.h

# 3. The key table, checked against the binary
04-tools/extract_keytable.py <batterysecret> --check 03-c-reimplementation/src/xpd_keytable.c

# 4. The crypto claim, checked against the file's bytes
04-tools/verify_sha256_constants.py <batterysecret>

# 5. Differential test: the C implementation against an independent
#    Python transcription of the same instructions
04-tools/differential_test.py 03-c-reimplementation/build/xpd_auth
```

Step 5 reports `580 comparisons, 0 mismatches`.

## What is published and what is not

**Published:** the analysis, the evidence bundle, the tools, and the
reimplementation. The key table, the per-model seed table and the interface
facts they encode are extracted from a publicly distributed MIUI build and are
published as interface facts — the same way this repository already publishes
the modem's QMI LOC message tables in
[`../surya-pmos/tools/qmi-loc-idl/`](../surya-pmos/tools/qmi-loc-idl/).

**Not published:** the vendor binaries themselves, the extracted vendor
filesystem, and the factory firmware images. They stay in the private working
copy. See `../README.md` and `../surya-pmos/NOTICE.md`.

**Not implemented, on purpose:** the USB-PD transport and the charge-pump
driver. The transport is a set of Qualcomm downstream sysfs attributes with no
mainline equivalent, and writing a PD policy engine from scratch is a
different project. The charge pump is already covered by the overlay's kernel
patch.
