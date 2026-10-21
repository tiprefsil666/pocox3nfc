# GNSS: what the factory firmware says about the receiver

**Source**: MIUI `V12.0.6.0.QJGMIXM` (Android 10, `surya`), the factory firmware.
**Tools**: the QMI LOC decoder already in the repository,
[`../../surya-pmos/tools/qmi-loc-idl/`](../../surya-pmos/tools/qmi-loc-idl/)

> Static analysis only. Nothing was run on hardware, and no satellite was
> observed.

## The receiver is the modem, not the application processor

This is the single most important fact for the port, and it is stated
plainly in `vendor/etc/gps.conf`:

```
# NMEA provider (1=Modem Processor, 0=Application Processor)
NMEA_PROVIDER=0
```

`NMEA_PROVIDER=0` means the **application processor** synthesises the
NMEA sentences, not the modem. That matches what the overlay's notes
already record: ModemManager synthesises the NMEA the modem never emits,
which is how Galileo and BeiDou reach the applications at all.

The receiver itself lives in the modem, and the applications talk to it
over QMI. `vendor/lib64/libloc_api_v02.so` is the QMI LOC implementation,
and `vendor/lib64/libgnss.so` is the generic GNSS HAL that drives the
modem's GNSS service.

## The constellations

The modem's GNSS service supports the full set. From `libgnss.so`:

```
blacklist bds 0x%lx, glo 0x%lx, qzss 0x%lx, gal 0x%lx, sbas 0x%lx
```

so **BDS** (BeiDou), **GLO** (GLONASS), **QZSS**, **GAL** (Galileo) and
**SBAS** are all handled, each with its own blacklist mask and its own
"enabled" mask. The log line

```
size %u constellations blacklisted 0x%lx, enabled 0x%lx, sendReset %d
```

shows that a constellation can be blacklisted independently of being
enabled.

`libloc_api_v02.so` carries the per-constellation ephemeris handling:

```
populateQzssEphemeris
populateGlonassEphemeris
QMI_LOC_EVENT_QZSS_EPHEMERIS_REPORT_IND_V02
QMI_LOC_EVENT_GLONASS_EPHEMERIS_REPORT_IND_V02
QMI_LOC_SET_SBAS_CONFIG_REQ_V02
QMI_LOC_GET_SBAS_CONFIG_REQ_V02
```

and a dedicated A-GLONASS protocol synchronisation:

```
LocApiV02::setAGLONASSProtocolSync(bool)
```

The **QMI LOC message table** — every message, its id, its TLVs, their
types and offsets — is already decoded and published in this repository:

```
surya-pmos/tools/qmi-loc-idl/loc-idl-full.txt
```

That is the reference for what can be asked of the modem.

## The three constellation messages that were missing

From the QMI LOC tool's README, and the reason the overlay's `libqmi` patch
exists:

```
0x0088  QMI_LOC_SET_GNSS_CONSTELL_REPORT_CONFIG   two u64 masks + three u8
0x00B8  QMI_LOC_SET_CONSTELLATION_CONTROL         u8 + two u64 masks
0x00BF  QMI_LOC_GET_CONSTELLATION_CONTROL         empty request; the answer
                                                  arrives in an indication
```

**0x00BF is the important one for the port.** Its request is empty and the
answer comes in an *indication*, not in the response. The QMI LOC tool's
README puts it plainly:

> ⚠️ **The pattern that matters in LOC: the response tells you nothing.**
> Almost every LOC response carries only the generic result TLV; the real
> answer arrives in a later **indication** with the same id.

So a mainline `libqmi` that only reads responses will see "successfully
set" and nothing else. The overlay's `libqmi` patch implements these three
messages, which is how Galileo and BeiDou reached the applications.

## A-GPS

`gps.conf` has the A-GPS settings, and the overlay's notes record that
**A-GPS assistance is not working**: the constellations do reach the
applications, but there is no assistance data, so a cold fix takes its
time.

The relevant settings:

```
SUPL_MODE = 3
AGPS_CONFIG_INJECT = 1
CUSTOM_NMEA_GGA_FIX_QUALITY_ENABLED = 0
```

`SUPL_MODE = 3` is a bit mask: bit 0 enables the SUPL server and bit 1
enables the network location provider, so both are on.

`AGPS_CONFIG_INJECT = 1` means the application processor injects the A-GPS
configuration into the modem. `CUSTOM_NMEA_GGA_FIX_QUALITY_ENABLED = 0`
means the modem's GGA quality field is passed through unchanged rather
than being rewritten to a custom value.

`AGPS_CERT_WRITABLE_MASK` and the SUPL server address are carrier
configuration and are commented out in the factory file, so this board
does not have a carrier A-GPS server configured. That is consistent with
`SUPL_MODE` being on but the server address being absent: the mode is
enabled, and the server comes from somewhere else.

## The FLP

`vendor/etc/flp.conf` configures the **Fusion Location Provider**, the
batching that saves power between fixes:

```
BATCH_SIZE=20
OUTDOOR_TRIP_BATCH_SIZE=600
```

and a separate outdoor-trip batch size. The FLP is what lets the modem
keep the receiver off most of the time and deliver a batch of positions
when the application asks. Twenty positions per batch, and six hundred for
an outdoor trip — a sustained activity where the receiver stays on.

## What this means for the port

1. **The receiver is the modem.** On mainline, the GNSS receiver of a
   Qualcomm modem is driven over QMI, and the port needs a QMI LOC client
   that works. The overlay's `libqmi` patch is that client, and the QMI
   LOC tool in this repository is the reference for the protocol.
2. **The constellation configuration is three messages.** Nothing else is
   needed to turn Galileo and BeiDou on; the modem already supports them.
   The three messages are in the overlay's `libqmi` patch.
3. **The NMEA has to be synthesised.** `NMEA_PROVIDER=0` is why the
   applications see NMEA at all: ModemManager generates it. A mainline
   port needs the same, and the overlay's notes record that it works.
4. **A-GPS is the open item.** The constellations work, the assistance
   does not. The overlay's notes list "no A-GPS assistance" under what
   does not work, and the reason is not established: the modem's A-GPS
   path needs the carrier's SUPL server and the injection of the
   configuration, and neither is in the factory file.
5. **Batching is what saves the power.** The FLP's `BATCH_SIZE=20` is the
   modem's default; a mainline client that asks for one position at a
   time will keep the receiver on and drain the battery.

## Open questions

- Why the A-GPS assistance does not arrive. The modem supports it
  (`AGPS_CONFIG_INJECT = 1`), and the overlay's notes list the missing
  assistance as the reason a cold fix is slow. The modem-side log
  (`gnss`, `loc` tags) would show whether the SUPL transaction is even
  attempted.
- Whether the overlay's `libqmi` patch handles the *indication* for
  0x00BF, or only the request. The QMI LOC tool's README warns about
  exactly this, and the difference decides whether the constellation
  masks are ever read back.
- Which constellations the modem actually has enabled by default, and
  which the blacklists in `libgnss.so` apply to.

## Reproducing this analysis

```sh
# the QMI LOC message table
python3 surya-pmos/tools/qmi-loc-idl/dump.py | head -40

# the constellation handling in the modem's HAL
strings -a rea/00-inputs/gnss/libgnss.so | grep -i constellation

# the configuration
grep -iE 'NMEA_PROVIDER|AGPS|SUPL' rea/00-inputs/gnss-config/gps.conf
grep -i BATCH rea/00-inputs/gnss-config/flp.conf
```
