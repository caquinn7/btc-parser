# Fuzz Testing - `btc_parser`

## Overview

The standalone fuzz project exercises the public transaction and block APIs with
mutated real mainnet wire bytes. Each run selects exactly one suite. Its goal is
to find unhandled exceptions: malformed input should return a structured
`Result` error, never crash the process.

The harness is a robustness check, not a semantic oracle. It does not require a
specific decode or validation error for every malformed input, and it does not
prove every successful parse is a fully valid Bitcoin transaction or block.
Focused library tests cover those exact behaviors.

## Commands

Run commands from the repository root. Arguments before `--` belong to Gleam;
arguments after it belong to the fuzz program.

```text
./fuzz/run [GLEAM_OPTIONS] -- <suite> <iterations> [seed]

suites:
  transaction
  block
```

Selectors are lowercase and exact. The former selector-less syntax is rejected;
there are no aliases and no `all` selector.

Run each suite on the default Erlang target:

```sh
./fuzz/run -- transaction <iterations>
./fuzz/run -- block <iterations>
```

Run each suite on Erlang explicitly:

```sh
./fuzz/run -t erlang -- transaction <iterations>
./fuzz/run -t erlang -- block <iterations>
```

Run each suite on the default JavaScript runtime from `fuzz/gleam.toml`:

```sh
./fuzz/run -t javascript -- transaction <iterations>
./fuzz/run -t javascript -- block <iterations>
```

Run either suite on a particular JavaScript runtime:

```sh
./fuzz/run -t javascript --runtime node -- transaction <iterations>
./fuzz/run -t javascript --runtime node -- block <iterations>
./fuzz/run -t javascript --runtime deno -- transaction <iterations>
./fuzz/run -t javascript --runtime deno -- block <iterations>
./fuzz/run -t javascript --runtime bun -- transaction <iterations>
./fuzz/run -t javascript --runtime bun -- block <iterations>
```

Supply a seed to replay a run:

```sh
./fuzz/run -t erlang -- transaction <iterations> <seed>
./fuzz/run -t erlang -- block <iterations> <seed>
./fuzz/run -t javascript --runtime node -- transaction <iterations> <seed>
./fuzz/run -t javascript --runtime node -- block <iterations> <seed>
```

When no seed is supplied, the runner generates and prints one. Seed arguments
are signed 32-bit integers. They are normalized to the Park-Miller RNG state
range `1..2_147_483_646`, so aliases such as `0` and `1` intentionally produce
the same trace.

The command exits nonzero for invalid arguments or when the selected suite
records a rescued exception. CI runs both suites on Erlang, Node, Deno, and Bun.

## Reports and Reproduction

Every report begins with `suite: transaction` or `suite: block`, followed by
the iteration count, initial RNG state, trace hash, elapsed time, and failure
count. The trace is an order-sensitive SHA-256 hash chain over the mutated
inputs, so the suite, seed, corpus ordering, mutation ordering, and iteration
count reproduce the same inputs.

Failure records retain the selected suite's vocabulary:

- Transaction: `seed_tx`, `mutation`, `hex`, and `exception`.
- Block: `seed_block`, `mutation`, `hex`, and `exception`.

Record the suite, seed, iteration, and mutated hex whenever reporting a failure.

## Iteration Selection

After normalizing the supplied or generated seed, a run uses one deterministic
Park-Miller RNG stream. On every iteration, the selected suite first samples one
entry uniformly from its corpus, then samples one mutation uniformly from that
suite's fixed mutation registry. The chosen mutation consumes any additional RNG
draws needed for offsets, lengths, replacement bytes, and similar parameters.

The harness updates the trace with the resulting bytes before exercising the
selected parser. Consequently, a suite, normalized seed, iteration count,
corpus order, and mutation order together determine the complete selection and
mutation sequence.

## Transaction Workflow

The transaction suite selects a corpus transaction, applies one mutation, and
calls `transaction.deserialize`. A deserialization error is clean. For each
successful parse it also runs context-free consensus validation, classifies
output scripts, serializes stripped and complete wire forms, and computes the
txid and wtxid. Validation errors are clean outcomes. Complete serialization
must exactly equal the mutated input.

Its corpus is `fuzz/corpus/transaction/seed_txs.txt`, using
`txid|codes|raw_hex` records. Labels are documented in
`fuzz/corpus/transaction/seed_txs_codes.txt`.

## Block Workflow

The block suite selects a corpus block, applies one mutation, and calls
`block.deserialize`. A deserialization error is clean. For each successful
parse it runs context-free consensus validation with the mainnet proof-of-work
limit; validation errors are also clean outcomes. It exercises every header
accessor, transaction count and list accessors, base size, total size, weight,
Merkle-root computation, block hashing, header serialization, and complete
serialization.

It requires the recorded transaction count to match the transaction list, the
complete serialization and total size to match the mutated input, and the
weight to equal `base_size * 3 + total_size`. Headers must serialize to 80 bytes
and relevant hashes and Merkle roots must be 32 bytes.

Its corpus is `fuzz/corpus/block/seed_blocks.txt`, using
`display_block_hash|codes|raw_hex` records. Labels are documented in
`fuzz/corpus/block/seed_blocks_codes.txt`: a single legacy coinbase, multiple
legacy transactions, and mixed legacy/SegWit transactions with odd-width Merkle
levels.

## Mutations and Scope

Both registries begin with truncation, byte flips, bit flips, byte insertion,
span deletion, span duplication, and zeroing. The transaction registry then
adds SegWit marker/flag mutation followed by heuristic CompactSize mutation. The
block registry instead adds heuristic CompactSize mutation and transaction-count
CompactSize mutation at byte offset 80, curated compact-target mutation at
header offsets 72–75, then contained-transaction mutation, count-adjusted
transaction removal, count-adjusted transaction duplication, and transaction
swapping. These orders are fixed because they are part of deterministic trace
replay.

Contained-transaction mutation selects one transaction uniformly and applies
truncation, byte flips, bit flips, byte insertion, span deletion, span
duplication, zeroing, or heuristic CompactSize mutation to its complete wire
serialization. It keeps the enclosing block count unchanged, so a
deserialization error remains a clean outcome. Removal and duplication select a
transaction uniformly, remove it or insert an exact copy immediately after it,
and minimally rewrite the block transaction count. They are structurally valid
block encodings and therefore must deserialize successfully when they remain
within the default decode policy, although the unchanged header Merkle root can
make consensus validation fail cleanly. Swapping selects two distinct
transaction indexes and records them in ascending order, then exchanges their
complete wire serializations without changing the header, transaction count, or
block size. It is structurally valid and must deserialize successfully; its
Merkle root or coinbase ordering can still cause a clean consensus-validation
failure. Blocks with no transactions omit the first three structure-aware
strategies, and blocks with fewer than two transactions omit swapping.

Compact-target mutation uniformly selects one of five four-byte `nBits` values:
zero (`0x00000000`), sign bit set (`0x20800001`), overflow (`0x23010000`), a
valid target above the mainnet proof-of-work limit (`0x207FFFFF`), or target one
(`0x03000001`). It splices the selected little-endian value into header bytes
72–75 while retaining the original count and transactions, so it must
deserialize successfully. Context-free validation errors are expected clean
outcomes and exercise proof-of-work handling. Adding this fixed-registry slot
intentionally changes deterministic replay traces.

The harness does not measure allocations, enforce timeouts, or treat elapsed
time as a failure condition. The library's default decode policy remains active.
Use focused tests for exact error shapes and the standalone
[`./benchmarks/run`](../benchmarks/README.md) harness for performance work.
