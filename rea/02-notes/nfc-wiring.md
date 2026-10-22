# The NFC: wiring the NXP PN553 to the mainline

**What**: the NFC controller of this board, and what it takes to bring it
up on the mainline.

**Status**: the mainline driver exists, a **reference board on the same
SoC family does it in the mainline**, and the factory device tree has
the addresses and the pin assignments. What is missing is a device tree
node and an enabled I²C bus.

This is the same kind of work as the
[FSA4480](usb-c-audio-fsa4480.md): no new driver, just wiring.

---

## The chip

The NFC is an **NXP PN553** (the "NQX NCI" family), on an I²C bus at
address **0x28**, driven through the NXP NCI protocol.

The upstream project's wiki names it: *"NQX NCI NXP55303 (PN553 type)"*.

The factory firmware's own identification differs — the analysis here
found a **PN557**, with the PN5180 radio configuration, and the
firmware in `libpn557_fw.so`. The PN557 is the same family, a later
revision. The mainline driver's compatible list covers both:

```c
{ .compatible = "nxp,pn553" },
{ .compatible = "nxp,nxp-nci-i2c" },
```

and the reference board in the mainline lists **both**, so the driver
picks the right one per board.

> 📌 The chip identity does not have to be settled to wire it up: the
> family-level `"nxp,nxp-nci-i2c"` is enough, and the factory tree's
> `"qcom,nq-nci"` is the downstream wrapper's name for the same thing.

---

## The factory device tree

From the stock firmware, published by the upstream project in
`sm7150-mainline/downstream-fdt`:

```dts
nq@28 {
    compatible = "qcom,nq-nci";
    reg = <0x28>;
    qcom,nq-irq = <0x178 0x25 0x00>;
    qcom,nq-ven = <0x178 0x0c 0x00>;
    qcom,nq-firm = <0x178 0x24 0x00>;
    qcom,nq-clkreq = <0x178 0x1f 0x00>;
    qcom,nq-esepwr = <0x178 0x16 0x00>;
    interrupt-parent = <0x178>;
    interrupts = <0x25 0x00>;
    interrupt-names = "nfc_irq";
    pinctrl-names = "nfc_active", "nfc_suspend";
    pinctrl-0 = <0x3a3 0x3a5 0x3a7>;
    pinctrl-1 = <0x3a4 0x3a6 0x3a8>;
};
```

The five `qcom,nq-*` properties are **PMI registers**, and they are the
downstream driver's way of doing it. The mainline driver does not use
them: it wants GPIOs and a plain interrupt.

**The bus.** The parent is `qupv3_se2_i2c`, at `0x888000` — which in the
mainline SM7150 device tree is **`i2c2`**. It is `status = "disabled"`
there, and no patch in this port enables it.

**The pins.** The three pinctrl states give the assignments:

| Factory state | GPIOs | What it is |
|---|---|---|
| `nfc_int_active` / `_suspend` | **37** | the interrupt |
| `nfc_enable_active` / `_suspend` | **12**, **36** | the enable |
| `nfc_clk_req_active` / `_suspend` | **31** | the clock request |

The interrupt is GPIO 37, presented to the downstream driver as a PMI
register. The mainline driver wants it as a **TLMM** interrupt, and
GPIO 37 is already configured as the NFC's interrupt pin — so the same
pin, a different description of it.

---

## The mainline reference

The mainline has a board on the same SoC family with exactly this
topology: the **Nothing Phone (1)**, `sm7325-nothing-spacewar.dts`.
Same QUPv3 SE2 I²C, same address, same kind of pins.

```dts
&i2c2 {
	clock-frequency = <100000>;
	status = "okay";

	nfc@28 {
		compatible = "nxp,pn553",
			     "nxp,nxp-nci-i2c";
		reg = <0x28>;

		interrupt-parent = <&tlmm>;
		interrupts = <41 IRQ_TYPE_EDGE_RISING>;

		enable-gpios = <&tlmm 38 GPIO_ACTIVE_HIGH>;
		firmware-gpios = <&tlmm 40 GPIO_ACTIVE_HIGH>;

		pinctrl-0 = <&nfc_en>,
			    <&nfc_clk_req>,
			    <&nfc_dwl_req>,
			    <&nfc_int_req>;
		pinctrl-names = "default";
	};
};
```

The two boards side by side:

| | Nothing Phone (1) | This board |
|---|---|---|
| Bus | `i2c2` | `i2c2` — the same |
| Address | `0x28` | `0x28` — the same |
| Compatible | `nxp,pn553`, `nxp,nxp-nci-i2c` | `nxp,nxp-nci-i2c` |
| Enable | GPIO 38 | GPIO 12 and/or 36 |
| Firmware (download) | GPIO 40 | **not identified** |
| Clock request | GPIO 39 | GPIO 31 |
| Interrupt | GPIO 41 | GPIO 37 |

---

## The recipe

### 1. The bus

In the board's device tree:

```dts
&i2c2 {
	clock-frequency = <100000>;
	status = "okay";
};
```

The frequency comes from the reference board; the factory tree does not
say. The NFC bus is slow — 100 kHz is what the reference uses.

### 2. The pins

The factory's pinctrl states, in the board's pinctrl block:

```dts
nfc_int_active: nfc_int_active {
	mux {
		pins = "gpio37";
		function = "gpio";
	};

	config {
		pins = "gpio37";
		drive-strength = <0x02>;
		bias-pull-up;
	};
};

nfc_enable_active: nfc_enable_active {
	mux {
		pins = "gpio12", "gpio36";
		function = "gpio";
	};

	config {
		pins = "gpio12", "gpio36";
		drive-strength = <0x02>;
		bias-pull-up;
	};
};

nfc_clk_req_active: nfc_clk_req_active {
	mux {
		pins = "gpio31";
		function = "gpio";
	};

	config {
		pins = "gpio31";
		drive-strength = <0x02>;
		bias-pull-up;
	};
};
```

The mainline driver wants a single `default` state, and the factory's
active/suspend pair is a downstream convention. The **active** states
are the ones to use.

### 3. The node

```dts
&i2c2 {
	clock-frequency = <100000>;
	status = "okay";

	nfc@28 {
		compatible = "nxp,pn553",
			     "nxp,nxp-nci-i2c";
		reg = <0x28>;

		interrupt-parent = <&tlmm>;
		interrupts = <37 IRQ_TYPE_EDGE_RISING>;

		enable-gpios = <&tlmm 12 GPIO_ACTIVE_HIGH>;
		firmware-gpios = <&tlmm 36 GPIO_ACTIVE_HIGH>;

		pinctrl-0 = <&nfc_int_active>,
			    <&nfc_enable_active>,
			    <&nfc_clk_req_active>;
		pinctrl-names = "default";
	};
};
```

> ⚠️ **The GPIO assignment is a guess, and it is the one thing here that
> has to be confirmed on the device.** The factory tree groups GPIO 12
> and GPIO 36 under "enable" without saying which is which, and it has
> no separate "download" or "firmware" pin — the reference board has one
> at GPIO 40, and the spacewar's `nfc_dwl_req`.
>
> Two candidates, and the way to tell them apart is the behaviour:
>
> - the **enable** pin is the one that has to be high for the chip to
>   answer at all;
> - the **firmware** pin is the one the driver pulses to put the chip
>   into the bootloader, and the chip only pulls the interrupt low when
>   it is in that mode.
>
> The driver can be told to use a different pin, so the first attempt
> can try one and swap if the probe fails.

---

## What the driver needs, and what it does not

From `drivers/nfc/nxp-nci/i2c.c`:

| | |
|---|---|
| `enable` GPIO | **required** — `devm_gpiod_get(dev, "enable", GPIOD_OUT_LOW)` |
| `firmware` GPIO | optional — `devm_gpiod_get_optional(dev, "firmware", GPIOD_OUT_LOW)` |
| the interrupt | through the I²C client, as usual |
| `data-lanes` | not applicable — that is the FSA4480's |

The driver **reads the interrupt type from the DT** when it is set, and
falls back to `IRQF_TRIGGER_RISING` when it is not:

```c
/* On non-ACPI systems (e.g. Device Tree), prefer the firmware-... */
irqflags = IRQF_TRIGGER_RISING;
if (!of_property_read_bool(dev->of_node, "interrupt-parent"))   /* roughly */
        irqflags = irq_get_trigger_type(client->irq);
if (!irqflags)
        irqflags = IRQF_TRIGGER_RISING;
```

So an explicit `interrupts = <37 IRQ_TYPE_EDGE_RISING>;` is the right
thing to write, and the reference board writes exactly that.

---

## How to verify

```sh
# o nó foi criado e o probe passou?
dmesg | grep -iE 'nxp|nfc|pn553'
ls -l /sys/bus/i2c/devices/i2c-*/name | grep -i nxp

# o chip responde no endereço?
i2cdetect -y <bus>       # o 0x28 tem de aparecer

# a interface aparece?
ls /sys/class/nfc/
rfkill list
```

Then the real test: bring a card or a tag near the top of the phone and
see if the NFC daemon reports it.

> ⚠️ **One thing to watch.** The NFC is on the **top** of the phone, next
> to the SIM. On the factory firmware it shares a bus with things that
> are also powered from the same rail, and the chip is sensitive to the
> order in which the rails come up. If the probe fails with a timeout
> rather than with "no chip", the enable pin's polarity or its timing is
> the first thing to look at.

---

## The open questions

1. **Which of GPIO 12 and GPIO 36 is the enable, and which is the
   firmware pin?** The factory tree groups them; the reference board has
   them separate. A guess is in the recipe above, and the device is the
   arbiter.
2. **Is there a separate download pin at all?** The factory's NFC
   pinctrl has only three states — int, enable, clock request. The
   spacewar has four. If this board has no download pin, the
   `firmware-gpios` line is simply left out.
3. **Which chip is it really?** The firmware says PN557, the upstream
   wiki says PN553. The mainline driver supports both, and the
   `nxp,pn553` compatible is the one that carries the chip-specific
   behaviour. Listing both, as the reference board does, is the safe
   answer — but it is a question that only the hardware settles.
4. **The interrupt polarity.** The reference board uses
   `IRQ_TYPE_EDGE_RISING`; the factory tree does not say. The driver's
   fallback is `IRQF_TRIGGER_RISING`, which is close enough to try.

---

## Related

- [`upstream-parallel-work.md`](upstream-parallel-work.md) — the survey of the other work
- [`nfc-pn557.md`](nfc-pn557.md) — the firmware analysis: the chip, its RF calibration and its firmware
- [`port-vs-factory.md`](port-vs-factory.md) — the comparison of the trees
- The roadmap, §1.3, task **S1**
