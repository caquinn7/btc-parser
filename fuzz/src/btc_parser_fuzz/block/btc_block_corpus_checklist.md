# Bitcoin Block Fuzz Corpus Checklist

## Purpose

This checklist tracks the real mainnet blocks used as mutation seeds by the
standalone block fuzz suite. Its goal is to maximize structural and scaling
coverage observable through the public block and contained-transaction APIs.

The current corpus contains 15 blocks and covers all 25 codes in the canonical
legend. This is considered sufficient baseline coverage for the current public
API and mutation registry; additional seeds should add a new boundary, a
materially different structural interaction, or a substantially cheaper way to
exercise an existing path.

The corpus supports:

- fuzzing seed inputs
- regression reproduction
- parser and serializer validation
- performance investigation
- preservation of structurally distinct real-world block encodings

Codes describe properties of the original seed block. They do not describe
invalid states that the mutation registry can synthesize, such as malformed
compact targets, missing coinbases, changed transaction counts, or mismatched
Merkle roots. The harness does not use the codes when selecting or mutating
seeds; they are documentation for evaluating corpus coverage.

## Corpus Record Format

The block corpus uses one pipe-delimited record per line:

```text
block_height|display_block_hash|codes|raw_hex
```

Multiple codes are comma-separated. The display hash identifies the seed; the
codes are reusable coverage tags rather than seed identifiers. Code definitions
in [`seed_blocks_codes.txt`](../../../corpus/block/seed_blocks_codes.txt) are
the canonical legend, and the records themselves are in
[`seed_blocks.txt`](../../../corpus/block/seed_blocks.txt).

## Status Legend

- `[ ]` TODO
- `[x]` HAVE
- `[~]` EXPAND

## Current Corpus

| Height | Display block hash | Codes | Transactions | Bytes | Legacy / SegWit |
| ---: | --- | --- | ---: | ---: | ---: |
| 0 | `000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f` | `N01,M01,T01` | 1 | 285 | 1 / 0 |
| 170 | `00000000d1145790a8694403d4063f323d499e655c83426834d4ce2f8dd4a2ee` | `N02,M02,T01` | 2 | 490 | 2 / 0 |
| 63911 | `000000000743551952b43409987c004d339475e346e27ecc41d9042adc714284` | `N02,M02,T01,X02` | 2 | 46,490 | 2 / 0 |
| 84661 | `00000000001bbdcc15ac746195f64580d5665ed44772feedb59438ce3621384a` | `N01,M01,T01,C01` | 1 | 210 | 1 / 0 |
| 200510 | `000000000000028ac315bd2644a7654f92d026a774a5da7c6f5f9f6402d0ddfa` | `N04,M04,T01` | 253 | 72,927 | 253 / 0 |
| 360948 | `000000000000000001cb1898e7bf378944063260e47682e17081164877b95cd7` | `N01,M01,T01,C02` | 1 | 266 | 1 / 0 |
| 362085 | `00000000000000000b2383470df04eaa7053c3171902a43ad8a67ae3bc594ca6` | `T01,M04,X03,L01` | 97 | 761,747 | 97 / 0 |
| 363447 | `000000000000000014e18f6a6d670c193fdef12fc181e68e66984cdc6a2dc712` | `N03,M03,T01` | 252 | 74,596 | 252 / 0 |
| 379831 | `00000000000000000d30874b7d3b90bda0fa939c86fd81349d0bb8d4fccdca2f` | `N02,M02,T01,X03` | 2 | 10,339 | 2 / 0 |
| 519311 | `0000000000000000001381004f0bf7b0578189d6853cd8af5098994095213e38` | `T02,M04,X04` | 33 | 22,884 | 18 / 15 |
| 560126 | `00000000000000000021f84bff42ddc7a09c071e11636f64eae3e3be59000c48` | `N05,M02,T02,S01,S02` | 1,024 | 1,090,771 | 549 / 475 |
| 603148 | `0000000000000000000bb2a7db685ccea5c07a28c1b31aabbb54684e06992317` | `N05,M02,T02,X04` | 1,024 | 332,258 | 382 / 642 |
| 899687 | `000000000000000000006ac8105a9e15d83bbb05883f45a1880521b641dfa685` | `N02,M02,T03,S02,S03,W01,W03,X01` | 2 | 3,991,946 | 0 / 2 |
| 918684 | `00000000000000000000af1dc90b9341ea8e52f268e5fee921e0d33e3c4700be` | `T02,M04,W01,W02` | 36 | 33,728 | 4 / 32 |
| 919992 | `00000000000000000001086665340a8d6c9a068bb707696c6a087937c52b80fb` | `T03,M03` | 3 | 893 | 0 / 3 |

## Transaction Count

- [x] **N01 — Exactly one transaction**
  - Height 0 exercises the single-transaction block and single-leaf Merkle path.
  - Heights 84661 and 360948 add the exact lower and upper coinbase scriptSig
    boundaries with no non-coinbase transactions.
- [x] **N02 — Exactly two transactions**
  - Height 170 is the smallest seed that enables transaction swapping.
  - Heights 63911 and 379831 pair a coinbase with an input-heavy and an
    output-heavy transaction shape, respectively.
  - Height 899687 combines two transactions with a near-maximum witness payload.
- [x] **N03 — Exactly 252 transactions**
  - Height 363447 is the largest one-byte CompactSize transaction count.
  - Duplicating a transaction exercises the `252 -> 253` width expansion.
- [x] **N04 — Exactly 253 transactions**
  - Height 200510 is the smallest three-byte CompactSize transaction count.
  - Removing a transaction exercises the `253 -> 252` width contraction.
- [x] **N05 — At least 1,000 transactions**
  - Height 560126 has exactly 1,024 transactions in a near-limit base-heavy
    block.
  - Height 603148 has exactly 1,024 transactions while remaining only 332,258
    bytes.

## Transaction Serialization Mix

- [x] **T01 — Legacy-only transactions**
  - Heights 0, 170, 63911, 84661, 200510, 360948, 362085, 363447, and
    379831.
- [x] **T02 — Mixed legacy and SegWit transactions**
  - Height 519311 contains 18 legacy and 15 SegWit transactions.
  - Height 560126 contains 549 legacy and 475 SegWit transactions.
  - Height 603148 contains 382 legacy and 642 SegWit transactions.
  - Height 918684 contains 4 legacy and 32 SegWit transactions.
- [x] **T03 — SegWit-only transactions**
  - Height 899687 contains two SegWit transactions.
  - Height 919992 contains a SegWit coinbase and two SegWit non-coinbase
    transactions.

## Merkle Tree Shape

- [x] **M01 — Single-leaf Merkle tree**
  - Heights 0, 84661, and 360948.
- [x] **M02 — Perfect power-of-two tree with more than one leaf**
  - Height 170 has two leaves.
  - Heights 63911 and 379831 each have two leaves while covering large
    per-transaction input and output counts.
  - Height 560126 has 1,024 leaves in a near-limit base-heavy block.
  - Height 603148 has 1,024 leaves and exercises a much deeper perfect tree.
  - Height 899687 also has two leaves, one of which is an unusually large
    witness transaction.
- [x] **M03 — Padding at exactly one level**
  - Height 363447 reaches an odd width at the 63-hash level.
  - Height 919992 pads its three transaction leaves once.
- [x] **M04 — Padding at multiple levels**
  - Height 200510 pads the 253- and 127-hash levels.
  - Height 362085 pads several levels beginning with 97 leaves.
  - Height 519311 pads several levels beginning with 33 leaves.
  - Height 918684 pads several levels beginning with 36 leaves.

## Block Scale

- [x] **S01 — Base size at least 900,000 bytes**
  - Height 560126 has a 967,403-byte base size, only 32,597 bytes below the
    1,000,000-byte limit.
- [x] **S02 — Weight at least 3,600,000 weight units**
  - Height 560126 weighs 3,992,980 weight units with a base-heavy profile.
  - Height 899687 weighs 3,993,023 weight units with a witness-heavy profile.
- [x] **S03 — Total serialized size at least 3,600,000 bytes**
  - Height 899687 is 3,991,946 bytes, directly targeting the default 4,000,000-
    byte decode-policy budget.

## Witness Structure

- [x] **W01 — Witness serialized size at least the base size**
  - Height 899687 has 3,991,587 witness bytes and only 359 base bytes.
  - Height 918684 has 27,861 witness bytes and only 5,867 base bytes.
- [x] **W02 — Largest witness item is 253 through 65,535 bytes**
  - Height 918684 contains exactly one item in this range, measuring 22,217
    bytes.
  - Exercises a three-byte CompactSize witness-item length without overlapping
    W03.
- [x] **W03 — Largest witness item is at least 65,536 bytes**
  - Height 899687 has four witness items containing 3,991,573 payload bytes, so
    at least one item is 997,894 bytes or larger.
  - Exercises a five-byte CompactSize witness-item length.

## Contained Transaction Extremes

- [x] **X01 — Contains a transaction at least 100,000 total serialized bytes**
  - Height 899687 contains only two transactions in 3,991,946 total bytes, so at
    least one transaction is much larger than 100,000 bytes.
  - Its low transaction count makes uniform contained-transaction mutation
    select the large transaction frequently.
- [x] **X02 — Contains a transaction with at least 253 inputs**
  - Height 63911 contains a 46,275-byte transaction with 267 inputs and one
    output.
  - Exercises a three-byte CompactSize input count inside a block.
- [x] **X03 — Contains a transaction with at least 253 outputs**
  - Height 379831 has a coinbase with one input and 283 outputs.
  - Height 362085 contains several transactions with 750 outputs.
  - Exercises a three-byte CompactSize output count inside a block.
- [x] **X04 — Contains a scriptSig or scriptPubKey at least 253 bytes long**
  - Height 519311 contains a 254-byte script field.
  - Height 603148 also contains a 254-byte script field.

## Coinbase Boundaries

- [x] **C01 — Coinbase scriptSig is exactly 2 bytes long**
  - Height 84661 has the two-byte scriptSig `0102`.
  - Lower context-free consensus boundary.
- [x] **C02 — Coinbase scriptSig is exactly 100 bytes long**
  - Height 360948 has an exactly 100-byte coinbase scriptSig.
  - Upper context-free consensus boundary.

## Legacy Signature Operations

- [x] **L01 — Near-limit legacy signature operations**
  - Height 362085 has 19,995 legacy sigops; its highest-sigop transaction has
    900, so duplicating that transaction raises the block total to 20,895.
  - Duplicating 95 of its 97 transactions crosses the 20,000-operation limit,
    making the uniformly selected duplication mutation likely to reach the
    boundary.

## Corpus Maintenance

Overlapping codes are intentional when blocks isolate different boundaries,
increase the probability of selecting an extreme contained transaction, or
provide a cheaper path to the same scaling behavior. Do not remove a seed based
only on label overlap.

Before adding or replacing a seed, prefer a candidate that does at least one of
the following:

- covers a code not represented by the current corpus
- targets an exact serialization or consensus boundary
- combines independently covered properties in a materially different shape
- isolates an extreme field in a small block so random mutation selects it often
- exercises a scaling dimension substantially more cheaply than existing seeds

## Seed Evaluation and Verification

Record or derive these values before accepting a candidate:

- block height and computed display hash
- total transaction count and CompactSize width
- legacy and SegWit transaction counts
- base size, total size, witness serialized size, and weight
- number of Merkle levels that require odd-hash padding
- largest contained transaction size
- maximum input count and output count in one transaction
- maximum scriptSig and scriptPubKey lengths
- maximum witness-stack item count and witness-item length
- coinbase scriptSig length
- total structural legacy signature-operation count

Before committing a seed, verify that its raw header hashes to the recorded
display hash, its metrics agree with the raw bytes, it deserializes under the
default policy, and complete serialization reproduces the original bytes.
