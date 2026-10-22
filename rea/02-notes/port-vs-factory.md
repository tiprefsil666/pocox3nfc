# What this port enables, and what is still missing

**A comparison**: the stock firmware's device tree, against the device
tree this port's kernel produces.

**How it was made**: the 140 patches applied to the pinned base, and the
result compared with the factory tree that the upstream project
publishes. Both trees are checked with
[`../04-tools/dt_crosscheck.py`](../04-tools/dt_crosscheck.py).

---

## The method

### 1. The series still applies

```sh
build/15-verify-series.sh
```

The base is the tarball of the tag `v7.1_rc3` of
`sm7150-mainline/linux` — **exactly what the build downloads and
unpacks**, so the check is a check against the build, not against a
git checkout that might differ.

The result, on 2026-10-22:

```
tag:    v7.1_rc3
commit: 1fd06fd169a9470c55bb4eb9ca417b797828dc8f
aplicam: 140
não aplicam: 0
```

**All 140 apply, in order, cleanly.** The commit is written down,
because a tag can move and a build that changes under you is not a
build.

> 📌 **A tag that moves is a real hazard here.** The `v7.1_rc3` tag of
> the upstream kernel is what the pmaports recipe downloads, by name. If
> it is ever re-pointed, the build silently starts from a different
> tree. The `15-verify-series.sh` step is what catches it.
>
> This is not hypothetical: the upstream history shows a **"WIP WCD
> stuff"** commit and its **revert**, both on 2026-05-13, on the same
> branch as the tag. The tree at the tag does **not** have the WCD9375
> — which is what our patch 0031 adds.

### 2. The trees compared

The factory tree is `sm7150-mainline/downstream-fdt`'s `fdt-surya` —
the stock firmware's own device tree, published by the upstream project.
It is the reference for what the hardware can do.

Our tree is the same base with the 140 patches applied.

---

## The comparison

| Component | Factory | This port | Note |
|---|---|---|---|
| **TAS2562 / TAS2564** (speakers) | ✅ | ✅ | the amplifiers and their DAI link |
| **WCD9375** (microphones) | ✅ | ✅ | **our patch 0031** — upstream does not have it |
| **BQ25970** (charge pump) | ✅ | ✅ | **our patch 0002** — the fast charging |
| **PM6150 QG** (fuel gauge) | ✅ | ✅ | the gauge, monitoring the `battery` node |
| **Type-C controller** | ✅ | ✅ | the PM6150's, with the USB-C connector |
| **Touchscreen** (NT36672C) | ✅ | ✅ | over SPI, with its firmware |
| **FSA4480** (USB-C audio) | ✅ | ❌ | **the recipe is written** — see below |
| **NFC** (NXP NCI) | ✅ | ❌ | not wired in the mainline tree |
| **Fingerprint** (goodix) | ✅ | ❌ | not wired in the mainline tree |
| **Camera IR LED** | ✅* | ❌ | *in the DTBO overlay, not the base tree |
| **IR remote emitter** | ❌ | ❌ | **not in the factory either** |

> 📌 **The WCD9375 and the BQ25970 are ours.** The upstream project's
> component table marks both as "N", and the upstream kernel branches
> `v7.1_rc3` and `v7.2` do not have them. This port does.
>
> That is the difference between catching up and being ahead, and it is
> worth stating plainly: on these two, and on the camera work, this
> port is ahead of the community.

---

## The four gaps

### 1. The FSA4480 — the USB-C analogue audio

**The cheapest one, and the recipe is written.** The mainline driver
exists (`drivers/usb/typec/mux/fsa4480.c`), the kernel configuration
already has `CONFIG_TYPEC_MUX_FSA4480=y`, the I²C bus the chip lives on
(`i2c9`, the QUPv3 SE9) **is already enabled** by patch 0042, and the
factory tree gives the address (`0x43`), the enable pin (GPIO 42) and
its configuration.

What is missing is three hunks of device tree. The whole recipe, with
the factory tree, the driver's requirements and the mainline reference
board, is in [`usb-c-audio-fsa4480.md`](usb-c-audio-fsa4480.md).

### 2. The NFC

The factory tree has the NXP NCI node:

```dts
nq@28 {
    compatible = "qcom,nq-nci";
    reg = <0x28>;
    qcom,nq-irq = <0x178 0x25 0x00>;
    ...
    interrupt-names = "nfc_irq";
};
```

The mainline driver is `drivers/nfc/nxp-nci`, and the upstream project's
wiki lists NFC as **working**. But the mainline device tree for the
surya does not have the node.

So this is **not** a driver problem — the driver is upstream and it
works. It is the same kind of gap as the FSA4480: a node, a bus and an
interrupt.

> ⚠️ **The chip identification is not settled.** The wiki's component
> table says *"NQX NCI NXP55303 (PN553 type)"*, while the firmware
> analysis found a **PN557** — same family, but not the same part. The
> factory tree's compatible is the family-level `"qcom,nq-nci"`, which
> sidesteps the question. The device node is `/dev/nq-nci` in the
> firmware too.
>
> See [`nfc-pn557.md`](nfc-pn557.md).

### 3. The fingerprint reader

The factory tree has a `goodix_fp` node and a `fpc1020` one — two
readers, or one and something else. The mainline has
`drivers/input/fingerprint`, and the tree for the surya does not have
the node.

Not investigated here. The survey is in
[`upstream-parallel-work.md`](upstream-parallel-work.md): the upstream
wiki lists the fingerprint as **Broken**, so this one is not a gap
against the community — it is a gap against the hardware.

### 4. The camera IR LED

In the factory it is in the **DTBO overlay**, not in the base tree:

```dts
ir_led: camera-ir-led@0 {
    compatible = "qcom,camera-ir-led";
    pwms = <&pm6150l_pwm_1>, <0x00 0x00>;
    enable-active-high;
    gpios = <&tlmm>, <0x49 0x00>, <&tlmm>, <0x4a 0x00>;
    qcom,gpio-req-tbl-label = "IR_CUT_FILTER_P", "IR_CUT_FILTER_M";
};
```

The mainline has no driver for it at all. Small work, but it is a
driver and not just a node.

---

## The IR remote control emitter — not in the factory either

Worth repeating, because it is the one component where **the factory
and this port agree**: there is no remote control emitter.

The factory tree has `spi@a80000` — the SPI the Android infrared HAL
drives through `/dev/spidev0.1` — with `status = "disabled"`, and no
LED child. The upstream project's tree says exactly the same. The
upstream wiki lists the feature as **"IR TX: Broken"**.

The camera's IR LED and its IR-cut filter are a different thing
entirely. See [`ir-and-fm.md`](ir-and-fm.md).

---

## The OCV table is a per-device calibration, and it is in a shared patch

This one is not a gap but a **hazard**, and it is worth being explicit
about.

The battery's percentage comes from a table of open-circuit voltages
against measured capacity. The factory kernel interpolates linearly
between the design minimum and maximum voltages, which for a lithium
cell is badly wrong where it matters: at 3.68 V the cell in this phone
had 8 % left and the linear model claimed 28 %.

The fix is two patches:

- **0004** — the driver (`qcom_qg.c`) learns to use the table when the
  node has one;
- **0126** — the table itself, measured on this device.

And **0117**, six days earlier, **removes** the upstream table, with
this in the commit message:

> *"The ocv-capacity-table in this node was measured on this phone's
> original battery. That battery has been replaced, and such a table is
> only ever valid for the cell it was measured on: its percentage axis
> is anchored to that cell's real measured capacity, not to anything
> general.*
>
> *Left in place it is worse than nothing, because it reports a
> calibrated-looking percentage that is wrong for the new cell."*

So the sequence is: the original battery's table is removed, a new one
is measured on the replacement cell, and it is added back. The work is
careful and correct.

**But the table is now in a patch that everybody applies**, and it
belongs to one specific cell. Anyone who builds this kernel and has a
different battery gets a confidently wrong percentage — precisely what
0117 warns about.

> 📌 **What to do about it.** Three options, in order of taste:
>
> 1. **Leave it, and document it.** The table is a measured
>    improvement, and a user with a different cell can delete the two
>    properties and fall back to the linear interpolation, which is
>    crude but honest. This is what the code does today.
> 2. **Make it per-device.** A `qcom,ocv-capacity-table` read from a
>    place that is not shared — a bootloader variable, a calibration
>    partition, a `qcom,` property. More work, and it needs somewhere
>    to put the per-device data.
> 3. **Move it to a separate overlay**, applied only to the phone whose
>    battery was measured.
>
> The honest answer, for a port that is shared, is that the table is
> **data, not a patch**, and it wants to live somewhere that says
> whose battery it is.

---

## Reproducing this comparison

```sh
# 1. the series still applies
build/15-verify-series.sh

# 2. the factory tree
git clone --depth=1 https://github.com/sm7150-mainline/downstream-fdt
dtc -I dtb -O dts downstream-fdt/fdt-surya > factory.dts

# 3. our tree, with the series applied
#    (15-verify-series.sh leaves it at build/out/series-check/tree/)
cat build/out/series-check/tree/linux-7.1_rc3/arch/arm64/boot/dts/qcom/sm7150*.dtsi \
    > ported.dts

# 4. the comparison
rea/04-tools/dt_crosscheck.py --dts factory.dts
rea/04-tools/dt_crosscheck.py --dts ported.dts
```
