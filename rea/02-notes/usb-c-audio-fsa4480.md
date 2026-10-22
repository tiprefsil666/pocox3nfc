# The USB-C analogue audio: the FSA4480

**What**: the chip that switches the USB-C port between USB and an analogue
audio headset, and what it takes to wire it up on this board.

**Status**: the mainline driver exists, the kernel configuration already
enables it, and the bus is already enabled. **Only the device tree is
missing.** This is the cheapest remaining win on the board.

---

## The chip

The **FSA4480** is an ON Semiconductor part that sits next to a USB-C
connector and does two things:

- it **muxes the sideband (SBU) lines**, so that a USB-C port can carry
  DisplayPort Alt Mode or the audio accessory mode;
- it **switches the analogue audio** — left, right, microphone and ground —
  when a USB-C audio adapter is plugged in.

The mainline driver is
[`drivers/usb/typec/mux/fsa4480.c`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/usb/typec/mux/fsa4480.c),
by Linaro, and it is a **Type-C mux**: it registers with the Type-C
framework and is driven by the port's controller.

> 📌 The upstream project lists this component as **"N"** in its
> component table, with the note *"Supported in this driver"* pointing at
> the mainline `fsa4480.c`. So it is **not wired**, not **missing a
> driver**. The driver was there first; nobody connected it.
>
> See [`upstream-parallel-work.md`](upstream-parallel-work.md).

---

## What the factory device tree says

The stock firmware describes the chip in full. This is the
`sm7150-mainline/downstream-fdt` tree, `fdt-surya`:

```dts
fsa4480: fsa4480@43 {
    compatible = "qcom,fsa4480-i2c";
    reg = <0x43>;
    pinctrl-names = "default";
    pinctrl-0 = <&fsa_usbc_ana_en>;
    phandle = <0x29e>;
};
```

**The bus.** The parent is `qupv3_se9_i2c`, at `0xa8c000` — which in the
mainline SM7150 device tree is **`i2c9`**. And `i2c9` is *already enabled*
on this board: patch `0042` turns it on for the WL2866D camera regulator.
So the bus is there, the clock and the pin group are configured, and the
FSA4480 is simply a second device on it.

**The pin.** The pinctrl state is `fsa_usbc_ana_en`, on **GPIO 42**:

```dts
fsa_usbc_ana_en: fsa_usbc_ana_en {
    mux {
        pins = "gpio42";
        function = "gpio";
    };

    config {
        pins = "gpio42";
        drive-strength = <0x02>;
        bias-disable;
        output-low;
    };
};
```

A plain GPIO, driven low. That is the analogue-audio enable line, and
the factory keeps it low — the chip is idle until an audio adapter
arrives.

**The sound card.** The chip is also referenced from the sound card, by
handle:

```dts
sound {
    ...
    fsa4480-i2c-handle = <0x29e>;
    qcom,model = "sm6150-wcd9375-snd-card";
    ...
};
```

The downstream audio driver uses this to find the chip when the USB-C
audio accessory is detected. **The mainline driver does not need it**: it
is a Type-C mux, and the Type-C framework tells it when to switch. The
`fsa4480-i2c-handle` is therefore *not* part of the recipe below — it is
there so that the downstream tree can be read without confusion.

---

## What the mainline driver wants

From the driver source:

| | |
|---|---|
| `compatible` | **`"fcs,fsa4480"`** — the factory says `"qcom,fsa4480-i2c"`, and the mainline driver does not match that |
| `reg` | the I²C address, `0x43` |
| `vcc-supply` | **optional** — `devm_regulator_get_enable_optional(dev, "vcc")` |
| `data-lanes` | **optional**, on the graph endpoint: two values, and the driver rejects anything but the normal or the inverted mapping |
| an interrupt | **not used** — the driver is polled through the Type-C framework |

The node must be reachable from the Type-C port, through the **graph**:
the connector's SBU endpoint points at the chip's endpoint, and the
chip's endpoint points back.

---

## The recipe

### 1. The pin group

In the board's device tree, next to the other pinctrl groups:

```dts
fsa_usbc_ana_en: fsa_usbc_ana_en {
    mux {
        pins = "gpio42";
        function = "gpio";
    };

    config {
        pins = "gpio42";
        drive-strength = <0x02>;
        bias-disable;
        output-low;
    };
};
```

### 2. The chip, on the bus that is already there

In the `&i2c9` block that patch `0042` already enables:

```dts
fsa4480: fsa4480@43 {
    compatible = "fcs,fsa4480";
    reg = <0x43>;

    pinctrl-names = "default";
    pinctrl-0 = <&fsa_usbc_ana_en>;

    mode-switch;
    orientation-switch;

    port {
        fsa4480_sbu_mux: endpoint {
            remote-endpoint = <&pm6150_sbu>;
        };
    };
};
```

### 3. The SBU endpoint on the connector

The mainline SM7150 device tree has the Type-C port under `&pm6150_typec`
with a `usb-c-connector` that has **one** port — the USB data one. The
SBU endpoint has to be added:

```dts
&pm6150_typec {
    vdd-vbus-supply = <&pm6150_vbus>;
    vdd-pdphy-supply = <&vdda_usb_hs_3p1>;
    status = "okay";

    connector {
        compatible = "usb-c-connector";

        power-role = "source";
        data-role = "dual";
        self-powered;

        source-pdos = <...>;

        ports {
            #address-cells = <1>;
            #size-cells = <0>;

            port@0 {
                reg = <0>;
                pm6150_role_switch_in: endpoint {
                    remote-endpoint = <&usb_1_dwc3_hs>;
                };
            };

            port@2 {
                reg = <2>;

                pm6150_sbu: endpoint {
                    remote-endpoint = <&fsa4480_sbu_mux>;
                };
            };
        };
    };
};
```

`port@2` is the SBU port, and `reg = <2>` is what the reference board
uses. The port number is not the SBU's own number in the hardware — it is
the index in the connector's `ports` array, and the reference
implementation puts the SBU at index 2.

### The reference board

The mainline has a working example, in
[`arch/arm64/boot/dts/qcom/sm8350-hdk.dts`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/arch/arm64/boot/dts/qcom/sm8350-hdk.dts):

```dts
typec-mux@42 {
    compatible = "fcs,fsa4480";
    reg = <0x42>;

    interrupts-extended = <&tlmm 2 IRQ_TYPE_LEVEL_LOW>;

    vcc-supply = <&vreg_bob>;
    mode-switch;
    orientation-switch;

    port {
        fsa4480_sbu_mux: endpoint {
            remote-endpoint = <&pmic_glink_sbu>;
        };
    };
};
```

and, on the connector:

```dts
port@2 {
    reg = <2>;

    pmic_glink_sbu: endpoint {
        remote-endpoint = <&fsa4480_sbu_mux>;
    };
};
```

The `interrupts-extended` there is for the board's own reasons; the
driver does not use an interrupt.

---

## Why the audio, and not just the USB

With the FSA4480 wired, plugging a USB-C headset into the phone switches
the port's analogue audio lines over to the headset. Two things follow:

1. **The headset is audible.** On this board the headphone amplifier is
   the WCD9375's `HPHL_OUT`/`HPHR_OUT` pair, and the USB-C audio adapter
   brings its own microphone back over the same lines. The switch is what
   connects them.
2. **The port keeps charging.** The `source-pdos` already declare a
   5 V/3 A source, so the phone can charge through the same adapter.

Without the chip, a USB-C headset is either silent or the phone stops
charging — which is the symptom to look for.

---

## How to verify

```sh
# o nó foi criado?
dmesg | grep -i fsa4480
# o probe passou?
ls -l /sys/bus/i2c/devices/i2c-*/name | grep -i fsa
# o chip responde?
i2cdetect -y <bus>          # o endereço 0x43 tem de aparecer
```

Where `<bus>` is the number of `i2c9` — find it with
`ls -l /dev/i2c-*` and match the `i2c9` alias, or read it from the
`i2c9` node in `/sys/bus/i2c/devices/`.

Then:

```sh
# com um auscultador USB-C ligado, o mixer tem de mostrar a rota nova
alsaucm -c 0 list _verbs | grep -i 'usb\|headset'
aplay -l | grep -i usb
```

And the **T7** test of the battery — the Bluetooth offload — has a
USB-C sibling worth adding to `build/tests/`: plug a USB-C headset, make
a call, and check that the audio goes to the headset and not to the
speaker.

---

## The open question

**The `data-lanes` property.** The driver reads it from the graph
endpoint, and accepts only two mappings — the normal one and the inverted
one. The factory tree does not have the property at all, so the driver
will use the default. Whether the default is right for this board is
**not established**: it depends on how the SBU lines are routed on the
PCB, and only a USB-C display adapter would show it.

The property is optional, so the first attempt should leave it out, and
the board should be tested with a USB-C audio adapter first — that is the
common case, and it does not touch the SBU lines at all.

---

## Reproducing this analysis

```sh
# a device tree da fábrica
rea/04-tools/ir_fm_config.py android/firmware-update/dtbo.img

# e a do upstream, que é a mesma coisa em formato limpo
git clone --depth=1 https://github.com/sm7150-mainline/downstream-fdt
dtc -I dtb -O dts downstream-fdt/fdt-surya
```

## Related

- [`upstream-parallel-work.md`](upstream-parallel-work.md) — the survey of the other work
- [`audio-mixer-paths.md`](audio-mixer-paths.md) — the vendor's audio routes
- The roadmap, §1.3, task **S10**
