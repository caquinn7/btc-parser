# Performance Benchmarks

This directory contains the `gleam dev perf` benchmark harness. It combines
domain suites for transactions and blocks, and is intended to catch broad
performance regressions in public workflows. Compare trends and relative changes within the
same machine, target, and runtime.

Input construction, hex decoding, and preflight assertions happen before timing
begins. Timed rows measure only the operation named in the `case` column.

## Commands

Run the complete suite on the default target from `gleam.toml`, which is Erlang:

```sh
gleam dev perf
```

List the concrete leaf section IDs without constructing inputs or running
any benchmarks:

```sh
gleam dev perf --list-sections
```

The list contains all implemented leaf sections in canonical order.

`--list-sections` is a standalone mode and cannot be combined with `--section`,
`--out`, or `--format`. It lists concrete leaf IDs only; group selectors are
resolved from those IDs and are not listed separately.

Run one report section by passing its exact leaf ID as a selector:

```sh
gleam dev perf --section transaction.deserialize.fixtures
```

Section selectors are case-sensitive. An exact selector uses a concrete leaf
ID, such as `transaction.deserialize.synthetic-witness-items` or
`transaction.validate-context-free-consensus.duplicate-inputs`. A dot-delimited
group selector selects all of its descendants, so `transaction` selects every
transaction section, `transaction.deserialize` selects every deserialization
section, and `block.compute-merkle-root` selects its scaling workload. Matching
happens at a dot boundary: `transaction.deserial` does not match
`transaction.deserialize.*`, and `transaction.deserialize.` is invalid. A
selector always includes whole report sections; individual timed case rows
within a section cannot be selected. Unprefixed transaction selectors from
earlier harness versions are intentionally rejected.

Repeat `--section` to select more than one section:

```sh
gleam dev perf \
  --section transaction.deserialize \
  --section transaction.serialize.fixtures
```

Repeated and overlapping selectors form a union. For example, passing
`--section transaction.deserialize --section transaction.deserialize.fixtures`
runs every `transaction.deserialize.*` section, with
`transaction.deserialize.fixtures` only once. Selected sections always run in
the suite's canonical order rather than command-line order. When no `--section`
is provided, the complete suite runs.

When neither `--out` nor `--format` is provided, the table report is printed to
stdout.

Save a CSV report to a file. CSV is the default format when `--out` is used:

```sh
gleam dev perf --out /tmp/btc_parser_perf/perf.csv
gleam dev perf --format csv --out /tmp/btc_parser_perf/perf.csv
```

Save the table report to a file:

```sh
gleam dev perf --format table --out /tmp/btc_parser_perf/perf.txt
```

Selection composes with the report flags. For example, save only the
`transaction.deserialize.fixtures` and `block.compute-merkle-root` sections as
CSV:

```sh
gleam dev perf \
  --section transaction.deserialize.fixtures \
  --section block.compute-merkle-root \
  --format csv \
  --out /tmp/btc_parser_perf/fixtures.csv
```

When `--out` references a file in a directory that does not exist, the missing
parent directories are created before writing the report.

Run it on Erlang explicitly:

```sh
gleam dev --target erlang perf
```

Run it on JavaScript using the default JavaScript runtime from `gleam.toml`,
which is Node:

```sh
gleam dev --target javascript perf
```

Run it on a specific JavaScript runtime:

```sh
gleam dev --target javascript --runtime node perf
gleam dev --target javascript --runtime deno perf
gleam dev --target javascript --runtime bun perf
```

The command exits with a nonzero status when its arguments are invalid or a
requested report cannot be written.

## Deserialize

`transaction.deserialize.fixtures` measures real transaction fixtures. These rows are smoke
tests for common legacy, SegWit, and witness-heavy shapes that synthetic cases
may not model exactly.

`transaction.deserialize.synthetic-inputs` measures deserializer scaling as the legacy
input vector grows. It is meant to catch input deserialization regressions,
accidental quadratic list or `BitArray` work, and CompactSize count handling
issues.

`transaction.deserialize.synthetic-outputs` measures deserializer scaling as the legacy
output vector grows. It is meant to catch output deserialization regressions and
scriptPubKey length handling problems while keeping the input side fixed.

`transaction.deserialize.synthetic-segwit-inputs` measures full SegWit transaction
deserialization as the input count and matching witness stack count grow
together. It is meant to catch regressions in SegWit input/witness alignment and
witness-list traversal.

`transaction.deserialize.synthetic-witness-items` measures deserializing one SegWit input
while the number of witness stack items grows. It is meant to catch per-item
overhead, CompactSize item count handling problems, and list-building
regressions.

`transaction.deserialize.synthetic-witness-payload` measures deserialization while witness
payload bytes grow but witness structure stays simple. Deserialization is
expected to be mostly flat here because payload bytes are captured, not
interpreted. A steep increase would suggest unexpected copying or byte-by-byte
payload work.

`transaction.deserialize.malformed` measures malformed inputs that fail after most of the
transaction has already been processed. These rows are meant to catch expensive
late-failure paths and ensure truncation checks stay precise.

`transaction.deserialize.policy-limits` measures policy-limit rejection before unnecessary
payload work. This should remain cheap even when the serialized input includes
large payload bytes.

## Inspection

`transaction.inspection.coinbase-shape` measures `has_coinbase_shape` over
context-free-validated transactions with many ordinary inputs. Deserialization
and validation happen before timing begins, isolating the cost of the private
coinbase-marker scan used by the public inspection helper.

## Context-Free Consensus Validation

`transaction.validate-context-free-consensus.valid-inputs` measures successful
context-free consensus validation as input count grows. It exercises the full
validator set on valid transactions, including duplicate-input tracking.

`transaction.validate-context-free-consensus.valid-outputs` measures successful validation
as output count grows. It is meant to catch regressions in per-output value
checks and cumulative output value tracking.

`transaction.validate-context-free-consensus.duplicate-inputs` places the duplicate input
late so the validator must inspect nearly the whole input list before failing.
This is meant to catch regressions from near-linear duplicate detection toward
quadratic behavior.

`transaction.validate-context-free-consensus.output-overflow` places cumulative value
overflow late in the output list. This is meant to catch regressions in
output-sum validation and to compare failure-path cost with the valid output
curve.

## Txid Computation

`transaction.txid-computation.fixtures` measures `compute_txid` and `compute_wtxid` on
real parsed fixtures. These rows cover common real shapes and the witness-heavy
fixture where `wtxid` includes substantially more data than `txid`.

`transaction.txid-computation.synthetic-inputs` measures `compute_txid` as legacy input
count grows. It is meant to catch serialization or hashing regressions over
large stripped transaction payloads.

`transaction.txid-computation.synthetic-outputs` measures `compute_txid` as legacy output
count grows. It is meant to catch output serialization and hashing regressions.

`transaction.txid-computation.synthetic-segwit-inputs` measures both `compute_txid` and
`compute_wtxid` as SegWit input count grows. The `compute_txid` rows are stripped
serialization controls; the `compute_wtxid` rows include witness bytes and should
be more sensitive to witness payload growth.

`transaction.txid-computation.synthetic-witness-items` measures `compute_wtxid` while the
number of witness stack items grows. It is meant to catch witness serialization
or hashing regressions driven by item count rather than payload size.

`transaction.txid-computation.synthetic-witness-payload` measures `compute_wtxid` while
witness payload bytes grow. This should scale with payload size because witness
serialization and double-SHA256 must read those bytes.

## Serialize

`transaction.serialize.fixtures` measures `serialize_stripped` and `serialize`
on real parsed fixtures. These rows cover common real shapes and confirm the
legacy and SegWit serialization paths both stay healthy.

`transaction.serialize.synthetic-inputs` measures `serialize_stripped` as legacy input
count grows. It is meant to catch stripped serialization regressions over large
input vectors.

`transaction.serialize.synthetic-outputs` measures `serialize_stripped` as legacy output
count grows. It is meant to catch output serialization regressions.

`transaction.serialize.synthetic-segwit-inputs` measures both stripped and witness
serialization as SegWit input count grows. The stripped rows isolate non-witness
serialization; the witness rows include witness stacks and should scale with
witness data.

`transaction.serialize.synthetic-witness-items` measures `serialize` while the
number of witness stack items grows. It is meant to catch list traversal and
CompactSize item serialization regressions.

`transaction.serialize.synthetic-witness-payload` measures `serialize` while
witness payload bytes grow. This should scale with payload size because the bytes
are emitted into the serialized transaction.

## Block

`block.compute-merkle-root.synthetic-transactions` measures
`block.compute_merkle_root` over prebuilt, parsed blocks containing `1`, `100`,
and `1,000` unique minimal legacy transactions. Transaction versions make the
transactions unique, so the preflight mutation flag remains false. Block
construction and deserialization occur before timing; each timed operation
computes only the Merkle root. The curve uses `100`, `10`, and `1` operations per
timed call respectively, with a 250 ms warmup and a 1,000 ms measurement
duration.

## Reading Results

The suite uses a lean set of scaling points by default. Count-based deserialization
curves use `1`, `100`, and `1000`; other count-based transaction curves use
`20`, `100`, and `1000`; the block Merkle-root curve uses `1`, `100`, and
`1000`; witness payload curves use `64`, `10_000`, and `100_000` bytes.

Table reports begin with metadata describing the target, runtime, operating
system, and architecture used for the run:

```text
target:       erlang
runtime:      Erlang/OTP 28 (ERTS 16.4)
os:           darwin
architecture: arm64
```

Metadata collection is best-effort. A field is reported as `unknown` when the
runtime does not make it available.

The results table has these columns:

- `case`: The measured function plus the input shape or fixture label.
- `bytes`: The complete serialized size of the input value used for the row
  (a transaction for transaction rows or a block for block rows).
- `warmup ms`: How long the benchmark ran before recording measurements.
- `duration ms`: The target amount of timed measurement for the row.
- `ops/call`: The number of logical operations batched inside one timed call.
- `timed calls`: The number of timed calls recorded during `duration ms`.
- `measured ms`: The total elapsed time covered by the recorded timed calls.
- `ops/s`: Estimated logical operations completed per second.
- `us/op`: Estimated microseconds per logical operation.

`ops/s` and `us/op` are normalized back to one logical operation, such as one
`deserialize`, `validate_context_free_consensus`, `compute_txid`, or serialization
call. That means rows with different `ops/call` values can still be compared.

Table headings and CSV `section` values use canonical concrete leaf section IDs.
Each is accepted as an exact `--section` selector; group selectors do not appear
as report headings. CSV output uses the same measurements as the table report,
with one row per benchmark case. The leading `run_target`, `run_runtime`,
`run_os`, and `run_architecture` columns repeat the run metadata on every row so
the file remains a single rectangular dataset. The remaining columns contain the
canonical section ID, case label, byte size, timing configuration, sample count,
measured milliseconds, operations per second, and microseconds per operation.

```csv
run_target,run_runtime,run_os,run_architecture,section,case,bytes,warmup_ms,duration_ms,ops_per_timed_call,timed_call_count,measured_ms,operations_per_second,microseconds_per_operation
"erlang","Erlang/OTP 28 (ERTS 16.4)","darwin","arm64","transaction.deserialize.fixtures","deserialize simple legacy tx",223,250,1000,100,11595,998.819,1160871.0,0.861
```

Batching is chosen by operation shape. Very fast rows use larger batches to
reduce timer overhead, while slow witness-inclusive SegWit rows use smaller
batches so JavaScript runs still record enough timed calls for useful estimates.

## When To Add A Benchmark

Add a benchmark when it answers at least one of these questions:

- Does this public operation scale with an input dimension the suite does not
  already cover?
- Could this change introduce quadratic behavior, excessive copying, or repeated
  hashing or serialization?
- Does this malformed or policy-rejected input exercise a distinct fail-fast
  path?
- Does this real fixture cover a transaction shape that synthetic cases do not
  model well?
- Would this row help diagnose a regression that existing rows would only
  vaguely reveal?

Avoid adding a benchmark when:

- It only differs by returned value, not by meaningful work performed.
- It duplicates an existing curve with a different label.
- It adds another intermediate point to a curve without a specific reason.
- It measures setup work that is not part of the public operation being timed.
- It is interesting only once; prefer a temporary local benchmark for
  investigation.

If a case is useful but not needed in the default suite, prefer adding it to a
future deeper/profiled run instead of expanding the default run.
