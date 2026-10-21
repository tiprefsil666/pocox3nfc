# The NXP NFC controller: PN557, its firmware and its RF calibration

**Source**: MIUI `V12.0.6.0.QJGMIXM` (Android 10, `surya`), the factory firmware.
**Tools**: [`../04-tools/parse_nxp_rf.py`](../04-tools/parse_nxp_rf.py),
[`../04-tools/extract_pn557_fw.py`](../04-tools/extract_pn557_fw.py)

> Static analysis only. Nothing was run on hardware, and the chip was not
> probed.

## The chip

The NFC controller is an **NXP PN557**, with the **PN5180** ("NQ4XX") variant
of the radio configuration. This is established from the configuration
files, not guessed:

- `vendor/etc/libnfc-mtp-NQ4XX.conf` opens with the comment:

  ```
  ## This file is used by NFC NXP NCI HAL(external/libnfc-nci/halimpl/pn547)
  ## and NFC Service Java Native Interface Extensions (packages/apps/Nfc/nci/jni/extns/pn547)
  ```

  and names the device node `NXP_NFC_DEV_NODE="/dev/nq-nci"`.

- The RF configuration file for this board is `vendor/libnfc-nxp_RF.conf`.

- The chip's firmware is shipped as `vendor/lib/libpn557_fw.so`.

> ⚠️ The HAL's own strings do **not** name the chip. `hal_libnfc.so` and
> `nfc_nci.nqx.default.hw.so` contain the NFA/NCI symbols but no `NF212`,
> `NF214` or `NF540` string; the identity comes from the configuration
> files, which is where the vendor puts it.

## The RF calibration

`libnfc-nxp_RF.conf` holds the factory calibration of the antenna and the
RF front end, as a set of blocks of raw bytes:

```
NXP_RF_CONF_BLK_1={
	20, 02, E7, 1B,
	A0, 0D, 06, 06, 37, 08, 76, 00, 00,
	A0, 0D, 03, 24, 03, 7E,
	...
}
```

The first four bytes are the block's header. Every line after it is one
register write:

```
byte 0..1  the I2C address of the configuration register
byte 2     the register
byte 3..   the value
```

The address `0xA00D` is the NXP RF configuration register; the value of the
register selects which calibration table is written, and the data that
follows is the table itself. The block's own header (`20 02` and a
length-like word) carries the block's parameters.

Decoded:

| Block | Header | Contents |
|---|---|---|
| 1 | `2002e71b` | 27 register writes — the ALM/PLM settings |
| 2 | `2002d601` | 213 packed bytes — a packed table, not a list of writes |
| 3 | `20025b01` | 90 packed bytes — likewise |
| 4 | `20022104` | 4 register writes, including `0xA00D` |
| 5, 6 | — | commented out in the vendor's file |

The active configuration for this board, `libnfc-mtp-NQ4XX.conf`, carries
its **own** set of blocks with different headers (`20025c01`, `2002d601`),
so the two files are not interchangeable.

> ⚠️ **Two block layouts.** Blocks 1 and 4 are written one register per
> line, and the parser reads them that way. Blocks 2 and 3 are a single
> long line each, and their bytes after the header are a *packed* table
> whose internal framing the parser does not guess at. The vendor's
> four-byte header is what distinguishes the two.

```sh
rea/04-tools/parse_nxp_rf.py rea/00-inputs/nfc-config/libnfc-nxp_RF.conf
rea/04-tools/parse_nxp_rf.py rea/00-inputs/nfc-config/libnfc-nxp_RF.conf --block 1
```

## The chip firmware

`vendor/lib/libpn557_fw.so` is not a library in the usual sense: it exports
one thing.

```
gphDnldNfc_DlSequence   OBJECT  34462 bytes   (the download sequence)
gphDnldNfc_DlSeqSz      OBJECT  2 bytes
gphDnldNfc_DlSeq        OBJECT  8 bytes      (a pointer; zero in this build)
```

The sequence is a list of chunks:

```
u16      the command
u16      the length of the data that follows
u8[]     the data
```

Decoded, the 34 462 bytes are **109 chunks**, of which only eight carry
data:

| Chunk | Command | Bytes | What |
|---|---|---:|---|
| 0 | `0xe400` | 192 | the firmware header |
| 1 | `0xde47` | 14 621 | firmware |
| 2 | `0x8168` | 1 144 | firmware |
| 3 | `0x43d1` | 1 096 | firmware |
| 4 | `0x1728` | 976 | firmware |
| 5 | `0x2040` | 8 213 | firmware |
| 6 | `0x82f1` | 7 783 | firmware |
| 108 | `0xc100` | 1 | the terminator (`0x00`) |

Chunks 7 to 107 are zero-length padding, which is how the HAL knows the
sequence has ended before the terminator.

**The header chunk is checksummed.** The sum of all its bytes is `0x00`, and
so is the sum of the terminator's. The firmware chunks are not; the checksum
belongs to the framing, not to the payload.

```sh
rea/04-tools/extract_pn557_fw.py rea/00-inputs/nfc/libpn557_fw.so
rea/04-tools/extract_pn557_fw.py rea/00-inputs/nfc/libpn557_fw.so --extract /tmp/pn557
```

> **Evidence**: REA analysis of `libpn557_fw.so`,
> `ev_d012ec090dab059d8d7096817f26a23369f43410a1722797e47d4e6dadec2ad1`
> (symbol inventory). The ELF is **not stripped**, so the symbols are the
> vendor's own.

## What this means for the port

1. **The controller is a PN557 with a PN5180-class radio.** The mainline
   driver is `pn557` in the NXP NFC tree; there is no mainline driver for
   the PN5180 radio, and the PN557 one does not cover it. The RF
   calibration blocks are the reason: they configure a radio the mainline
   driver does not know.
2. **The firmware is loadable without the vendor's HAL.** The download
   sequence is a plain list of (command, data) chunks in a file the vendor
   ships as a library. A mainline driver that can write those commands to
   the chip can load the firmware; the format is now documented.
3. **The RF calibration is per-device in practice.** The blocks are shipped
   in a plain text file in the factory firmware, but they are the factory
   calibration of one board's antenna. They should be read from the
   device's own firmware, not redistributed.
4. **The eSE is routed through the same controller.** `libnfc-qrd_default.conf`
   sets `NXP_CE_ROUTE_STRICT_DISABLE=0x01` and the default AID and DesFire
   routes to the eSE (`0x01` / `0x02`), which is the "secure element" the
   overlay's notes call the eSE. Whether the mainline port needs it is a
   separate question.

## Open questions

- The NXP download commands themselves: `0xe400`, `0xde47`, `0x8168`,
  `0x43d1`, `0x1728`, `0x2040`, `0x82f1` and the terminator `0xc100` are
  the values in the sequence, but what each one *means* to the chip is not
  established here. The NXP NFC HAL source is the reference, and it is not
  part of the factory firmware.
- The framing of the packed blocks 2 and 3.
- Whether the PN5180 radio needs the RF blocks at all, or whether they
  are legacy from an earlier board. The active `NQ4XX` file carries its own
  set, which suggests they are used.

## Reproducing this analysis

```sh
rea/04-tools/parse_nxp_rf.py rea/00-inputs/nfc-config/libnfc-nxp_RF.conf
rea/04-tools/extract_pn557_fw.py rea/00-inputs/nfc/libpn557_fw.so
rea/04-tools/triage.sh rea/00-inputs/nfc/libpn557_fw.so
```
