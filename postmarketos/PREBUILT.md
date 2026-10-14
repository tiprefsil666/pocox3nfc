# Prebuilt image inspection

File: `20261009-0834-postmarketOS-v26.06-plasma-mobile-6-qcom-sm7150.img`

This is the BPO `v26.06 / qcom-sm7150 / plasma-mobile` build dated
`20261009-0834`. The SM7150 generic port includes the POCO X3 NFC (`surya`);
the device wiki directs Surya users to the generic SM7150 installation guide.

## Image identity

- Length: 4,970,250,240 bytes (4.63 GiB)
- SHA-256: `d87e18dc9acdeea4361f628fb3a12f052fed275dafac1a8efaa7117822b8b8ec`
- Logical sector size: 4096 bytes; GPT header is at byte offset 4096 (LBA 1).
- `fdisk`'s default 512-byte sector interpretation reports only a protective
  MBR. Use a 4096-byte sector-aware GPT parser for the partition table.

## Partitions

| # | Label / type | Start byte | Size bytes | Filesystem | UUID |
| --- | --- | ---: | ---: | --- | --- |
| 1 | `pmOS_boot` / EFI System | 8,388,608 | 503,316,480 | FAT32, 4096-byte blocks | `78CB-8628` |
| 2 | `pmOS_root` | 511,705,088 | 4,457,496,576 | ext4, 4096-byte blocks | `07d21640-5725-4c40-b360-75e3403f385d` |

The image contains a 480 MiB FAT boot partition followed by a 4.15 GiB ext4
root partition. `blkid -p -O 8388608 <image>` and
`blkid -p -O 511705088 <image>` inspect the filesystems without writing to
the image. I also split them into `prebuilt/bootpart.img` and
`prebuilt/rootfs.ext4`, leaving the original image intact. The FAT check finds
21 files. The root filesystem reports `postmarketOS v26.06`, and
`/usr/lib/modules/7.1.0-rc3-sm7150/` contains kernel module metadata and the
kernel module tree.

The installed package selection includes `device-qcom-sm7150` and
`postmarketos-ui-plasma-mobile`. The root filesystem can be browsed without
mounting it, for example:

```sh
debugfs -R 'ls -l /usr/lib/modules/7.1.0-rc3-sm7150/kernel' prebuilt/rootfs.ext4
debugfs -R 'cat /etc/apk/world' prebuilt/rootfs.ext4
```

## Local pmbootstrap

`pmbootstrap/pmbootstrap.py -V` reports 3.12.1. The source tree is present,
but it has no `.git` metadata and no local `pmaports` checkout. pmbootstrap
needs the packaging repository to initialize a device build; fetching that
repository is currently blocked because this shell cannot resolve the
upstream Git hosts. `fetch-upstream.sh` will retry the requested SM7150 source
first when network access is available.

This is a prebuilt reference image, not a Surya-specific firmware dump. Keep
it unchanged and use the extracted Android vendor tree alongside it when
comparing firmware requirements. The generic SM7150 installation guide
requires the SM7150 U-Boot and the correct Surya panel variant.
