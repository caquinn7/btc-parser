# Performance Benchmarks

This directory contains the `gleam dev perf` benchmark harness. The suite is
intended to catch broad performance regressions in public transaction workflows,
not to produce stable machine-independent numbers. Compare trends and relative
changes within the same machine, target, and runtime.

Input construction, hex decoding, and preflight assertions happen before timing
begins. Timed rows measure only the operation named in the `case` column.

## Commands

Run the suite on the default target from `gleam.toml`, which is Erlang:

```sh
gleam dev perf
```

When neither `--out` nor `--format` is provided, the table report is printed to
stdout.

Save a CSV report to a file. CSV is the default format when `--out` is used:

```sh
gleam dev perf --out /tmp/btc_tx_perf/perf.csv
gleam dev perf --format csv --out /tmp/btc_tx_perf/perf.csv
```

Save the table report to a file:

```sh
gleam dev perf --format table --out /tmp/btc_tx_perf/perf.txt
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

## Decode

`decode / fixtures` measures real transaction fixtures. These rows are smoke
tests for common legacy, SegWit, and witness-heavy shapes that synthetic cases
may not model exactly.

`decode / synthetic inputs` measures parser scaling as the legacy input vector
grows. It is meant to catch input parsing regressions, accidental quadratic list
or `BitArray` work, and CompactSize count handling issues.

`decode / synthetic outputs` measures parser scaling as the legacy output vector
grows. It is meant to catch output parsing regressions and scriptPubKey length
handling problems while keeping the input side fixed.

`decode / synthetic segwit inputs` measures full SegWit transaction decoding as
the input count and matching witness stack count grow together. It is meant to
catch regressions in SegWit input/witness alignment and witness-list traversal.

`decode / synthetic witness items` measures decoding one SegWit input while the
number of witness stack items grows. It is meant to catch per-item overhead,
CompactSize item count handling problems, and list-building regressions.

`decode / synthetic witness payload` measures decoding while witness payload
bytes grow but witness structure stays simple. Decode is expected to be mostly
flat here because payload bytes are captured, not interpreted. A steep increase
would suggest unexpected copying or byte-by-byte payload work.

`decode / malformed` measures malformed inputs that fail after most of the
transaction has already been parsed. These rows are meant to catch expensive
late-failure paths and ensure truncation checks stay precise.

`decode / policy limits` measures policy-limit rejection before unnecessary
payload work. This should remain cheap even when the serialized input includes
large payload bytes.

## Context-Free Consensus Validation

`validate_context_free_consensus / valid inputs` measures successful
context-free consensus validation as input count grows. It exercises the full
validator set on valid transactions, including duplicate-input tracking.

`validate_context_free_consensus / valid outputs` measures successful validation
as output count grows. It is meant to catch regressions in per-output value
checks and cumulative output value tracking.

`validate_context_free_consensus / duplicate inputs` places the duplicate input
late so the validator must inspect nearly the whole input list before failing.
This is meant to catch regressions from near-linear duplicate detection toward
quadratic behavior.

`validate_context_free_consensus / output overflow` places cumulative value
overflow late in the output list. This is meant to catch regressions in
output-sum validation and to compare failure-path cost with the valid output
curve.

## Txid Computation

`txid computation / fixtures` measures `compute_txid` and `compute_wtxid` on
real parsed fixtures. These rows cover common real shapes and the witness-heavy
fixture where `wtxid` includes substantially more data than `txid`.

`txid computation / synthetic inputs` measures `compute_txid` as legacy input
count grows. It is meant to catch serialization or hashing regressions over
large stripped transaction payloads.

`txid computation / synthetic outputs` measures `compute_txid` as legacy output
count grows. It is meant to catch output serialization and hashing regressions.

`txid computation / synthetic segwit inputs` measures both `compute_txid` and
`compute_wtxid` as SegWit input count grows. The `compute_txid` rows are stripped
serialization controls; the `compute_wtxid` rows include witness bytes and should
be more sensitive to witness payload growth.

`txid computation / synthetic witness items` measures `compute_wtxid` while the
number of witness stack items grows. It is meant to catch witness serialization
or hashing regressions driven by item count rather than payload size.

`txid computation / synthetic witness payload` measures `compute_wtxid` while
witness payload bytes grow. This should scale with payload size because witness
serialization and double-SHA256 must read those bytes.

## Serialization

`serialization / fixtures` measures `to_stripped_bytes` and `to_wire_bytes`
on real parsed fixtures. These rows cover common real shapes and confirm the
legacy and SegWit serialization paths both stay healthy.

`serialization / synthetic inputs` measures `to_stripped_bytes` as legacy input
count grows. It is meant to catch stripped serialization regressions over large
input vectors.

`serialization / synthetic outputs` measures `to_stripped_bytes` as legacy output
count grows. It is meant to catch output serialization regressions.

`serialization / synthetic segwit inputs` measures both stripped and witness
serialization as SegWit input count grows. The stripped rows isolate non-witness
serialization; the witness rows include witness stacks and should scale with
witness data.

`serialization / synthetic witness items` measures `to_wire_bytes` while the
number of witness stack items grows. It is meant to catch list traversal and
CompactSize item serialization regressions.

`serialization / synthetic witness payload` measures `to_wire_bytes` while
witness payload bytes grow. This should scale with payload size because the bytes
are emitted into the serialized transaction.

## Reading Results

The suite uses a lean set of scaling points by default. Count-based decode
curves use `1`, `100`, and `1000`; other count-based curves use `20`, `100`, and
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

- `case`: The measured function plus the transaction shape or fixture label.
- `bytes`: The wire-format size of the transaction input used for the row.
- `warmup ms`: How long the benchmark ran before recording measurements.
- `duration ms`: The target amount of timed measurement for the row.
- `ops/call`: The number of logical operations batched inside one timed call.
- `timed calls`: The number of timed calls recorded during `duration ms`.
- `measured ms`: The total elapsed time covered by the recorded timed calls.
- `ops/s`: Estimated logical operations completed per second.
- `us/op`: Estimated microseconds per logical operation.

`ops/s` and `us/op` are normalized back to one logical operation, such as one
`decode`, `validate_context_free_consensus`, `compute_txid`, or serialization
call. That means rows with different `ops/call` values can still be compared.

CSV output uses the same measurements as the table report, with one row per
benchmark case. The leading `run_target`, `run_runtime`, `run_os`, and
`run_architecture` columns repeat the run metadata on every row so the file
remains a single rectangular dataset. The remaining columns contain the section
name, case label, byte size, timing configuration, sample count, measured
milliseconds, operations per second, and microseconds per operation.

```csv
run_target,run_runtime,run_os,run_architecture,section,case,bytes,warmup_ms,duration_ms,ops_per_timed_call,timed_call_count,measured_ms,operations_per_second,microseconds_per_operation
"erlang","Erlang/OTP 28 (ERTS 16.4)","darwin","arm64","decode / fixtures","decode simple legacy tx",223,250,1000,100,11595,998.819,1160871.0,0.861
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
