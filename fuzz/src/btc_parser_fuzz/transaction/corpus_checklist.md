# Bitcoin Transaction Fuzz Corpus Checklist

## Purpose

This checklist tracks the real mainnet transactions used as mutation seeds by
the standalone transaction fuzz suite. It records coverage that is observable
through the public transaction API without affecting seed selection or
mutation. Codes describe the original seed transaction, not malformed states
that mutations can synthesize.

The 77-record corpus has 304 exhaustive assignments across the 25-code
canonical legend: 15 codes are represented and 10 are deliberate collection
targets. Every satisfied predicate is applied to every seed in canonical order.
The source of truth is [`seed_txs.txt`](../../../corpus/transaction/seed_txs.txt);
the legend is [`seed_txs_codes.txt`](../../../corpus/transaction/seed_txs_codes.txt).

## Corpus Record Format

```text
display_txid|codes|raw_hex
```

The display txid identifies the seed, codes are comma-separated, and `raw_hex`
is the complete transaction serialization. The harness never uses codes when
selecting or mutating seeds.

## Status Legend

- `[ ]` TODO
- `[x]` HAVE
- `[~]` EXPAND

## Core Crash-Fuzz Targets

These predicates emphasize shapes and sizes that are useful when fuzzing the
deserializer and serializer. They remain useful even though malformed versions
of the same structures are also reached by mutation.

| Status | Code | Predicate | Current evidence or gap |
| --- | --- | --- | --- |
| [x] | `I01` | Exactly one input | 48 transactions across legacy and SegWit. |
| [x] | `I02` | At least 200 inputs | The 200-input legacy and 292-input SegWit seeds. |
| [x] | `O01` | Exactly one output | 30 transactions across several output classes. |
| [x] | `O02` | At least 200 outputs | The 376-output SegWit scaling seed. |
| [ ] | `W01` | Mixed empty and nonempty witness stacks | No seed has both stack shapes. |
| [x] | `W02` | A zero-length witness item | Five transactions contain this shape. |
| [ ] | `W03` | A witness item at least 65,536 bytes | No seed reaches this large-item threshold. |
| [ ] | `W04` | A witness stack with at least 253 items | The current maximum is five items. |
| [ ] | `L01` | A 9,000–10,000-byte scriptSig | The current maximum scriptSig is 107 bytes. |
| [ ] | `L02` | A 9,000–10,000-byte scriptPubKey | The current maximum scriptPubKey is 1,210 bytes. |
| [ ] | `S01` | Total size 360,000–400,000 bytes | The current maximum total size is 49,444 bytes. |

## Secondary Post-Parse API Targets

The transaction suite calls the output classifier after every successful
deserialization. These codes retain exact public classifier shapes that random
mutation is unlikely to synthesize deliberately.

| Status | Code | Predicate | Current evidence or gap |
| --- | --- | --- | --- |
| [ ] | `F01` | `P2PK` output | Add an exact P2PK template. |
| [x] | `F02` | `P2PKH` output | 22 transactions. |
| [x] | `F03` | `P2SH` output | 12 transactions. |
| [x] | `F04` | `P2WPKH` output | 52 transactions. |
| [x] | `F05` | `P2WSH` output | 15 transactions. |
| [x] | `F06` | `P2TR` output | 18 transactions. |
| [ ] | `F07` | `BareMultisig` output | Add an exact bare-multisig template. |
| [x] | `F08` | `NullData` output | 13 transactions. |
| [ ] | `F09` | `UnknownWitnessProgram` output | Add an unknown witness program. |
| [ ] | `F10` | Non-OP_RETURN `NonStandard` output | No current coverage. |
| [x] | `F11` | OP_RETURN-prefixed `NonStandard` output | Six transactions have oversized or otherwise unrecognized OP_RETURN scripts. |

`F10` deliberately excludes `F11`: all currently classified `NonStandard`
outputs are OP_RETURN-prefixed, so they cover only `F11`.

## Baseline Descriptors

These broad properties anchor the core shapes above and help preserve a varied
set of real-world transaction encodings.

| Status | Code | Predicate | Current evidence |
| --- | --- | --- | --- |
| [x] | `T01` | Legacy serialization | 15 transactions, from 188 to 29,547 bytes. |
| [x] | `T02` | SegWit serialization | 62 transactions, from 150 to 49,444 bytes. |
| [x] | `T03` | Coinbase shape | Three SegWit coinbases with scriptSig lengths 93, 100, and 100 bytes. |

## Measured but Not Required

The 50-column metrics report includes numeric measurements for
CompactSize-width boundaries, exact 252/253 script and witness lengths, exact
65,535/65,536 witness-item lengths, exact witness-stack counts,
witness-to-base-size comparisons, combined high input/output counts, and exact
coinbase scriptSig boundaries. These are useful diagnostics when evaluating a
candidate seed, but they do not create taxonomy codes or TODO items.

In other words, the 25 codes exhaustively describe the selected coverage
predicates; the additional measurements describe the corpus without expanding
the coverage requirements.

## Seed Evaluation and Verification

Generate the deterministic, tab-separated report from the repository root:

```sh
./fuzz/run -m btc_parser_fuzz/transaction/corpus_metrics
./fuzz/run -t javascript --runtime node \
  -m btc_parser_fuzz/transaction/corpus_metrics
```

The extractor uses only the public transaction API. It requires every seed to
deserialize, serialize back to the original bytes, and reproduce its display
txid before reporting the stored codes, derived codes, and detailed metrics.
The `recorded_codes` and `derived_codes` report columns must match exactly on
every row.
