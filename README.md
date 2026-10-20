# pocox3nfc

Workspace and porting notes for postmarketOS on the Xiaomi POCO X3 NFC
(`surya`, Qualcomm SM7150).

## Contents

- [`surya-pmos/`](surya-pmos/): device overlay, kernel patches, packages and port documentation.
- [`postmarketos/verificacao-blobs/`](postmarketos/verificacao-blobs/): inventory of Android-derived components and postmarketOS port status.
- [`postmarketos/INTEGRATION.md`](postmarketos/INTEGRATION.md): integration notes for the SM7150 prebuilt image.
- [`postmarketos/PREBUILT.md`](postmarketos/PREBUILT.md): notes about the local prebuilt image, which is not included here.
- [`rea/`](rea/): reverse-engineering workspace — the analysis of Xiaomi's proprietary binaries, the REA evidence bundle, the tools, and a clean-room C reimplementation.

Android firmware, extracted proprietary blobs, and prebuilt disk images are
excluded from this public repository. Use firmware obtained for your own
device and follow the relevant vendor and project licenses.

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
