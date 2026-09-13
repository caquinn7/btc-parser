# Output Script Classification

This document explains how `classify_output_script` identifies a recognised
structural Bitcoin output script template (`OutputScriptType`) for a given
`scriptPubKey`.

Classification is intentionally structural and non-extractive. The classifier
reports which template the bytes match, but it does not extract, decode, or
interpret embedded hashes, public keys, witness programs, multisig parameters,
signatures, or `OP_RETURN` payloads. Callers that need those details should use
`get_raw_script_bytes` and interpret the script bytes in their own layer.

Classification is per-script. It does not evaluate transaction-wide,
configurable relay policy.

---

## Overview

Classification is a two-pass process:

1. **Fixed-template matching** — byte-exact pattern matching against every named
   script type whose structure has a fixed, known length.
2. **Non-template fallback** — scripts that did not match a fixed template are
   tested for other valid witness programs and then for bare multisig.

Any script that fails all structural tests is returned as `NonStandard`. This
fallback does not make a relay-policy decision.

---

## Pass 1 — Fixed-template matching

`classify_output_script` pattern-matches the raw script bytes directly.  Each arm
requires an exact byte layout; the wrong length or wrong opcode bytes fall through
to the next arm.

### P2PKH — Pay-to-Public-Key-Hash

```text
76  A9  14  <20 bytes>  88  AC
```

| Byte(s) | Opcode           | Meaning                                       |
| ------- | ---------------- | --------------------------------------------- |
| `76`    | `OP_DUP`         | Duplicate top stack item                      |
| `A9`    | `OP_HASH160`     | Hash top item with SHA-256, then RIPEMD-160   |
| `14`    | `OP_DATA_20`     | Push the next 20 bytes                        |
| ×20     | `<pubkey hash>`  | RIPEMD-160(SHA-256(pubkey))                   |
| `88`    | `OP_EQUALVERIFY` | Verify top two items are equal, then pop them |
| `AC`    | `OP_CHECKSIG`    | Verify signature against the duplicated key   |

Total: **25 bytes**. This is the most common legacy output type.

---

### P2SH — Pay-to-Script-Hash

```text
A9  14  <20 bytes>  87
```

| Byte(s) | Opcode          | Meaning                            |
| ------- | --------------- | ---------------------------------- |
| `A9`    | `OP_HASH160`    | Hash top stack item                |
| `14`    | `OP_DATA_20`    | Push the next 20 bytes             |
| ×20     | `<script hash>` | RIPEMD-160(SHA-256(redeem script)) |
| `87`    | `OP_EQUAL`      | Verify top two items are equal     |

Total: **23 bytes**. The actual spending conditions are revealed in `scriptSig`.

---

### P2WPKH — Pay-to-Witness-Public-Key-Hash (SegWit v0, single-key)

```text
00  14  <20 bytes>
```

| Byte(s) | Meaning                               |
| ------- | ------------------------------------- |
| `00`    | Witness version 0 (`OP_0`)            |
| `14`    | Push 20 bytes (0x14 = 20)             |
| ×20     | 20-byte witness program (pubkey hash) |

Total: **22 bytes**.

---

### P2WSH — Pay-to-Witness-Script-Hash (SegWit v0, script)

```text
00  20  <32 bytes>
```

| Byte(s) | Meaning                                     |
| ------- | ------------------------------------------- |
| `00`    | Witness version 0 (`OP_0`)                  |
| `20`    | Push 32 bytes (0x20 = 32)                   |
| ×32     | 32-byte witness program (SHA-256 of script) |

Total: **34 bytes**.

---

### P2TR — Pay-to-Taproot (SegWit v1)

```text
51  20  <32 bytes>
```

| Byte(s) | Meaning                                      |
| ------- | -------------------------------------------- |
| `51`    | Witness version 1 (`OP_1`)                   |
| `20`    | Push 32 bytes (0x20 = 32)                    |
| ×32     | 32-byte witness program (Taproot output key) |

Total: **34 bytes**. Supports both key-path and script-path spends
(Taproot/Tapscript). Classification does not validate the output key.

> Note: OP_1 with a 32-byte program is always `P2TR`, and the exact `51 02 4E
> 73` script is `P2A`. Other valid OP_1 witness-program shapes (2–40 bytes)
> fall through to `OtherWitnessProgram`; malformed lengths are `NonStandard`.

---

### P2A — Pay-to-Anchor

```text
51  02  4E  73
```

| Byte(s) | Meaning                                          |
| ------- | ------------------------------------------------ |
| `51`    | Witness version 1 (`OP_1`)                       |
| `02`    | Push two bytes                                   |
| `4E 73` | The exact `Ns` program used by Bitcoin Core P2A |

Total: **4 bytes**. `P2A` is structural recognition of Bitcoin Core's named
relay-policy template. It does not add consensus validation or interpret a
spend.

---

### P2PK — Pay-to-Public-Key (two payload lengths)

**33-byte key payload:**

```text
21  <33 bytes>  AC
```

**65-byte key payload:**

```text
41  <65 bytes>  AC
```

| Byte(s)   | Meaning                          |
| --------- | -------------------------------- |
| `21`/`41` | Push 33 or 65 bytes              |
| ×33/×65   | Key payload bytes                |
| `AC`      | `OP_CHECKSIG` — verify signature |

Total: **35 bytes** with a 33-byte payload or **67 bytes** with a 65-byte
payload. This is a legacy format rarely used in new outputs. Classification
checks the payload length, not whether the payload is a valid public key
encoding.

---

### NullData — OP_RETURN data carrier

A script beginning with `OP_RETURN` (`6A`) is `NullData` when every following
operation is a complete push, as checked by
[`do_is_push_only`](#push-only-validation-do_is_push_only). Script size does not
affect classification. A non-push opcode or malformed/truncated push operation
after `OP_RETURN` makes the script `NonStandard`.

---

## Pass 2 — Non-template fallback (`do_classify_non_template`)

Scripts that did not match any fixed template are passed to this function, which
checks two further cases.

### OtherWitnessProgram — other valid SegWit programs

```text
<version byte>  <push_length byte>  <push_length bytes>
```

Conditions (all must hold):

- `version` is in `0x51`–`0x60` (i.e., `OP_1`–`OP_16`)
- The script is exactly three fields: version opcode, one-byte length, then data
- `push_length` is between 2 and 40 (the valid range for a witness program)

The returned `version` integer is decoded as `version_byte - 0x50` (so `OP_2`
gives version 2, `OP_16` gives version 16).

Cases already handled before reaching this fallback:

- `OP_0` with a 20- or 32-byte program — matched as `P2WPKH` or `P2WSH` in
  pass 1
- `OP_1` with a 32-byte program — matched as `P2TR` in pass 1
- The exact `OP_1 OP_DATA_2 4E 73` script — matched as `P2A` in pass 1

`OtherWitnessProgram` should be treated as forward-compatible, not as an error
or as `NonStandard`. A dedicated constructor for a later assignment requires a
major release.

---

### BareMultisig — structural bare multisig

A script matches `BareMultisig` when `do_is_bare_multisig` recognises the
complete structure:

```text
m  { key-push }...  n  OP_CHECKMULTISIG
```

The matcher follows Bitcoin Core's `MatchMultisig` count and operation grammar,
but intentionally omits Core's SEC public-key validation. It consumes the
script sequentially and does not extract or allocate key payloads.

#### Counts

Both `m` (required signatures) and `n` (key count) must be minimally encoded
script numbers in the range 1–20:

- `OP_1` through `OP_16` encode 1 through 16.
- Values 17 through 20 use a direct one-byte script-number push:
  `01 11`, `01 12`, `01 13`, or `01 14`.

Other push encodings for these values are nonminimal and are rejected. Values
outside 1–20, including count 21, are rejected. The matcher also requires
`m ≤ n`.

#### Key pushes

The matcher consumes exactly `n` complete key-push operations. It accepts all
of these operation forms when the decoded payload size is 33 or 65 bytes:

| Operation       | Layout                                  |
| --------------- | --------------------------------------- |
| Direct push     | `21 <33 bytes>` or `41 <65 bytes>`      |
| `OP_PUSHDATA1`  | `4C 21 <33 bytes>` or `4C 41 <65 bytes>` |
| `OP_PUSHDATA2`  | `4D 2100 <33 bytes>` or `4D 4100 <65 bytes>` |
| `OP_PUSHDATA4`  | `4E 21000000 <33 bytes>` or `4E 41000000 <65 bytes>` |

Payload contents are deliberately uninterpreted. In particular, the classifier
does not check SEC prefixes, elliptic-curve points, or any other public-key
validity condition; arbitrary bytes of length 33 or 65 qualify.

After the key pushes, `n` must be followed immediately by one final
`OP_CHECKMULTISIG` (`AE`) with no trailing bytes. Malformed or truncated pushes,
incorrect key payload sizes, a key-count mismatch, and trailing operations are
therefore `NonStandard`.

Relay-policy evaluation is separate from `classify_output_script`; a qualifying
structural 4–20-key script is `BareMultisig` regardless of a node's relay
policy.

---

## Push-only validation (`do_is_push_only`)

Used for the `NullData` check. The function walks the byte sequence recursively,
consuming one push operation per call. It returns `False` as soon as any
non-push opcode is encountered.

| Opcode(s)      | Hex range | Consumes                                   |
| -------------- | --------- | ------------------------------------------ |
| `OP_0`         | `00`      | 1 byte (opcode only, pushes empty array)   |
| `OP_1NEGATE`   | `4F`      | 1 byte (opcode only, pushes –1)            |
| `OP_1`–`OP_16` | `51`–`60` | 1 byte (opcode only, pushes small integer) |
| Direct push    | `01`–`4B` | 1 + N bytes (opcode encodes the length N)  |
| `OP_PUSHDATA1` | `4C`      | 1 + 1 + N bytes (next byte is N)           |
| `OP_PUSHDATA2` | `4D`      | 1 + 2 + N bytes (next 2 bytes LE are N)    |
| `OP_PUSHDATA4` | `4E`      | 1 + 4 + N bytes (next 4 bytes LE are N)    |
| Anything else  | —         | Returns `False` immediately                |

If the byte slice is exhausted cleanly (`<<>>`) the function returns `True`.

---

## Classification decision tree

```text
classify_output_script(script)
│
├─ 76 A9 14 [×20] 88 AC                  → P2PKH
├─ A9 14 [×20] 87                        → P2SH
├─ 00 14 [×20]                           → P2WPKH
├─ 00 20 [×32]                           → P2WSH
├─ 51 20 [×32]                           → P2TR
├─ 51 02 4E 73                           → P2A
├─ 21 [×33] AC                           → P2PK (33-byte payload)
├─ 41 [×65] AC                           → P2PK (65-byte payload)
├─ 6A …                                  (OP_RETURN prefix)
│   ├─ complete push-only operations      → NullData
│   └─ otherwise                         → NonStandard
└─ (none matched) → do_classify_non_template
    │
    ├─ [51–60] [02–28] [×push_length]    → OtherWitnessProgram(version)
    └─ (none matched) → do_is_bare_multisig
        ├─ structural m-of-n (1≤m≤n≤20, minimal counts)
        │   AND key-payload count = n    → BareMultisig
        └─ otherwise                     → NonStandard
```

---

## Opcode reference

| Opcode             | Hex       | Notes                                                           |
| ------------------ | --------- | --------------------------------------------------------------- |
| `OP_0`             | `00`      | Witness version 0 in SegWit outputs                             |
| `OP_1NEGATE`       | `4F`      | Pushes –1                                                       |
| `OP_DATA_20`       | `14`      | Direct push of 20 bytes (decimal 20 = 0x14)                     |
| `OP_DATA_32`       | `20`      | Direct push of 32 bytes (decimal 32 = 0x20)                     |
| `OP_DATA_33`       | `21`      | Direct push of 33 bytes                                         |
| `OP_DATA_65`       | `41`      | Direct push of 65 bytes                                         |
| `OP_1`–`OP_16`     | `51`–`60` | Push small integers 1–16; also serve as witness version opcodes |
| `OP_RETURN`        | `6A`      | Marks unspendable data-carrier outputs                          |
| `OP_DUP`           | `76`      | Duplicate top stack item                                        |
| `OP_EQUAL`         | `87`      | Check equality                                                  |
| `OP_EQUALVERIFY`   | `88`      | Check equality, fail if not equal                               |
| `OP_HASH160`       | `A9`      | SHA-256 then RIPEMD-160                                         |
| `OP_CHECKSIG`      | `AC`      | Verify a signature                                              |
| `OP_CHECKMULTISIG` | `AE`      | Verify m-of-n signatures                                        |
| `OP_PUSHDATA1`     | `4C`      | Next byte gives push length                                     |
| `OP_PUSHDATA2`     | `4D`      | Next 2 bytes (LE) give push length                              |
| `OP_PUSHDATA4`     | `4E`      | Next 4 bytes (LE) give push length                              |
