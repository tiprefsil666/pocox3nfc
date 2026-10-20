# `batterysecret` — Xiaomi USB-PD / HVDCP authentication handshake

**Target**: `vendor/bin/batterysecret` from MIUI `V12.0.6.0.QJGMIXM` (Android 10, `surya`).
**SHA-256**: `8f12eeb8f77bb9cec47e73cb4639c3b598137d012fccb882f575ceb146946140`
**Arch**: ELF64 AArch64, PIE, stripped, Android 29, interpreter `/system/bin/linker64`.
**Analysed with**: REA 6.4.0 / Hopper (`launcher-sha256:0294ced141cc373468ee22d8343e7dac41980cb05a937994ca81c9f09afe7ded`).
**Evidence bundle**: [`../01-evidence/batterysecret-session.json`](../01-evidence/batterysecret-session.json) (31 records).

> This is a static analysis. Nothing here was observed running on hardware. The
> runtime behaviour of the Xiaomi charger remains unverified.

## Summary

`batterysecret` is the Xiaomi-proprietary half of the fast-charge negotiation. It does
**not** program the BQ2597x charge pump. It performs a **mutual authentication handshake
with the charger** over USB-PD vendor-defined messages (VDM), and only then unlocks the
high-voltage path. The charge-pump driver and the handshake are two separate problems.

The handshake is **HMAC-SHA-256** over a 20-byte message, with a 16-byte challenge seed
and a per-model 32-byte key taken from a table of 10 embedded in the binary. Only the
first 16 bytes of the resulting 32-byte MAC are compared.

## Procedure map

| Address | Hopper name | Recovered role | Evidence ID |
|---|---|---|---|
| `0x2000` | `EntryPoint` | ELF entry → `sub_2008` | `ev_b532e5e0cda274917cc07b56ae085fa7b763e835feb52aebc5a17be3435076f7` |
| `0x2008` | `sub_2008` | `__libc_init` trampoline | `ev_b0a701ab28bec7a37bf4b92f643a5381ff758cfed8ffa540e7cc73b3ddc1fec4` |
| `0x200c` | `sub_200c` | `main` → `sub_4ce0` | `ev_360655d4f70e3f57ad128ae987eb698f1346f80d67c1f9b2f32b29fd25b6813e` |
| `0x21b8` | `sub_21b8` | uevent filter (`POWER_SUPPLY_NAME=usb`, `DATA_ROLE=ufp`) | `ev_78a57e2e94336fdd111eabff3d49b11b34919ddb97b937c26b77c13576d7c1a8` |
| `0x2e0c` | `sub_2e0c` | VDM request builder + state machine | `ev_5c7ebbc546f13ad16e56fdbf0c65a664fb556a3cb6c91eadd7094c6c5aed7610` |
| `0x2ae4` | `sub_2ae4` | **the verification** (the core) | `ev_5fbbe670cb2cf3eb98d403dd06d5b8fdf61c754b56bc44263a9b5959ab2ae673` |
| `0x26e4` | `sub_26e4` | **HMAC-SHA-256** | `ev_647c8283614a543f5ab22dd22a3a4494c6cc26d54b38e03dae2e7cdf09c708d4` |
| `0x2e0c` @ `0x3628` | — | the call site: `sub_2ae4(msg, model, seed)` | `ev_b6a621ba7226a9b620f6fc51e092c0b26ad767a6941de1a7c70b371b4073a0e3` |
| `0x30a8` | `sub_30a8` | per-model seed capture + send | `ev_a1af06f7780023290a65ad39cfb3702046a35d4daf28ac13eae7940cc6a6c69e` |
| `0x317c` | `sub_317c` | session seed generation (16 random bytes) | `ev_ef55c9817fcd7c01a49ba55fea498884420591ca688743598b6c9b651be1c37c` |
| `0x36b0` | `sub_36b0` | PD state wait (`SNK_Ready`/`SRC_Ready`) | `ev_fc5343f5799854c8aa3237713a2ff1937e88532b59aa0cf9264d9480c9872953` |
| `0x45b0` | `sub_45b0` | SHA-256 `init` | — |
| `0x45d4` | `sub_45d4` | SHA-256 `update` | `ev_62031e113077e4ec00c9a6ebb19461dd390029f0f5f711f297c54be23b7ec69d` |
| `0x4ad0` | `sub_4ad0` | SHA-256 `final` | `ev_bf96952e6c2944273a5b150b009ea7fcae6077398424590e077c9197af951c24` |

### The PLT stubs, resolved

Hopper names the imported-function thunks `sub_XXXX`. The `.rela.plt` section says what
they really are; [`../04-tools/resolve_plt.py`](../04-tools/resolve_plt.py) maps them
without a disassembler:

| Stub | Symbol | Stub | Symbol |
|---|---|---|---|
| `sub_4d00` | `strlen` | `sub_4ea0` | `toupper` |
| `sub_4d30` | `klog_write` | `sub_4eb0` | `memcmp` |
| `sub_4e30` | `memset` | `sub_4ec0` | `atoi` |
| `sub_4e60` | `memcpy` | `sub_4ed0` | `time` |
| `sub_4e80` | `__read_chk` | `sub_4ee0` | `srand` |
| `sub_4e90` | `lseek` | `sub_4ef0` | `rand` |
| `sub_4f10` | `__write_chk` | `sub_4f20` | `sscanf` |
| `sub_4f30` | `usleep` | `sub_4f00` | `__strlcat_chk` |

> ⚠️ **This matters.** `sub_4ea0` is `toupper`, not a hex-nibble helper. The first pass of
> this analysis assumed it was one and produced a wrong index derivation. The nibble
> decoding in `sub_2ae4` is built on top of `toupper` and has to be read instruction by
> instruction.

## The crypto, established from bytes rather than names

`sub_26e4` is **HMAC-SHA-256**, not a bare hash. Confirmed independently of the
decompiler, by locating the constants in the file:

- File offset `0x16f0`: the eight SHA-256 initial hash values
  `6a09e667 bb67ae85 3c6ef372 a54ff53a 510e527f 9b05688c 1f83d9ab 5be0cd19` — exact match.
- File offset `0x1710`: all 64 SHA-256 round constants `K[0..63]` — exact match.

The HMAC structure is textbook, read from the AArch64 at `0x26e4`:

```
if (keylen >= 0x41)  key = SHA256(key)     /* 0x2734-0x2750: long keys are hashed */
key = key zero-padded to 64 bytes
ipad = key ^ 0x36                        /* 0x27a4 / 0x27dc (NEON)             */
opad = key ^ 0x5c                        /* 0x28e8 / 0x29c4 (NEON)             */
inner = SHA256(ipad || data)             /* 0x2880-0x28a8: update then final   */
out   = SHA256(opad || inner)            /* 0x2924-0x2950                       */
```

**Evidence**: `ev_683b0930442708ffa824eb9fc9d6956ae551bc1fe495b8e6103acdb0e2e65ea6`
(byte read of the key table), `ev_647c8283614a543f5ab22dd22a3a4494c6cc26d54b38e03dae2e7cdf09c708d4`
(assembly of `sub_26e4`), plus the local constant check in
[`../04-tools/verify_sha256_constants.py`](../04-tools/verify_sha256_constants.py).

## The data tables

### Key table — `0x50a0`, 10 × 32 bytes

These are the HMAC **keys**, one per charger model:

```
[0] 5c4d4179da1501ed11747492e26083d96b8fbc73c82e7bdf5d3255c2a036a1dc
[1] 4554ea907fc3250d2078bd6277d6cf0cb823e62258d087378af29c466b101026
[2] 83d30625cb0f7ce6d49649ff4cfcf9cebe62469b57e31ba62d01de2810ff621a
[3] a1447305166b4a786df5ddd707a8360a7328ced7038487607fa21128a15d1864
[4] e4fb00afd15186af1a44502005d3d1b0b1e9d1a636a51c26349422e7dbadc273
[5] 46b8cae9a46a3254ee551282cf07b7bb6b2ef12bf615463c239bb63b984e42a9
[6] eaf45b6ff3ccce769e82bd0b007b69c406a66b98f427a2bbe455d1ffcb1ecdcc
[7] e787db568b7d704d29cc50a2bb1e971f6f1fd7fe9604deb4d4a1a7a72c63ff42
[8] b5f704a75d0db54a0b5e731779949b321105adc9d5c0858c50efc9bf92892cf4
[9] df47cc3249833bdefeb4a04a257489fc7500d827b2b66b2689bded7ffe49465e
```

The slot is selected by the **charger model number** (`dword_7024`), and the
addressing is `table_base + model * 0x20` (`0x2cd0: add x0, x12, x13, lsl #5`).

### Per-model seed table — `0x5000`, 10 × 16 bytes

```
[0] d6e9770506c7f5f4df7a40008c7467b8
[1] 09604eb9ad37e17bd6b2a4f2a3515984
[2] f6295ce3bde8678c9ffeab616098aba0
[3] ae0c8ee9b05ba233799badcb9fa22b41
[4] 56b7470c9d6f22ca003e40326fa77eb5
[5] 6019b457cd77fd5fedffdc3d0ed06106
[6] 09e47c32760fb2facfc5843df0716465
[7] a601934c1403bfd955ebd77f509ba17f
[8] 3e02b44e19dc24f438e62f026ade4aa7
[9] 343d6b41b900beb4c8bf0e8fa7df8c13
```

`sub_30a8` picks the entry with the same model number and sends it to the charger
as command `4` (format `"%02x"` per byte). The model number itself comes from
`rand() % 10` (`0x3060`: `time` → `srand` → `rand`, then a `smull`/`msub` division by 10).

## The verification algorithm (`sub_2ae4`)

Transcribed from the AArch64 at `0x2ae4`–`0x2dec`
(`ev_5da235f514e3b31b7591e4e4d93d532ca224df150a4bfafec66a2f4de15b410b`).

```
int verify(const char *charger_digest_hex,   /* arg0: 64 hex chars   */
           uint32_t model,                   /* arg1: model number  */
           uint8_t *seed)                    /* arg2: 16-byte seed  */
```

1. **Byte-swap the seed in place.** The 16-byte seed is loaded as four
   little-endian `u32` and each is `rev`-ed to big-endian, then written back
   (`0x2b20`–`0x2b4c`). The result is stored at `sp+0x70`.

2. **Build the index word** from the first 8 bytes of the charger's
   `adapter_id` text (at `sp+0x10`–`sp+0x17`), using two *different* hex
   decoders built on `toupper`:

   ```
   A(c) = (c - '0')      if toupper(c) is a digit
        = toupper(c) + 9  otherwise          <-- NOT a nibble
   B(c) = (c - '0')      if toupper(c) is a digit
        = toupper(c) - 0x37 otherwise         <-- the real nibble

   byte 0 = A(c[0]) + (B(c[1]) << 4)
   byte 1 = A(c[2]) + (B(c[3]) << 4)
   byte 2 = A(c[4]) + (B(c[5]) << 4)
   byte 3 = B(c[7]) + (A(c[6]) << 4)          <-- nibble order reversed
   ```

   The four bytes are packed into `w10` and stored at `sp+0x80`
   (`0x2ce8: str w10, [sp, #0x80]`).

3. **Hash the 20-byte message.** The HMAC key is
   `table[model]` (32 bytes) and the message is `sp+0x70`, length `0x14` = 20
   (`0x2cd4: mov w1, #0x20`, `0x2cdc: mov w3, #0x14`). So the message is
   `byte_swapped_seed || index_word`.

4. **Decode the charger's digest.** The 64-character hex string at `arg0` is
   decoded into 32 raw bytes by a 32-iteration loop (`0x2cf4`–`0x2d44`) using
   the same two decoders, two characters per output byte.

5. **Compare.** `sub_4eb0(charger_digest_32, expected, 0x10)` — a **16-byte**
   `memcmp`. Non-zero → log `"failed to verify pd digest"` and return 0; zero →
   log `"success to verify pd digest"` and return 1.

So the scheme is:

```
expected = HMAC-SHA256( key = table[model], message = swap32(seed) || index_word )
accept  if (memcmp(expected[0..15], charger_digest[0..15]) == 0)
```

> ⚠️ `decoder_a()` in the C reimplementation is **not** a nibble decoder. That is the
> vendor's actual code and it is reproduced verbatim, because a reimplementation has to
> be byte-compatible with it. Do not "fix" it.

## The state machine

`sub_36b0` (`ev_fc5343f5799854c8aa3237713a2ff1937e88532b59aa0cf9264d9480c9872953`) waits
for the PD contract to settle:

- Reads `sys/class/usbpd/usbpd0/current_state`.
- Compares against `"UNKNOWN"`, `"SNK_Ready"`, `"SRC_Ready"` via `memcmp`.
- If the state is `SNK_Ready`: opens `/sys/class/dual_role_usb/otg_default/data_role`,
  writes `"host"`, and re-reads it. It polls up to **3 times with 10 ms sleeps**
  (`usleep(0x2710)`), returning `-22` (`EINVAL`) if the role never becomes `host`.
- If the state is `SRC_Ready`: sleeps 100 ms (`usleep(0x186a0)`) and returns `-11`
  (`EAGAIN`).
- If the state is `UNKNOWN`: returns `-11` (`EAGAIN`).

The caller in `sub_2e0c` loops on `sub_36b0` until it stops returning `-EAGAIN`
(`while ((r0 = sub_36b0()) == -0xb)`), and retries the whole flow up to 4 times
(`var_154 < 0x3`).

## The message flow

`sub_2e0c` builds VDM requests:

- It waits for a PD state whose first two bytes equal `0x2717` (`"'\x27"`), i.e. the
  state string starts with `SN` — the `SNK_Ready` branch.
- A jump table at `0x3018` selects the request to send, indexed by
  `switch_table[0x6e3 + n]`.
- It formats the payload with `"%d,null"` and `"%d,%s"`.
- The response is parsed with `atoi` and a `sscanf`-like `"%d,%s"`.
- The verification is reached from three distinct sites (at `0x363c` and two
  others), all with the command number `5` (`0x3620: cmp w20, #0x5`).

Command `4` is the per-model seed send (`sub_30a8`); command `5` is the
authentication exchange.

## sysfs interface

| Path | Access | Purpose |
|---|---|---|
| `sys/class/usbpd/usbpd0/current_state` | read | PD contract state (`SNK_Ready`, `SRC_Ready`, `UNKNOWN`) |
| `sys/class/usbpd/usbpd0/current_pr` | write | Power Role; also the channel for the per-model seed |
| `sys/class/usbpd/usbpd0/request_vdm_cmd` | read/write | VDM request/response channel |
| `sys/class/usbpd/usbpd0/verify_process` | read/write | Authentication progress |
| `sys/class/usbpd/usbpd0/usbpd_verifed` | read/write | Final verification result (note the vendor's spelling) |
| `sys/class/usbpd/usbpd0/adapter_id` | read | Charger identity — the source of the index word |
| `sys/class/usbpd/usbpd0/adapter_svid` | read | Charger SVID |
| `sys/class/usbpd/usbpd0/pdo2` | read | Power Data Object 2 |
| `sys/class/power_supply/usb/pd_authentication` | write | Auth result to the power supply layer |
| `sys/class/power_supply/usb/real_type` | read | Real charge type |
| `sys/class/power_supply/usb/online` | read | Online state |
| `/sys/class/dual_role_usb/otg_default/data_role` | read/write | USB data role |
| `/sys/power/wake_lock`, `/sys/power/wake_unlock` | write | Wakelock |

Charge type strings observed: `USB`, `USB_CDP`, `USB_DCP`, `USB_ACA`, `USB_PD`,
`USB_HVDCP`, `USB_HVDCP_3`, `TYPEC`, `TYPEC_UFP`, `TYPEC_DFP`, `Wireless`, `Battery`,
`Parallel`, `Wipower`, `Mains`, `Main`, `UPS`, `BMS`, `Unknown`, `UNKNOWN`.

The uevent filter is `POWER_SUPPLY_NAME=usb` plus `DATA_ROLE=ufp`
(`ev_78a57e2e94336fdd111eabff3d49b11b34919ddb97b937c26b77c13576d7c1a8`).

## What this means for the postmarketOS port

1. **The BQ2597x driver and the fast-charge handshake are independent.** The overlay's
   `power: supply: add TI BQ25970 switched-capacitor charge pump` driver drives the
   charge pump; `batterysecret` performs the adapter authentication that unlocks the
   high-power mode. Both are needed for 33 W, and neither is implemented on mainline.
2. **The handshake needs the `usbpd` kernel driver.** Every channel is a sysfs attribute
   under `/sys/class/usbpd/usbpd0/`, which is provided by Qualcomm's downstream
   `usbpd` / `pd-mapper` stack. On mainline SM7150 there is no equivalent, so this
   cannot be ported as-is — the PD policy engine and VDM transport would have to be
   written from scratch.
3. **The proprietary part is the table, not the algorithm.** HMAC-SHA-256 is standard and
   the message flow is recoverable. The 10 keys at `0x50a0` and the 10 per-model seeds
   at `0x5000` are the actual secret material.
4. **The session seed is `rand()`-based.** `sub_317c` fills the 16-byte seed from
   `rand()` four bytes at a time, seeded by `srand(time(NULL))` (`time`, `srand` and
   `rand` are all in the import table). The log line `"session seed: '%s'"` prints it.
   This is a **weak nonce**, and it is per-session.
5. **Only 16 bytes of the MAC are compared.** Two different seeds or two different
   table entries would need to collide in the first 16 bytes of HMAC-SHA-256 to be
   accepted incorrectly. That is a sound truncation, but combined with the seed's
   weakness it is the most promising line of attack if the goal were to unlock fast
   charge on hardware the user does not own — which is out of scope for this port.

## Open questions

- What exactly does the charger do with the per-model seed and the index word? It must
  compute the same HMAC, so both must reach it, but the transport is not reconstructed.
- What is the full VDM message format on the wire, and what do commands other than
  `4` and `5` do?
- Does command `5` correspond to HVDCP 3.0 (`USB_HVDCP_3`)? The string exists in the
  binary but its link to the command number is not established.
- Is `dword_7024` (the model number) really `rand() % 10`, or is it later overridden
  by the charger's response? The write in `sub_30a8` happens before the handshake; a
  later write was not found, but the caller chain was not fully traced.
- What is the exact format of the `adapter_id` string? Only the first 8 characters
  matter, and the kernel driver that writes it was not analysed.

## Reproducing this analysis

```sh
# triage (no disassembler needed)
rea/04-tools/triage.sh rea/00-inputs/charge-stack/batterysecret

# resolve the PLT stubs
rea/04-tools/resolve_plt.py rea/00-inputs/charge-stack/batterysecret

# open in REA/Hopper
mcp__rea rea_open_binary {path: ".../batterysecret"}
mcp__rea rea_binary_overview {}
mcp__rea rea_procedure_assembly {procedure: "0x2ae4"}
mcp__rea rea_procedure_assembly {procedure: "0x26e4"}
mcp__rea rea_read_bytes {address: "0x50a0"}
```

## Licence note

`batterysecret` is a Xiaomi proprietary binary. It is **not** redistributed here; the
workspace keeps a working copy for analysis only. The reimplementation in
[`../03-c-reimplementation/`](../03-c-reimplementation/) is derived from the observed
*behaviour* (the algorithm and the protocol), and it is clean-room with respect to
Xiaomi's code. The table entries quoted above are protocol constants extracted for
analysis; treat them as belonging to Xiaomi and do not redistribute them in a
published artefact without checking the licence.
