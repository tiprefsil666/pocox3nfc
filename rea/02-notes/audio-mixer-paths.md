# The vendor audio configuration: mixer paths, the WCD9375 and the TAS2562

**Source**: MIUI `V12.0.6.0.QJGMIXM` (Android 10, `surya`), the factory firmware.
**Tools**: [`../04-tools/parse_mixer_paths.py`](../04-tools/parse_mixer_paths.py)

> Static analysis only. Nothing was run on hardware.

## Where the audio configuration lives

| File | What it holds |
|---|---|
| `vendor/etc/mixer_paths_wcd9375.xml` | the routes: playback, capture, voice, echo reference, low latency, deep buffer |
| `vendor/etc/mixer_paths_tavil.xml` | the same, for the "tavil" tuning |
| `vendor/etc/mixer_paths_idp.xml` | the same, for the "idp" (in-house product) tuning |
| `vendor/etc/mixer_paths_qrd.xml` | the same, for the reference design |
| `vendor/etc/audio_platform_info*.xml` | the platform's port and channel counts |
| `vendor/etc/audio_policy_configuration.xml` | which route each stream type uses |
| `vendor/etc/acdbdata/` | the ACDB, the calibration the DSP loads |
| `vendor/lib64/hw/audio.primary.sm6150.so` | the primary HAL: it parses the above |
| `vendor/lib64/libaudioparsers.so` | the parser of the mixer paths |

The HAL is named for the **sm6150**, not the surya: the board reuses the
Snapdragon 615-era audio primary, with a WCD9375 codec and TAS2562
amplifiers.

## The structure of a mixer paths file

The file is a tree. A route either carries controls, or refers to other
routes by name:

```xml
<path name="voice-rec-mic">
    <path name="handset-mic" />
</path>

<path name="speaker">
    <ctl name="TAS256X RX MODE RIGHT" value="Speaker" />
    <ctl name="TAS256X ASI1 SEL RIGHT" value="Right" />
    <ctl name="TAS256X ASI1 SEL LEFT"  value="Left" />
    <ctl name="TAS256X ASI Right Switch" value="1" />
    <ctl name="TAS256X ASI Left Switch"  value="1" />
</path>
```

A control is a write to a mixer control, named, with an optional id and a
value. The names are the ASoC control names the driver exposes, so they are
the direct link between the vendor's configuration and the mainline
driver's controls.

The tool flattens the tree, so a route shows the controls that actually
apply to it:

```sh
rea/04-tools/parse_mixer_paths.py \
    rea/00-inputs/audio-config/mixer_paths_wcd9375.xml

rea/04-tools/parse_mixer_paths.py \
    rea/00-inputs/audio-config/mixer_paths_wcd9375.xml --route voice-rec-mic
```

`mixer_paths_wcd9375.xml` has **607 routes**.

## The four tunings

There are four `mixer_paths` files, and they are **not** interchangeable.
They are four tunings of the same routes, and they differ in more than
values — they differ in the control names themselves:

| File | The speaker route writes |
|---|---|
| `mixer_paths_wcd9375.xml` | `TAS256X RX MODE RIGHT`, `TAS256X ASI1 SEL RIGHT`, `TAS256X ASI Right Switch` — six controls in all |
| `mixer_paths_idp.xml` | `Amp Output Level = 5`, `TAS256X Left Speaker Switch = On`, `TAS256X Right Speaker Switch = On` |
| `mixer_paths_qrd.xml` | `WSA_CDC_DMA_RX_0 Channels`, `WSA RX0 MUX`, `SpkrLeft COMP Switch`, `SpkrLeft BOOST Switch`, `SpkrLeft VISENSE Switch` — the WSA amplifier, not the TAS2562 |
| `mixer_paths_tavil.xml` | `SLIM RX0 MUX = AIF1_PB`, `SLIM_0_RX Channels = Two` — the plain SLIMbus path, no amplifier controls at all |

That last row is the important one: `mixer_paths_tavil.xml` has **no
amplifier controls at all**, and `mixer_paths_qrd.xml` drives a WSA
amplifier that this board does not have. The board with the TAS2562 is the
one that uses `mixer_paths_wcd9375.xml` or `mixer_paths_idp.xml`.

Which one the HAL loads is decided at run time; the names suggest `tavil`
is the tuning that ships with this SoC generation and `idp` is the
in-house product one.

> ✅ **Resolved: it is `mixer_paths_wcd9375.xml`.**
>
> The device tree of the stock firmware, published by the upstream project
> in `sm7150-mainline/downstream-fdt`, gives the sound card's model:
>
> ```
> sm6150_snd: sound {
>     compatible = "qcom,sm6150-asoc-snd";
>     qcom,model = "sm6150-wcd9375-snd-card";
> ```
>
> The HAL picks the file by that name: `sm6150-<variant>-snd-card` →
> `mixer_paths_<variant>.xml`. The variants in the HAL's strings line up
> exactly with the four files that exist — `wcd9375`, `qrd`, `tavil`, `idp`
> and `wcd9375qrd`.
>
> So the board is a **`wcd9375`** one, and `mixer_paths_idp.xml` belongs
> to a different board — even though the device tree's top-level `model`
> is `"IDP"`, which is a red herring: it is the board's name, not the
> sound card's.
>
> The same tree confirms the NFC is the NXP NCI
> (`compatible = "qcom,nq-nci"`) and that the FM is a WCN feature
> (`qcom,wcn-btfm = <0x01>` on the sound card).
>
> See [`upstream-parallel-work.md`](upstream-parallel-work.md).

## The speakers

The `speaker` route of `mixer_paths_wcd9375.xml` writes the TAS2562
amplifiers directly:

```
TERT_MI2S_RX Channels      = Two
TAS256X RX MODE RIGHT      = Speaker
TAS256X ASI1 SEL RIGHT     = Right
TAS256X ASI1 SEL LEFT      = Left
TAS256X ASI Right Switch   = 1
TAS256X ASI Left Switch    = 1
```

Six controls, and no volume: the volume of the speakers is set by the
**DSP**, through the ACDB, not by the ASoC controls. That is why the overlay
needed its own `tas2562` driver patches (0013 to 0016, 0022 to 0027) and
why the notes on `audio.es.md` talk about writing the amplifiers' registers
directly.

`TAS256X RX MODE RIGHT = Speaker` selects the amplifier's mode; `ASI1 SEL
LEFT`/`RIGHT` select which ASI each channel is fed from, which is how the
stereo routing is set up. `TERT_MI2S_RX Channels = Two` says the tertiary
MI2S carries two channels, which is the DSP's link to the amplifiers.

## The microphones

The capture side is a set of routes over the WCD9375's two ADCs and its
digital microphones. The route names tell the whole story:

| Route family | What it is |
|---|---|
| `handset-mic`, `voice-rec-mic`, `voice-speaker-mic` | the main microphone, in the different modes |
| `handset-dmic-endfire`, `voice-dmic-ef`, `voice-rec-dmic-ef` | the endfire digital microphone |
| `dmic1` .. `dmic4`, `dmic-broadside`, `dmic-endfire` | the raw digital microphone channels |
| `amic1` .. `amic3` | the analog microphones |
| `quad-mic`, `three-mic`, `main-mic`, `top-mic`, `speaker-mic` | the multi-microphone arrays |
| `headset-mic`, `usb-headset-mic`, `bt-sco-mic` | the external microphones |
| `camcorder-mic`, `camcorder-dmic` | the camera route's microphone |

The `voice-rec-mic` route, flattened, shows the whole signal path:

```
TX_CDC_DMA_TX_3 Channels     = Two
TX DEC0 MUX                  = SWR_MIC
TX SMIC MUX0                 = ADC2
TX_AIF1_CAP Mixer DEC0       = 1
ADC1_MIXER Switch            = 1
TX DEC1 MUX                  = SWR_MIC
TX SMIC MUX1                 = ADC0
TX_AIF1_CAP Mixer DEC1       = 1
ADC2_MIXER Switch            = 1
ADC2 MUX                     = INP3
IIR0 INP0 MUX                = DEC0
```

Two microphones, `ADC0` and `ADC2`, both routed to the TX decimators
`DEC0` and `DEC1`, in `SWR_MIC` mode. `SWR_MIC` is the microphone mode that
the WCD9375 uses for its digital microphones.

The single-microphone routes use `ADC1` and `ADC2`; the digital microphone
routes use `dmic1` and `dmic2`. The board therefore has both an analog
microphone path and a digital one, and the routes exist for both.

## The echo reference

The `echo-reference*` routes are the loopback the voice call's echo
canceller uses. There is one per output:

```
echo-reference handset
echo-reference speaker
echo-reference headphones
echo-reference headset
echo-reference display-port
echo-reference-voip speaker
echo-reference-voip headphones
echo-reference-voip usb-headphones
```

The `-voip` variants are for the VoIP path. The `handset` one is the
earpiece. Each is two controls, and they are the routes the overlay's
`q6voice` and `hexagonrpcd` work depends on: the echo canceller needs the
reference of the *actual* output device, which is why the notes record
switching the output and needing a different reference.

## The ACDB

`vendor/etc/acdbdata/` holds the ACDB, the calibration the audio DSP
loads:

```
adsp_avs_config.acdb
IDP/
QRD/
```

The `.acdb` files are binary. `libacdbloader.so` and `libacdbrtac.so` are
the loaders, and the ACDB is what carries the **voice calibration** the
echo canceller needs — which the overlay's notes are explicit about not
being redistributable, and which the `hexagonrpcd` patch has to serve to
the ADSP.

> The ACDB format was not decoded here. It is a Qualcomm format with a
> published structure in the ACDB loader, and the calibration it carries
> is per-device.

## What this means for the port

1. **The mainline WCD9375 driver already covers most of the controls.**
   The names in the mixer paths are the ASoC control names, and the
   mainline driver exposes them. What mainline does not have is the
   vendor's *routing table*: which ADC goes where for each capture mode,
   and which output the echo reference follows.
2. **The amplifiers need a driver of their own.** The TAS2562 is not an
   ASoC codec; the overlay's patches 0013 to 0016 and 0022 to 0027 are
   that driver. The mixer paths show only six controls for the speakers,
   which is what makes the amplifier special.
3. **The echo reference has to follow the output.** The `echo-reference*`
   routes are the list of outputs the canceller can use. Switching from
   the speaker to the earpiece mid-call changes which reference applies.
   This is the same problem the overlay's `q6voice` patches solve.
4. **The microphone routing is a table, not a driver.** The board has both
   analog and digital microphones and the routes choose between them; the
   hardware does not decide. The mainline driver needs the vendor's table
   transcribed.

## Open questions

- ~~Which of the four `mixer_paths_*.xml` files this board actually
  loads.~~ **Answered: `mixer_paths_wcd9375.xml`**, from the sound card's
  `qcom,model` in the upstream device tree — see §"The four tunings".
- The ACDB format, and which of its tables carry the voice calibration.
- The `TERT_MI2S_RX Channels = Two` control on the speaker route: the
  tertiary MI2S is the DSP's link to the amplifiers, and the mainline
  driver's handling of it is not established.

> 📌 **The upstream project already has an audio configuration.** The
> `sm7150-mainline/alsa-ucm-conf` repository, packaged in pmaports as
> `alsa-ucm-conf-qcom-sm7150` and pulled in by the `device-qcom-sm7150`
> package, carries the UCM configuration for this board.
>
> Its surya profile is 18 lines — a mono speaker and nothing else. This
> port's is 172, with the stereo split, the amplifier gains and the
> microphone capture.
>
> ⚠️ **They collide.** The upstream package installs
> `conf.d/sm8250/POCO X3.conf` — **with a space, not a hyphen** — and
> puts the profile in `Xiaomi/surya/HiFi.conf`. This port's
> `install-on-device.sh` writes `HiFi.conf`, `POCO-X3.conf` and
> `VoiceCall.conf` into `conf.d/sm8250/`. On a current build that means
> two "HiFi" use cases, one of them the simple upstream one, and a
> "Voice Call" use case pointing at a file that was never installed.
>
> This has to be reconciled before the next flash. See §4.5 of the
> roadmap.

## Reproducing this analysis

```sh
rea/04-tools/parse_mixer_paths.py \
    rea/00-inputs/audio-config/mixer_paths_wcd9375.xml

rea/04-tools/parse_mixer_paths.py \
    rea/00-inputs/audio-config/mixer_paths_wcd9375.xml --route speaker

rea/04-tools/audio_inventory.py rea/00-inputs/audio-config
```
