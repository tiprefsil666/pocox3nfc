# pocox3nfc

Workspace and porting notes for postmarketOS on the Xiaomi POCO X3 NFC
(`surya`, Qualcomm SM7150).

## Contents

- [`surya-pmos/`](surya-pmos/): device overlay, kernel patches, packages and port documentation.
- [`build/`](build/): the build pipeline — the numbered steps that go from the sources to a flashable image, and the test battery.
- [`postmarketos/verificacao-blobs/`](postmarketos/verificacao-blobs/): inventory of Android-derived components and postmarketOS port status.
- [`postmarketos/INTEGRATION.md`](postmarketos/INTEGRATION.md): integration notes for the SM7150 prebuilt image.
- [`postmarketos/PREBUILT.md`](postmarketos/PREBUILT.md): notes about the local prebuilt image, which is not included here.
- [`rea/`](rea/): reverse-engineering workspace — the analysis of Xiaomi's proprietary binaries, the REA evidence bundle, the tools, and a clean-room C reimplementation.

Android firmware, extracted proprietary blobs, and prebuilt disk images are
excluded from this public repository. Use firmware obtained for your own
device and follow the relevant vendor and project licenses.

## Building and testing

The build is a set of numbered steps, each of which can be run on its own:

```sh
cd build
./run.sh --list
./run.sh
```

The full recipe — the host dependencies, the pmbootstrap configuration, the
flash and the seventeen tests — is in
[`build/README.md`](build/README.md), and the roadmap that leads to it is
in [`surya-pmos/docs/ROADMAP-pt.md`](surya-pmos/docs/ROADMAP-pt.md).

> ⚠️ The build has not yet been run end to end on a clean installation.
> Flash to a second partition, a second phone or a microSD card first, not
> to the phone that works today.

## Current reverse-engineering focus

The BQ25968/BQ25970 charge-pump driver checks the silicon ID before
initialization. The Android device tree reports the BQ2597x family at I²C
address `0x65`; hardware ID and runtime behavior still need confirmation on a
POCO X3 NFC running this port. Xiaomi's proprietary HVDCP fast-charge
negotiation is not implemented by the driver.

See [`surya-pmos/reverse-engineering/bq2597x/`](surya-pmos/reverse-engineering/bq2597x/)
for the register and firmware analysis.

## The USB-PD authentication handshake

The fast-charge negotiation is a second, separate problem from the charge
pump: the pump converts a high VBUS into current, while an authentication
handshake with the charger decides whether the high-power mode is unlocked at
all. That handshake lives in Xiaomi's `vendor/bin/batterysecret`, and it has
now been reverse-engineered.

The recovered scheme is HMAC-SHA-256 over a 20-byte message, keyed by a
per-charger-model table embedded in the binary, with a 16-byte `rand()`-based
session seed and only the first 16 bytes of the MAC compared.

- [`rea/02-notes/batterysecret-hvdcp.md`](rea/02-notes/batterysecret-hvdcp.md) — the analysis, with observations, inferences and unknowns kept apart.
- [`rea/03-c-reimplementation/`](rea/03-c-reimplementation/) — a C reimplementation of the recovered behaviour, with tests.
- [`rea/01-evidence/`](rea/01-evidence/) — the REA evidence bundle behind every claim.

Verified against the published RFC and FIPS test vectors and by 580
differential comparisons against an independent transcription of the same
instructions.

## The vendor camera configuration

The blobs that describe every camera module of the factory firmware —
`com.qti.sensormodule.*.bin` — hold the sensor, the module, the I2C slaves,
the register tables of the power-up sequence, the lane assignment and the
resolution tables. Their format is now documented, and the tools that decode
them are committed.

- [`rea/02-notes/camera-sensormodule.md`](rea/02-notes/camera-sensormodule.md) — the format, the inventory, and what the blob does *not* contain.
- [`rea/04-tools/`](rea/04-tools/) — the parser, the inventory, and the hardware diagnostics the camera notes refer to (`mmr`, the CSIPHY lane decoder, the read-only diagnostic).

Across the twelve blobs that is **1 052 power-up steps and about 1.2 million
register writes**, covering the IMX682, S5K3T2, HI1337, HI259, GC02M1B and
OV02B1B sensors.
