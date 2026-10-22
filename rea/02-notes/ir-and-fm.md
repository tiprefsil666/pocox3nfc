# Infrared and FM radio: what is actually on this board

**Source**: MIUI `V12.0.6.0.QJGMIXM` (Android 10, `surya`), the factory firmware.
**Tools**: [`../04-tools/ir_fm_config.py`](../04-tools/ir_fm_config.py)

> Static analysis only. Nothing was run on hardware, no infrared code was
> transmitted and no radio was tuned.

Both of these are asked about often, and both are **not** what people expect.
In particular, the three things that get called "infrared" on this phone are
three different things, and the FM radio is not a separate chip at all.

---

## Infrared: three different things

### 1. The camera's infrared LED and its IR-cut filter

This is the one that is really in the hardware, and it is in the device tree:

```
ir_led: camera-ir-led@0 {
    compatible = "qcom,camera-ir-led";
    pwms = <&pm6150l_pwm_1>, <0x00 0x00>;
    enable-active-high;
    gpios = <&tlmm>, <0x49 0x00>, <&tlmm>, <0x4a 0x00>;
    qcom,gpio-ir-p = <0x00>;
    qcom,gpio-ir-m = <0x01>;
    qcom,gpio-req-tbl-label = "IR_CUT_FILTER_P", "IR_CUT_FILTER_M";
    status = "ok";
};
```

The two GPIOs, **73 and 74**, are the **IR-cut filter** of the front camera —
a mechanical shutter that either passes or blocks the infrared, so the sensor
can be switched between visible light and IR. The pinctrl states are named for
what they do:

```
cam_sensor_ir_led_on:  { pins = "gpio73", "gpio74"; bias-disable; }
cam_sensor_ir_led_off: { pins = "gpio73", "gpio74"; bias-pull-down; }
```

The LED itself is on the PWM of the PM6150 LDO (`pm6150l_pwm_1`). It illuminates
the scene in IR so the sensor can see in the dark.

> This is **not** a remote control emitter, and it is not what "the infrared"
> means in the Android settings. It is a camera feature: the front camera's
> night mode.

### 2. The infrared remote control emitter — the SPI LED

Android's infrared HAL is `lib64/hw/consumerir.default.so`, and it says
exactly what it drives:

```
ro.lirc.dev
/dev/spidev0.1
carrier_freq = %d,pattern_len=%d
xubuchao_debug:consumerir_transmit
xubuchao_debug:consumerir_open
```

So the remote control emitter is an **SPI LED on the QUPv3 SPI0**, and the
HAL writes the pulse pattern to `/dev/spidev0.1` as raw SPI data, with the
carrier frequency and the pattern length given separately.

But:

- **The QUPv3 SPI0 node is `status = "disabled"`** in the factory's device
  tree overlay, and it has **no child device** — no `ir-spi-led`, no
  `led-active-low`, no `duty-cycle` anywhere in the DTBO.
- **The factory kernel has no infrared driver.** There is no `ir-spi`,
  `consumerir` or `gpio-cir` module among the 38 vendor modules, and no
  `m88w8997` (the Xiaomi IR LED part) in the kernel image.
- The `consumerird` binary is a **factory test** tool, not the service: it
  logs *"consumerir lirc auto test implement successful"* and does nothing
  else.

> ⚠️ **Conclusion: the remote control emitter is very likely not populated on
> this board, or at least not enabled by the factory firmware.** The HAL is
> present and would drive `/dev/spidev0.1`, but nothing in the device tree
> or the kernel brings that SPI up or describes the LED. The camera's IR LED
> and its filter are present and described; the remote control path is not.
>
> This is worth confirming on the device before anyone writes a driver:
> look for the LED physically, and check whether `ir-spi-led` appears
> anywhere in the running device tree.

> 📌 **Independently confirmed by the upstream project.** The
> `sm7150-mainline/downstream-fdt` repository publishes the device tree of
> the stock firmware of every SM7150 device, and its `fdt-surya` says the
> same thing: `spi@a80000` — the SPI0 that the infrared HAL drives — has
> `status = "disabled"`, and the **only** SPI with a device attached is
> `spi@880000`, the NT36672C touchscreen. There is no infrared node in
> that tree at all.
>
> The upstream wiki lists the feature as **"IR TX: Broken"**, which is
> the community's tested answer to the same question.
>
> See [`upstream-parallel-work.md`](upstream-parallel-work.md).

### 3. The `qcom,ires-ua` property

`qcom,ires-ua` appears in the device tree next to the LED properties of the
flash and the LPG channels. It is a **Qualcomm LED driver** property, part of
the same subsystem as the camera's IR LED, not the remote control.

---

## FM radio: there is no separate chip

The FM radio on this board is the **WCN3990**, the same chip that does the
Bluetooth and the Wi-Fi. The Android FM HAL reaches it through the
**Bluetooth HCI transport**:

```
vendor.qti.hardware.fm@1.0-impl.so:
    HIDL_FETCH_IFmHci
    sendDataToController: data_handler is null
    FM died sending fmOff command to SoC
    Unable to call hciEventReceived()
```

The FM HAL is a thin HIDL client that hands packets to the Bluetooth HAL
(`android.hardware.bluetooth@1.0-impl-qti.so`) and receives events back. The
FM commands travel over HCI to the WCN, which does the actual RF.

> 📌 **The device tree says the same thing.** The sound card of the stock
> firmware carries `qcom,wcn-btfm = <0x01>`, which is the WCN's Bluetooth
> FM transport. That is the FM, in the device tree, next to the sound card
> it belongs to.
>
> See [`upstream-parallel-work.md`](upstream-parallel-work.md).

The build properties say which chip and that FM is on:

```
vendor.qcom.bluetooth.soc=cherokee
vendor.audio.feature.fm.enable=true
```

**"Cherokee" is the WCN3990.** The same string is what
`fm_qsoc_patches` matches on to choose the FM calibration.

### The FM firmware and calibration

The FM stack needs two things loaded into the chip: the **firmware** and the
**calibration patches**. Both are done by
`vendor/bin/fm_qsoc_patches`, started by `vendor/bin/init.qti.fm.sh`:

```
service vendor.fm /vendor/bin/init.qti.fm.sh
    class late_start
    user system
    group system
    disabled
    oneshot
```

The script reads the chip from the build property and then:

```
case $mode in
  "normal")
        echo 1 > /sys/module/radio_iris_transport/parameters/fmsmd_set
        /vendor/bin/fm_qsoc_patches $version 0
```

`radio_iris_transport` is the Qualcomm transport that carries the FM commands
into the WCN. The `fmsmd_set` parameter has to be set to 1, or the chip will
not accept them.

`fm_qsoc_patches` does three things:

1. **Reads the chip type** from `vendor.qcom.bluetooth.soc`, and refuses to
   continue if it does not recognise it:

   ```
   fm_qsoc_patches: get_bt_soc_type
   FmQSocPatches_WritePatches: Bahama B1
   FmQSocPatches_WritePatches: WCN2243 2.0: count: %d
   FmQSocPatches_WritePatches: unknown chip version
   %s: Failed to get soc type
   ```

   The chips it knows are **Bahama B1**, **WCN2243 1.0**, **WCN2243 2.0**
   and **Cherokee**. Anything else is refused:

   ```
   fm_qsoc_patches: get_bt_soc_type
   FmQSocPatches_WritePatches: Bahama B1
   FmQSocPatches_WritePatches: Patches Written for WCN2243 1.0: count: %d
   FmQSocPatches_WritePatches: Patches Written for WCN2243 2.0: count: %d
   FmQSocPatches_WritePatches: unknown chip version
   %s: Failed to get soc type
   ```

2. **Downloads the patches over QMI**, with `qmi_client_init` and
   `nas_get_service_object_internal_v01` — so the patches come from the
   modem:

   ```
   Patch [%d] started downloading
   Patch [%d] download success
   Patch [%d] download failed
   ```

3. **Writes the calibration to the codec over I²C**, and configures the
   notch filters and the spur frequency:

   ```
   opened FM i2c device node : %s
   /dev/i2c-1
   /dev/i2c-2
   /dev/i2c-4
   Configuring DAC : Success
   FmDacInit
   FmDacCodecAnalogConfig
   FmDacCodecDigitalConfig
   Reset FM Dac : Failed
   Resetting the notchfilters
   HPNOTCHREG
   Configuring the SPUR FREQUENCY Data...
   spurFrequencyFilter: SPUR FREQ TABLE Size(%d) configured successfully
   ```

   The DAC is the part of the WCN that does the FM modulation, and its
   calibration is the notch filter and the spur frequency table. The three
   I²C nodes are the ones the vendor's own board has; which of them the
   calibration actually lands on depends on the chip.

### RDS

`vendor/bin/fmconfig` is the configuration tool. It speaks the FM HCI
commands, and it implements RDS:

```
RDS Search Complete. Status = 0x%x
RdsOptions    :%x
Search RDS in Progress. RDS Mode = %d
RDS decoder not synchronized
RDS decoder synchronized
RDS group req failed
EnableReceiver Failed to set RDS std = %d
EnableReceiver Failed to set RDS group  = %d
```

The RDS **group** is requested, and the result arrives asynchronously — the
same "the response tells you nothing" pattern as the QMI LOC constellation
messages, and for the same reason: it is an indication, not a response.

### The peripheral tuner (Wigig) is not this board

`vendor.qti.hardware.wigig.netperftuner@1.0.so` and the `libwigig_*`
libraries implement FM on a **Wi-Fi peripheral** — an M.2 module with its own
tuner, connected over PCIe. The name means "Wireless Gigabit Internet
Solution", and it is for the "bring your own hotspot" accessories. It has
nothing to do with the phone's own FM.

---

## What this means for the port

### Infrared

| | State | What would be needed |
|---|---|---|
| Camera IR LED + IR-cut filter | described in the DT, **driver not in mainline** | the `qcom,camera-ir-led` driver and the IR-cut filter logic. The filter is two GPIOs on the PM6150, so it is a GPIO driver plus a camera hook |
| Remote control emitter | HAL present, **nothing describes or enables it** | first confirm the part exists. If it does: the `ir-spi-led` mainline driver (it is `CONFIG_IR_SPI=m` already) plus a device tree node |

The kernel configuration already has the framework:

```
CONFIG_MEDIA_SUPPORT=m
CONFIG_LIRC=y
CONFIG_IR_SPI=m
CONFIG_IR_GPIO_CIR=m
```

So the mainline side is mostly a device tree node and a driver for the SPI
LED. The `ir-spi-led` driver in mainline is the generic Samsung one: 38 kHz
by default, `led-active-low` and `duty-cycle` as properties, and a
`irda_regulator` supply. If the part is a plain SPI LED, it works as it is.

### FM radio

| | State | What would be needed |
|---|---|---|
| FM on the WCN3990 | **the whole stack is missing from mainline** | the `radio_iris_transport` driver, the `fmsmd_set` handling, the HCI FM command transport, the patch download over QMI, and the DAC calibration over I²C |
| FM on a peripheral (Wigig) | not this board | — |

The FM radio is a **large** piece of work, and the hardest part is not the
driver: it is the patch and calibration download, which needs the modem
(QMI) and the codec (I²C) to be involved at boot, in the right order, with
the right chip type.

> ⚠️ **The FM calibration and patches are per-device and per-chip.** They come
> from the modem over QMI and are written to the codec over I²C. They are not
> in the factory firmware as files, and they are not redistributable.

---

## Open questions

- **Does this board physically have the IR remote control emitter?** The
  firmware gives every sign that it does not, but the firmware is not the
  hardware. This needs eyes on the device.
- **Which SPI bus and pins would the emitter use?** The HAL says
  `/dev/spidev0.1` — bus 0, chip select 1. On this SoC, `spi0` is the
  QUPv3 SE4 at `0xa80000`, with its pins on GPIO 20–23 (`function = "qup10"`).
  If the emitter is populated, that is almost certainly it.
- **What is the FM chip's own firmware version?** `init.qti.fm.sh` has
  `version=199217` and passes it to `fm_qsoc_patches` as the chip version, but
  the argument is not the version of the FM firmware — it selects the patch
  set. The actual FM firmware is in the modem.
- **Does the modem of this board even have the FM image?** The patches are
  downloaded over QMI; whether the modem carries an FM image for the
  Cherokee is not established from the firmware.

## Reproducing this analysis

```sh
rea/04-tools/ir_fm_config.py \
    android/firmware-update/dtbo.img \
    --vendor android/extracted/rootfs/vendor
```

The device tree side needs `dtc`; the vendor side needs `strings`.
