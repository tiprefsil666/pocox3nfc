# pocox3nfc

Workspace and porting notes for postmarketOS on the Xiaomi POCO X3 NFC
(`surya`, Qualcomm SM7150).

## Contents

- [`surya-pmos/`](surya-pmos/): device overlay, kernel patches, packages and port documentation.
- [`postmarketos/verificacao-blobs/`](postmarketos/verificacao-blobs/): inventory of Android-derived components and postmarketOS port status.
- [`postmarketos/INTEGRATION.md`](postmarketos/INTEGRATION.md): integration notes for the SM7150 prebuilt image.
- [`postmarketos/PREBUILT.md`](postmarketos/PREBUILT.md): notes about the local prebuilt image, which is not included here.

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
