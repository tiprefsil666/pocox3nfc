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

### The vendor camera configuration — `com.qti.sensormodule.*.bin`

The blobs that describe every camera module in the factory firmware: the
sensor, the module, the I2C slaves, the register tables of the power-up
sequence, the lane assignment and the resolution tables.

The format was recovered here and is now documented, together with the tools
that decode it:

- [`02-notes/camera-sensormodule.md`](02-notes/camera-sensormodule.md) — the format, the inventory, and what the blob does *not* contain.
- [`04-tools/parse_sensormodule.py`](04-tools/parse_sensormodule.py) — the container format.
- [`04-tools/dump_regtable.py`](04-tools/dump_regtable.py) — the power-up sequence.
- [`04-tools/camera_inventory.py`](04-tools/camera_inventory.py) — every blob at a glance.

The inventory covers all twelve blobs: **1 052 power-up steps and about 1.2
million register writes**, across the IMX682 (rear), S5K3T2 (front), HI1337
(ultra), HI259 (macro), GC02M1B and OV02B1B (depth) sensors.

The camera notes in `surya-pmos/docs/camera.es.md` refer to tools that were
never committed. They are now here, rebuilt from the descriptions in those
notes: [`04-tools/mmr.c`](04-tools/mmr.c) (MMIO through `/dev/mem`, for a
phone with no `devmem` applet),
[`04-tools/csiphy-lane-decode.sh`](04-tools/csiphy-lane-decode.sh) and
[`04-tools/diagnostico_camara.sh`](04-tools/diagnostico_camara.sh).

### NFC — the NXP PN557 and its firmware

The NFC controller is an NXP **PN557** with a PN5180-class radio, and the
factory firmware ships three things worth having: the chip's firmware as a
download sequence in a plain shared library, the RF calibration as text
blocks, and the routing configuration.

- [`02-notes/nfc-pn557.md`](02-notes/nfc-pn557.md) — the chip, the firmware format, the RF calibration blocks.
- [`04-tools/extract_pn557_fw.py`](04-tools/extract_pn557_fw.py) — the firmware download sequence: 109 chunks, 7 with data.
- [`04-tools/parse_nxp_rf.py`](04-tools/parse_nxp_rf.py) — the RF calibration blocks.

### Audio — the mixer paths

The audio configuration is a tree of routes over the WCD9375 codec and the
TAS2562 amplifiers, with four tunings that differ in more than values.
Decoded: **607 routes** in the WCD9375 tuning, and the microphone routes
wired out in full.

- [`02-notes/audio-mixer-paths.md`](02-notes/audio-mixer-paths.md) — the routes, the speakers, the microphones, the echo reference.
- [`04-tools/parse_mixer_paths.py`](04-tools/parse_mixer_paths.py) — the routes, flattened.
- [`04-tools/audio_inventory.py`](04-tools/audio_inventory.py) — the routes, the amplifiers and the codec each one touches.

### GNSS — the modem's receiver

The receiver is the modem, not the application processor, and the factory
configuration says so: `NMEA_PROVIDER=0`. The modem supports BeiDou,
GLONASS, QZSS, Galileo and SBAS, each with its own blacklist mask. The
QMI LOC message table is already decoded and published in
[`../surya-pmos/tools/qmi-loc-idl/`](../surya-pmos/tools/qmi-loc-idl/).

- [`02-notes/gnss-qmi-loc.md`](02-notes/gnss-qmi-loc.md) — what the firmware says, and what is still missing (A-GPS assistance).

### Infrared and FM radio

Both are asked about often, and neither is what people expect. Three
different things get called "infrared" on this phone, and the FM radio is
not a separate chip at all: it is the WCN3990, reached through the
Bluetooth HCI transport.

- [`02-notes/ir-and-fm.md`](02-notes/ir-and-fm.md) — the camera's IR LED and its IR-cut filter, the remote control emitter that the firmware never enables, and the FM stack that rides on the Bluetooth chip.
- [`04-tools/ir_fm_config.py`](04-tools/ir_fm_config.py) — the device tree and the vendor side, side by side.

### The other work on this hardware

The upstream `sm7150-mainline` project ports the same SoC to
postmarketOS, and the community has already solved several of the things
this workspace was working on. Reading their work first avoids doing it
twice — and it also says clearly where this port is **ahead**.

- [`02-notes/upstream-parallel-work.md`](02-notes/upstream-parallel-work.md) — the survey: the official installation, the tested feature status, the audio configuration, the NixOS port, and the upstreaming of this port's own libcamera patches.
- The device tree of the stock firmware is published there, which is the cross-check for the analysis in these notes.

## Using REA on this tree

```sh
# Is REA ready? Which provider is available?
rea doctor

# Triage a binary without a disassembler
rea/04-tools/triage.sh <elf>

# Resolve Hopper's sub_XXXX thunks to real symbol names
rea/04-tools/resolve_plt.py <elf>

# Disassemble, when Hopper's decompiler is ambiguous
rea/04-tools/disasm.py <elf> --range <start> <end>
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
  hand. `04-tools/disasm.py` gives a plain disassembly via capstone.

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

# 6. The camera inventory, decoded from the factory blobs
04-tools/camera_inventory.py \
    ../android/extracted/rootfs/vendor/lib64/camera

# 7. The NFC firmware download sequence
04-tools/extract_pn557_fw.py 00-inputs/nfc/libpn557_fw.so

# 8. The RF calibration blocks
04-tools/parse_nxp_rf.py 00-inputs/nfc-config/libnfc-nxp_RF.conf

# 9. The audio routes
04-tools/audio_inventory.py 00-inputs/audio-config
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
