# Mapping local firmware to postmarketOS work

| Local artifact | Path | Use in port work |
| --- | --- | --- |
| Decompiled vendor filesystem | `decoded-firmware/rootfs/vendor/` | Inspect HALs, configs, services, proprietary libraries, and module loading dependencies. |
| Compiled vendor kernel modules | `decoded-firmware/blobs/vendor_modules/modules/` | Use as behavior and symbol references; compare dependencies with mainline drivers. |
| Vendor firmware | `decoded-firmware/blobs/vendor_firmware/firmware/` | Identify required firmware names and device-specific calibration/configuration. |
| Kernel image | `decoded-firmware/boot/kernel.uncompressed` | Extract build strings and compare symbols/configuration with available SM7150 kernel sources. |
| Boot DTB bundle | `decoded-firmware/boot/dtb` | Inspect board description; it may contain multiple concatenated device trees. |
| Factory DT overlays | `../android/firmware-update/dtbo.img` | Reference original panel and peripheral overlays. |
| DSP image | `../android/firmware-update/dspso.bin` | Qualcomm DSP firmware reference. |
| Modem image | `../android/firmware-update/NON-HLOS.bin` | Radio firmware reference. |
| Bluetooth firmware | `../android/firmware-update/BTFM.bin` | Bluetooth firmware reference. |
| Boot chain | `../android/firmware-update/` (`xbl`, `abl`, `tz`, `hyp`, etc.) | Partition map and boot-chain analysis only. |

All decoded images and source artifacts should remain immutable. Store derived
patches, notes, and tool outputs in this `postmarketos/` tree and include the
source image hash when recording a finding.
