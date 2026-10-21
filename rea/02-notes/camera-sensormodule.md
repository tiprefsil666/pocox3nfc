# The vendor camera configuration: `com.qti.sensormodule.*.bin`

**Source**: MIUI `V12.0.6.0.QJGMIXM` (Android 10, `surya`), the factory firmware.
**Location**: `android/extracted/rootfs/vendor/lib64/camera/com.qti.sensormodule.*.bin`
**Tools**: [`../04-tools/parse_sensormodule.py`](../04-tools/parse_sensormodule.py),
[`../04-tools/dump_regtable.py`](../04-tools/dump_regtable.py),
[`../04-tools/camera_inventory.py`](../04-tools/camera_inventory.py)

> This is a static analysis of the blob format. Nothing was run on hardware, and
> the values the vendor writes to the sensor are **not** in these blobs — see
> "What the blob does not contain" below.

## Why this matters

The mainline IMX682 driver in the overlay was written by reading the vendor's
blob. This note records the *format*, so the next person does not have to
rediscover it, and so the tools can be checked against it.

The blob is the vendor's description of a camera module: which sensor it
carries, which I2C slave it lives on, the register tables that make up its
power-up sequence, the lane assignment, the resolution tables, the EEPROM and
flash parts, and the PDAF configuration.

## The format

The file is a "QTI Chromatix Header" with a "Parameter Parser" section. The
layout below was recovered by inspecting the bytes.

### Header

```
0x000  char[24]   magic, "QTI Chromatix Header"
0x018  u32        header size
0x020  u16        version fields
0x028  char[40]   parser name, "Parameter Parser V1.3.2 (1811291228)"
0x098  u32        offset of the section table
0x0a0  u64[]      section table: (offset, size, id) triples
```

The section table of the blobs in this firmware is:

| Offset | Size | What |
|---|---:|---|
| `0x0000e8` | `0x17610` | the tag directory and the payloads |
| `0x0176f8` | `0x0b4f0` | the string and data pool |
| `0x022be8` | `0x18` | a trailing block |

### Tag directory

The directory is a flat list of entries **0x48 bytes** apart, starting at the
offset the section table gives. The walk ends at the first entry whose name is
empty or 0xff-filled.

```
+0x00  u64      tag id
+0x08  char[24] name
+0x20  u64      parent id (0 for a top-level tag)
+0x28  u64      tag type (1 = container, 0 = leaf)
+0x30  u64      child count (0xffffffff for a leaf)
+0x38  u64      payload offset, relative to the payload base
+0x40  u64      payload size
```

The **payload base** is the start of the second block of the section table
(`0x176f8` in these files). The offsets in the directory are relative to it.

The ids run from 1 upwards and are unique within a blob, but the same *name*
appears many times with different ids — the vendor reuses names for the
fields of every sensor, mode and sub-module in the file. Anything that
resolves an id to a name has to cope with that.

### The power-up sequence

The section named `regSetting` is a list of **16-byte records**, each a pair of
tag ids:

```
u64      the value
u64      the property
```

A blob may carry more than one `regSetting` section. The right one is the
one whose records actually name the `registerData` sections.

The records repeat in a fixed **five-record pattern**, and they have to be
read by position, because the same property name appears many times with
different ids and a record's *property* field names the property that the
*next* record introduces:

```
position 0  the register table of the following step
position 1  the driver data
position 2  the register table of this step
position 3  the field name
position 4  the delay
```

So for the `sunny_imx682` blob:

```
rec[0]  value=0    property=slaveAddr
rec[1]  value=274  property=sensorDriverData
rec[2]  value=25   property=registerData     <- the register table of this step
rec[3]  value=1    property=(id 0)
rec[4]  value=1    property=delayUs
```

The `registerData` section's payload starts with a **u32 count** — the number
of registers in that table.

## The inventory

Every blob in the factory firmware, decoded:

| Blob | Sensor | Module | Steps | Registers |
|---|---|---|---:|---:|
| `aac_gc02m1b_depth` | aac_gc02m1b | aac | 200 | 3 927 |
| `aac_hi1337_ultra` | aac_hi1337 | aac | 87 | 313 623 |
| `aac_hi259_macro` | aac_hi259 | aac | 73 | 2 782 |
| `ofilm_hi259_macro` | ofilm_hi259 | ofilm | 73 | 2 908 |
| `ofilm_imx682_ver2_wide` | ofilm_imx682 | ofilm | 74 | 1 527 |
| `ofilm_imx682_wide` | ofilm_imx682 | ofilm | 74 | 1 527 |
| `ofilm_ov02b1b_depth` | ofilm_ov02b1b | ofilm | 104 | 1 050 |
| `ofilm_s5k3t2_front` | ofilm_s5k3t2 | ofilm | 66 | 292 942 |
| `sunny_hi1337_ultra` | sunny_hi1337 | sunny | 87 | 313 623 |
| `sunny_imx682_ver2_wide` | sunny_imx682 | sunny | 74 | 1 527 |
| `sunny_imx682_wide` | sunny_imx682 | sunny | 74 | 1 527 |
| `sunny_s5k3t2_front` | sunny_s5k3t2 | sunny | 66 | 292 942 |

**1 052 power-up steps and about 1.2 million register writes** across the
twelve blobs. The `aac` and `sunny` variants of a module are byte-identical
in their step structure, which is what the vendor does: the module vendor
only changes the EEPROM part.

This confirms the sensor list the notes in
`surya-pmos/docs/camera.es.md` already worked from: **IMX682** (rear),
**S5K3T2** (front), **HI1337** (ultra), **HI259** (macro), **GC02M1B** and
**OV02B1B** (depth).

Reproduce with:

```sh
rea/04-tools/camera_inventory.py \
    android/extracted/rootfs/vendor/lib64/camera
```

## What the blob does not contain

**The register values are not in the blob.** A scan of every blob in the
factory firmware finds no run of `(address, value)` pairs with plausible
sensor addresses and non-zero values. The blob carries the *addresses*, the
ordering, the slaves and the delays; the *values* either come from the
vendor's sensor driver or are computed at run time.

The *addresses* of each table are in the payload pool, interleaved with the
other sections rather than stored inside the `registerData` section — that
section holds only the count. For the IMX682 blob the addresses are visible
in the pool (`0x034c`, `0x034e`, `0x0340`, `0x0342`, `0x0202`, `0x0204`, and
the clock registers `0x4050`, `0x3ff0`, `0x0492`), but **the framing between
one table and the next is not yet established**, so the tool reports the
count rather than guessing at the entries.

This matters when reading the notes: the "reg table" in
`surya-pmos/docs/camera.es.md` is the table of *addresses* and the sequence
they are written in, not a table of address/value pairs.

The other thing the blob does not carry is the lane assignment and the clock
settings in a directly readable form. The notes record that these were
extracted by other means, by comparing the vendor's CSIPHY configuration with
the factory kernel's.

## The tools the camera notes refer to

The notes in `surya-pmos/docs/camera.es.md` list tools that were never
committed. They are rebuilt here, from the descriptions in those notes:

| Tool | What it does |
|---|---|
| [`04-tools/parse_sensormodule.py`](../04-tools/parse_sensormodule.py) | the container format: header, tag directory, payloads |
| [`04-tools/dump_regtable.py`](../04-tools/dump_regtable.py) | the power-up sequence of one blob |
| [`04-tools/dump_reg_table.py`](../04-tools/dump_reg_table.py) | the register tables, as C |
| [`04-tools/camera_inventory.py`](../04-tools/camera_inventory.py) | every blob at a glance |
| [`04-tools/mmr.c`](../04-tools/mmr.c) | MMIO read/write through `/dev/mem`, for a phone with no `devmem` applet |
| [`04-tools/csiphy-lane-decode.sh`](../04-tools/csiphy-lane-decode.sh) | the per-lane CSIPHY status, with the IRQ bits masked |
| [`04-tools/csiphy_latch.sh`](../04-tools/csiphy_latch.sh) | the same status with and without the sensor emitting |
| [`04-tools/diagnostico_camara.sh`](../04-tools/diagnostico_camara.sh) | a read-only snapshot of the whole camera stack |

`mmr.c` carries the warning from the notes: reading MMIO with the clock
stopped gives zeros, or hangs, so read *while* the sensor is streaming.

## How this was verified

- The parser is checked against all twelve blobs: each one yields a
  consistent sensor name, module name, step count and register count.
- The `sensorName` payload of `sunny_imx682_wide` decodes to `sunny_imx682`,
  matching the file name.
- The `regSetting` records were cross-checked for the five-record periodicity
  across the whole stream (370 records in the IMX682 blobs, 78 of them
  naming a `registerData` section).
- The SHA-256 of each blob is recorded in
  `android/extracted/blob-inventory.csv`, which the extraction produced.

## Open questions

- The framing of the register tables in the payload pool. The addresses are
  there; the boundaries between tables are not yet established. The
  authority is the vendor's own parser, which lives in
  `vendor/lib64/hw/camera.qcom.so` (CamX) in
  `camximagesensormoduledatamanager.cpp`. That binary is 6.4 MB and the REA
  analysis of it did not finish within the tool's time budget, so a
  narrower pass over it — searching for the register-table reader rather than
  analysing the whole library — is the next step.
- Where the `delayUs` values are stored: the `delayUs` sections in the pool
  are all zero, so the delays live somewhere else, or are computed.
- The relationship between the `regSetting` step count and the resolution
  tables is not established: the blob has 74 steps for the IMX682 and the
  notes refer to five modes in the factory firmware.
- The `slaveAddr` sections have a zero-length payload, so the I2C slave of
  each step is carried elsewhere. The `regSetting` records give the ids of
  the `slaveAddr` sections, but the values in them are not in their own
  payloads.

## Reproducing this analysis

```sh
# the whole inventory
rea/04-tools/camera_inventory.py \
    android/extracted/rootfs/vendor/lib64/camera

# one blob, in full
rea/04-tools/parse_sensormodule.py \
    android/extracted/rootfs/vendor/lib64/camera/com.qti.sensormodule.j20c_sunny_imx682_wide.bin

# the power-up sequence of one blob
rea/04-tools/dump_regtable.py \
    android/extracted/rootfs/vendor/lib64/camera/com.qti.sensormodule.j20c_sunny_imx682_wide.bin --list
```
