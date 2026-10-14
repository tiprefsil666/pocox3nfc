# POCO X3 NFC postmarketOS port workspace

Device: Xiaomi POCO X3 NFC, codename `surya`, SoC Qualcomm SM7150.

This workspace now also contains the prebuilt v26.06 Plasma Mobile image and
the pmbootstrap 3.12.1 source tree. See [PREBUILT.md](PREBUILT.md) for its
partition layout and hashes. The prebuilt is the generic SM7150 image; the
upstream device guide lists `surya` as supported by this generic port.

## Upstream projects to fetch

- `postmarketOS/pmaports` is the official package/port repository. Its current
  default branch is `main`; the relevant recipes are the `device-xiaomi-surya`
  device package and `linux-postmarketos-qcom-sm7150` kernel package.
- `sm7150-mainline/postmarketos` is an archived mirror of the SM7150 device,
  firmware and kernel packages that were incorporated into pmaports.
- `woodyst/surya-pmos` is a community overlay with additional kernel patches,
  device configuration and userspace integration. Its README says this is a
  hobbyist port, and that a clean end-to-end build has not been verified.

Run `./fetch-upstream.sh` from this directory when network access is available.
It downloads these sources into `upstream/` without mixing their files into
the local firmware workspace. The system currently cannot resolve GitHub from
the terminal (`Could not resolve host: github.com`), so the source checkouts
could not be downloaded in this session. The script is ready to retry.

## Decoded firmware

`decoded-firmware` links to `../android/extracted/`, created from the local
Android OTA. It includes raw ext4 partition images, the unpacked boot image,
the entire vendor filesystem, module files, firmware files, and hash indexes.
See [`../android/RE_NOTES.md`](../android/RE_NOTES.md) for the extraction and
inspection details.

Keep the factory blobs as reverse-engineering references. Android `.ko`
modules target the vendor Android kernel ABI and cannot be assumed to work on
the mainline SM7150 kernel. Map behavior and firmware requirements back to
mainline drivers; do not redistribute proprietary vendor firmware in source
patches.

The POCO X3 NFC has Huaxing and Tianma display variants. Check the device-tree
and bootloader variant before any device testing; a mismatch can leave the
screen black.
