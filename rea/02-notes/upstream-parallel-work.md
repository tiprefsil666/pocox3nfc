# Parallel work: what is already tested out there

**What this is**: a survey of the other efforts on the same hardware, so
that this port does not redo work that is already done — and so that the
places where this port is *ahead* are known.

Everything here was read from the public sources in October 2026. Nothing
was tested on hardware by us.

> 📌 The names changed: **postmarketOS is now "Nura"**, and the wiki moved
> to `wiki.nura.eco`. The old `wiki.postmarketos.org` redirects there.

---

## The people behind it

The upstream SM7150 effort is a small group, and the same people are
behind all of it:

| | |
|---|---|
| **Aelin** (Aelin Reidel) | maintainer of the generic SM7150 port, the pmaports packages, the u-boot and the alsa-ucm-conf |
| **JIaxyga** (Danila Tikhonov) | the original surya port, the audio configuration, the `sm7150-mainline/linux` fork |
| **Ungeskriptet** | the NixOS port, and the libcamera autofocus work upstreaming |
| **Vasiliy Doylov** (nekocwd) | the libcamera focus control upstreaming |
| **Pavel Machek** | reviewing and polishing the libcamera focus work |
| **Milan Zamazal** (Red Hat) | the libcamera maintainer, who merged the focus work |

---

## The upstream project: `sm7150-mainline`

<https://github.com/sm7150-mainline> — the kernel, the bootloader, the
audio configuration, the firmware and the package recipes for every SM7150
device.

| Repository | What it is |
|---|---|
| [`linux`](https://github.com/sm7150-mainline/linux) | the mainline kernel fork. The default branch is `v7.2`; `master` is the development one |
| [`u-boot`](https://github.com/sm7150-mainline/u-boot) | the bootloader. One image per device **and per panel** |
| [`alsa-ucm-conf`](https://github.com/sm7150-mainline/alsa-ucm-conf) | the ALSA Use Case Manager configuration — the audio routing |
| [`pmaports`](https://github.com/sm7150-mainline/pmaports) | a **fork** of the postmarketOS package recipes, on the branch `generic` |
| [`nightly-builds`](https://github.com/sm7150-mainline/nightly-builds) | weekly automated images for every supported device |
| [`downstream-fdt`](https://github.com/sm7150-mainline/downstream-fdt) | the device trees of the stock firmware, for every device |
| [`firmware-xiaomi-surya`](https://github.com/sm7150-mainline/firmware-xiaomi-surya) | the proprietary firmware blobs, packaged |

### `downstream-fdt` — the device tree of the stock firmware

This is the one that matters most for the analysis here: `fdt-surya` is
**the device tree of the POCO X3 NFC's own firmware**, published and
maintained by the upstream project. It is the cross-check for everything
nos apontamentos desta pasta.

It confirms three things that were inferred here from the factory firmware:

- **The SPI0 is disabled.** `spi@a80000` — the one the Android infrared
  HAL drives through `/dev/spidev0.1` — has `status = "disabled"`, in the
  upstream tree as well as in the factory DTBO. The only SPI with a device
  on it is `spi@880000`, the NT36672C touchscreen.
- **There is no infrared node at all.** No `ir-spi-led`, no
  `qcom,camera-ir-led` — the camera's IR LED lives in the DTBO overlay,
  not in the base tree.
- **The FM is a WCN feature.** The sound card carries
  `qcom,wcn-btfm = <0x01>`, which is the Bluetooth-chip FM transport — the
  same conclusion the firmware analysis reached.

And it answers one open question:

- **Which `mixer_paths` is the right one?** The sound card's
  `qcom,model` is **`sm6150-wcd9375-snd-card`**. The audio HAL picks the
  file by that name: `sm6150-<variant>-snd-card` →
  `mixer_paths_<variant>.xml`. So the answer is
  **`mixer_paths_wcd9375.xml`**, and not `mixer_paths_idp.xml` — despite
  the board's top-level `model` being `"IDP"`.

  The DT also confirms the NFC is the NXP NCI: `compatible = "qcom,nq-nci"`.

---

## The official installation, as tested

From the wiki: [Qualcomm SM7150 (qcom-sm7150)](https://wiki.nura.eco/wiki/Qualcomm_SM7150_(qcom-sm7150))
and [Xiaomi POCO X3 NFC (xiaomi-surya)](https://wiki.nura.eco/wiki/Xiaomi_POCO_X3_NFC_(xiaomi-surya)).

```sh
# the u-boot for this phone's panel
fastboot erase dtbo
fastboot flash boot u-boot-sm7150-xiaomi-surya-<panel>.img

# and the rootfs
pmbootstrap install
pmbootstrap flasher flash_rootfs
```

Things worth knowing that are not obvious:

- **The device package is the generic `qcom-sm7150`**, not
  `device-xiaomi-surya`. The per-device packages were removed in March
  2025, in favour of one generic package, because U-Boot can now pick the
  right device tree itself.
- **The U-Boot is chainloaded from the stock bootloader.** The primary
  bootloader is not replaced: U-Boot goes into the `boot` partition and the
  stock bootloader chainloads it. (The bootloader still has to be
  unlocked.)
- **The rootfs goes to `userdata`.**
- **OpenRC is not supported** for this device package. systemd only.
- **The partition layout changed completely** with the switch to U-Boot.
  The old layout and the new one are incompatible, and there is no
  migration — it is a fresh install or nothing. See
  [the migration note](https://postmarketos.org/edge/2025/03/09/sm7150-generic-migration/).
- **The firmware no longer has to be packaged.** Since
  `msm-firmware-loader` 1.6.0, the firmware is loaded from the Android
  partitions.

### Which panel is this phone?

The wiki's method, and it is better than reading a property:

```sh
adb wait-for-device && adb reboot && adb logcat | grep "panel name is"
```

It prints `panel name is Huaxing` or `panel name is Tianma`. The device
name (`ro.product.device`) is a second opinion: `surya` for the Huaxing,
`surya_tianma` for the Tianma.

### The UART is 1.8 V

The POCO X3 NFC uses **1.8 V** for the UART, not 3.3 V. A TTL adapter that
outputs 3.3 V needs a divider, or the phone's GPIO is at risk. The RX pin
is pulled up in software in Linux and U-Boot, but for a log that survives
a reboot the pull-up has to be in hardware.

---

## The official feature status

From the wiki's device page. This is the community's tested state, and it
is the baseline to compare against.

| | Status | |
|---|---|---|
| Flashing | **Works** | `pmbootstrap flasher` |
| Screen | **Works** | |
| Touchscreen | **Works** | NT36672C, over SPI, needs firmware |
| Buttons | **Works** | |
| Wi-Fi, Bluetooth | **Works** | |
| **Modem: calls, SMS, data** | **Works** | |
| **NFC** | **Works** | NXP NCI |
| USB OTG | **Works** | |
| Internal storage, SD card | **Works** | |
| FDE, unlocking with unl0kr | **Works** | |
| Sensors (accelerometer, magnetometer, ambient light, proximity) | **Works** | |
| Haptics | **Works** | AW8624 |
| 3D acceleration | **Works** | |
| Camera flash | **Works** | |
| **Audio** | **Partial** | playback, microphone, headset and buttons |
| **Battery** | **Partial** | charging and level reporting |
| USB host | **Partial** | |
| **Camera** | **Broken** | |
| **IR TX** | **Broken** | |
| **GPS** | **Broken** | |
| Fingerprint | **Broken** | |

### The component table

Also from the wiki, and it is more precise than the feature list.

| Component | | Status |
|---|---|---|
| Touchscreen | NT36672C | **Y** — over SPI, needs firmware |
| Accelerometer, gyroscope | BMI220 | **Y** — through the SSC |
| Ambient light, proximity | STK3A5X | **Y** |
| Magnetometer | AK09918C | **Y** |
| Haptics | AW8624 | **Y** |
| **Main speaker** | TAS2562 | **Y** |
| **Earpiece** | TAS2564 | **Y** |
| Fuel gauge | qcom,pm6150-qg | **P** |
| **Microphones** | WCD9375 | **N** — supported in the mainline `wcd937x.c` |
| **USB-C analogue audio** | fcs,fsa4480 | **N** — supported in the mainline `fsa4480.c` |
| Charging | qcom,qpnp-smb5 / BQ25968 | **N** |
| Camera regulator | longcheer,wl2866d | **N** |
| **Cameras** | IMX682, S5K3T2, Hi-1337, Hi-259, OV02B1B | **N** — all of them |
| NFC | NXP55303 (PN553 type) | **Y** |

> 📌 **The two "N" that the mainline already has the driver for are the
> two this port has been fighting**: the WCD9375 microphones and the
> FSA4480 USB-C audio. Both drivers exist upstream
> (`sound/soc/codecs/wcd937x.c` and
> `drivers/usb/typec/mux/fsa4480.c`); they are not wired to this board.
> That is a **device tree** job, not a driver job — which makes it a very
> different proposition from the camera, where the hardware itself is the
> problem.

### A quirk worth knowing

There is an error unlocking the SIM card in slot 1. If it fails with an
internal error, try the SD-card/SIM-shared slot.

---

## The audio configuration: `alsa-ucm-conf`

<https://github.com/sm7150-mainline/alsa-ucm-conf> — the UCM
configuration, packaged in pmaports as `alsa-ucm-conf-qcom-sm7150` and
pulled in by the `device-qcom-sm7150` package.

For the POCO X3 NFC it has:

- `ucm2/Xiaomi/surya/HiFi.conf` — the speaker profile;
- `ucm2/conf.d/sm8250/POCO X3.conf` — the use case that points at it;
- symlinks with the vendor's device names
  (`xiaomi-XiaomiPOCOX3NFCHuaxing.conf` and the Tianma ones), "for
  U-Boot compatibility".

> ⚠️ **This package collides with this port's own audio configuration.**
> The port's `scripts/install-on-device.sh` writes `HiFi.conf`,
> `POCO-X3.conf` and `VoiceCall.conf` into
> `/usr/share/alsa/ucm2/conf.d/sm8250/`, and the official package
> installs `POCO X3.conf` — **with a space, not a hyphen** — into the same
> directory, with the profile itself in `Xiaomi/surya/`.
>
> The result on a current build is two "HiFi" use cases, one of them the
> simple upstream speaker profile, and a "Voice Call" use case pointing at
> a `VoiceCall.conf` that was never installed. See §4.5 of the roadmap.

For comparison, the upstream surya profile is 18 lines: a mono speaker
and nothing else. This port's is 172, with the stereo split, the
amplifier gains and the microphone capture.

---

## The NixOS port

<https://codeberg.org/ungeskriptet/nixos-qcom> — a NixOS port of the same
hardware, by the same upstream people.

It is worth looking at for three reasons:

- **It has one device per panel**: `xiaomi-surya-huaxing` and
  `xiaomi-surya-tianma`. The panel problem, solved by naming.
- **It uses the same `alsa-ucm-conf`** — a commit from October 2025, so
  slightly older than the one pmaports uses.
- **It uses the kernel 6.18.0** from the same fork, where pmaports is on
  7.1-rc3. Two ports, two kernel versions, the same tree.

It also carries modules for the same pieces: `hexagonrpcd`, the audio
setup, the USB tethering, the `hkdm` (ModemManager) and the
`qcom-services`.

---

## The libcamera focus work — this port's patches are being upstreamed

**This is the most important finding for this port.**

The two patches in `surya-pmos/packages/libcamera/` are the manual focus
(0004) and the autofocus (0005). The same design was independently
proposed upstream, and **it has been merged**:

| Upstream commit | Date | What |
|---|---|---|
| [`7231d3177`](https://gitlab.freedesktop.org/camera/libcamera/-/commit/7231d3177) `software_isp: Add focus control` | 2026-02-26 | Vasiliy Doylov — **the same approach as our 0004**: the `setSensorControls` signal grows a `lensControls` argument, the `Af` algorithm appears in `src/ipa/simple/algorithms/af.cpp`, `- Af:` is added to `uncalibrated.yaml`, and the simple pipeline calls `focusLens->setFocusPosition()` |
| [`bfcd9e133`](https://gitlab.freedesktop.org/camera/libcamera/-/commit/bfcd9e133) `libcamera: software_isp: Add variance to stats` | 2026-10-21 | Milan Zamazal — **the sharpness measure that our 0005 computes**, called "variance" upstream |
| [`a594b8900`](https://gitlab.freedesktop.org/camera/libcamera/-/commit/a594b8900) `ipa: softisp: Add Af algorithm` | 2026-10-21 | Milan Zamazal — the `Af` algorithm for the software ISP |
| [`9d1793335`](https://gitlab.freedesktop.org/camera/libcamera/-/commit/9d1793335) `libcamera: software_isp: Add autofocus controls` | 2026-10-21 | Milan Zamazal — the lens controls are passed around and the autofocus values are read and written |

The review thread is in the
[libcamera-devel archive](https://lists.libcamera.org/pipermail/libcamera-devel/2026-February/057562.html),
with Milan Zamazal (the maintainer) doing the review.

> 📌 **Upstream is at exactly the stage this port's 0005 is at.** The
> commit message of `a594b8900` says it plainly: *"The algorithm is not
> enabled yet because there are no autofocus stats computed."* The
> variance is added to the statistics, but nothing computes it yet. The
> port's 0005 computes a sharpness measure and uses it to drive the lens;
> upstream has the plumbing and is waiting for the same measurement.
>
> This port's 0005 is therefore **not a patch to keep forever**: it is a
> local implementation of something the upstream is doing, and the right
> end state is the upstream one.

**None of this is in a release yet.** The newest tag is **v0.7.2**, and
these commits are in `main`. The port's overlay pins **0.7.1**, and the
current pmaports is on **0.7.2** — so the port's overlay currently
*downgrades* libcamera in a current build. That is a deliberate choice
(the patches were verified against 0.7.1) and it is recorded in the
roadmap.

### The history of the focus work

- [libcamera, Librem 5 and autofocus](https://lists.libcamera.org/pipermail/libcamera-devel/2025-April/049735.html)
  — Pavel Machek, April 2025: *"I played a bit with libcamera on Librem
  5, and got autofocus to work (slowly!)"*, and the tree is at
  `gitlab.com/tui/libcamera`, branch `l5`.
- [software_isp: Add focus control](https://lists.libcamera.org/pipermail/libcamera-devel/2026-February/057562.html)
  — the merged patch.
- [fairphone6-wide-camera-linux](https://github.com/nondescriptpointer/fairphone6-wide-camera-linux)
  — a **working** mainline camera pipeline on the Fairphone 6 (SM7635),
  with a full capture path, the software ISP, auto-exposure and AWB, and
  gstreamer and PipeWire. It is "experimental" and targets one device and
  one kernel revision, but it is the closest thing to a reference for
  what a working camera port looks like.

---

## What the upstream port does *not* do

The community's port has, by its own status table:

- **no working camera** — all five sensors are "N";
- **no IR** — "IR TX: Broken";
- **no GPS**;
- **partial audio** — the microphones (WCD9375) and the USB-C audio
  (FSA4480) are not wired;
- **partial battery** — the BQ25970 charge pump is not in the kernel.

Those four are exactly the areas this port has been working on. The
upstream port is the **reference for the parts that work** — the display,
the touch, the modem, the NFC, the sensors, the bootloader — and it is
the **baseline to beat** on the four that do not.

---

## The people to ask

- The `#sm7150-mainline` room on Matrix
  (<https://matrix.to/#/#sm7150-mainline:matrix.org>) and the postmarketOS
  chatrooms.
- Aelin, JIaxyga and Ungeskriptet are the maintainers listed on the
  device's wiki page.

## A summary of the sources

| Source | What it gave |
|---|---|
| [wiki.nura.eco — qcom-sm7150](https://wiki.nura.eco/wiki/Qualcomm_SM7150_(qcom-sm7150)) | the installation procedure, the U-Boot chainload, OpenRC not supported |
| [wiki.nura.eco — xiaomi-surya](https://wiki.nura.eco/wiki/Xiaomi_POCO_X3_NFC_(xiaomi-surya)) | the feature and component tables, the panel detection, the 1.8 V UART, the SIM quirk |
| [the SM7150 migration note](https://postmarketos.org/edge/2025/03/09/sm7150-generic-migration/) | the new partition layout, and why there is no migration |
| [sm7150-mainline/downstream-fdt](https://github.com/sm7150-mainline/downstream-fdt) | the device tree of the stock firmware — the cross-check for the analysis |
| [sm7150-mainline/alsa-ucm-conf](https://github.com/sm7150-mainline/alsa-ucm-conf) | the official audio configuration, and the collision with this port's |
| [sm7150-mainline/nightly-builds](https://github.com/sm7150-mainline/nightly-builds) | the weekly tested images, and the envkernel build flow |
| [sm7150-mainline/pmaports](https://github.com/sm7150-mainline/pmaports) | the fork of the package recipes, with the per-panel device packages |
| [the libcamera focus series](https://gitlab.freedesktop.org/camera/libcamera/-/commits/master) | the upstreaming of this port's own two patches |
| [codeberg.org/ungeskriptet/nixos-qcom](https://codeberg.org/ungeskriptet/nixos-qcom) | the parallel NixOS port |
