# Fuzz Testing Purpose - `btc_parser/transaction`

## Overview

The purpose of fuzz testing in the `btc_parser/transaction` module is to check
that the transaction parser and immediately related inspection APIs handle
mutated transaction bytes without unhandled exceptions.

This includes malformed, adversarial, and edge-case data, not just valid Bitcoin
transactions.

> **Core Goal:**  
> Catch unhandled exceptions while decoding, validating, inspecting, serializing,
> and hashing mutated transaction input. Malformed input should return `Result`
> errors from the library, not crash the process.

The harness is not a semantic oracle. It does not verify that every malformed
input returns a specific parse error kind, nor does it prove that every
successfully decoded mutated transaction is semantically "correct." Focused unit
tests cover exact error shapes and consensus-validation behavior.

The harness does enforce one structural oracle: every successfully decoded
transaction must serialize back to its exact original wire bytes.

---

## Commands

Run the harness on the default target from `gleam.toml`, which is Erlang:

```sh
gleam dev fuzz <iterations>
```

Run it on Erlang explicitly:

```sh
gleam dev --target erlang fuzz <iterations>
```

Run it on JavaScript using the default JavaScript runtime from `gleam.toml`,
which is Node:

```sh
gleam dev --target javascript fuzz <iterations>
```

Run it on a specific JavaScript runtime:

```sh
gleam dev --target javascript --runtime node fuzz <iterations>
gleam dev --target javascript --runtime deno fuzz <iterations>
gleam dev --target javascript --runtime bun fuzz <iterations>
```

Run it with a specific seed to reproduce a previous run:

```sh
gleam dev --target erlang fuzz <iterations> <seed>
gleam dev --target javascript --runtime node fuzz <iterations> <seed>
```

When no seed is provided, the harness generates one and prints it before the
report. Record that seed when reporting a failure so the run can be replayed.

Seed arguments are signed 32-bit integers, matching the range produced when the
harness interprets four random seed bytes as an integer. Seeds are normalized to
a Park-Miller RNG state before fuzzing starts. The accepted CLI seed range is
`-2_147_483_648..2_147_483_647`, while the effective RNG state range is
`1..2_147_483_646`; this means aliases such as `0` and `1` can intentionally
produce the same trace.

The report includes the iteration count, initial RNG state, trace hash, elapsed
time, failure count, and details for each rescued exception. A failure record
includes the iteration number, seed transaction txid, mutation name, mutated
transaction hex, and exception.

The command exits with a nonzero status when its arguments are invalid or the
report contains any rescued exceptions, so CI treats an unsuccessful fuzz run
as a failure.

The trace is an order-sensitive SHA-256 hash chain over the mutated inputs. Each
iteration computes `SHA256(previous_trace || SHA256(mutated_input))`, starting
from 32 zero bytes, so changing the order or repetition of inputs changes the
reported trace.

---

## Primary Objectives

### 1. Robustness Against Arbitrary Input

The parser operates on raw, potentially untrusted transaction bytes. On each
iteration, the fuzz harness randomly selects one real seed transaction, randomly
selects one mutation, and applies that mutation to the selected transaction.

Fuzz testing checks that:

- `transaction.decode` handles mutated transaction bytes without unhandled
  exceptions
- Successfully decoded transactions can flow through context-free consensus
  validation, output script classification, serialization, txid, and wtxid APIs
  without unhandled exceptions, regardless of the validation result
- Successfully decoded transactions serialize back to their exact input bytes

---

### 2. Discovery of Unexpected Edge Cases

Even well-designed parsers can miss rare or unusual structures.

Fuzzing helps uncover inputs that trigger unexpected exceptions in areas such
as:

- Unusual script lengths
- Unexpected witness stack shapes
- Edge-case CompactSize encodings
- Boundary conditions near policy limits

These are often combinations that are:

- Valid but uncommon
- Invalid in subtle ways
- Not covered by hand-written tests

---

### 3. Failure-Mode Smoke Testing

Clean failure behavior is just as important as successful parsing.

For each mutated input, the harness:

- Calls `transaction.decode`
- If decoding succeeds, calls `transaction.validate_context_free_consensus`
- Regardless of the validation result, classifies every output script
- Serializes both stripped and full wire forms
- Checks that the full wire serialization exactly matches the mutated input
- Computes both txid and wtxid

Any `Error(_)` returned by `decode` or `validate_context_free_consensus` is
treated as a clean outcome. A validation error does not stop the remaining APIs
from being exercised. Any unhandled exception or wire round-trip mismatch is
reported as a fuzz failure with the mutated input hex needed for reproduction.

Use focused unit tests when exact failures matter, such as requiring
`PolicyLimitExceeded`, `UnexpectedEof`, `NonMinimalCompactSize`, offsets, or
context stacks.

---

### 4. Preservation of Internal Invariants

The parser enforces structural guarantees such as:

- Length prefixes match actual data
- Input/output counts are consistent
- Witness stack sizes align with declared counts
- No out-of-bounds reads occur

Fuzz testing continuously attempts to break these invariants by applying
mutations such as truncation, byte flips, bit flips, byte insertion, span
deletion, span duplication, zeroing, SegWit marker/flag mutation, and targeted
CompactSize candidate mutation.

Any invariant violation that escapes as an unhandled exception indicates a
critical bug.

---

### 5. Performance and Resource Non-Goals

The current harness is not a performance or resource-usage test. It does not
measure allocations, detect slow parsing paths, enforce timeouts, or fail based
on elapsed time.

The harness still runs through `transaction.decode`, so the library's default
decode policy is active during fuzzing. The harness does not assert the exact
errors returned when policy limits or structural limits are hit. Use focused
unit tests for policy-limit behavior and `gleam dev perf` for benchmark-style
performance analysis.

---

## Role of the Seed Corpus

The fuzzing strategy uses a **seed corpus of real Bitcoin transactions** stored
in `dev/fuzz/transaction/corpus/seed_txs.txt`. Each record contains
`txid|codes|raw_hex`. Corpus-code labels are documented in
`dev/fuzz/transaction/corpus/seed_txs_codes.txt`.

### Why this matters

- Pure random input is mostly invalid and low-signal
- Real transactions provide **valid structural baselines**
- Mutations explore **realistic edge cases**

### Result

Higher-quality fuzzing with better coverage of meaningful scenarios.

---

## Summary

Fuzz testing exercises the `btc_parser/transaction` parser and related
transaction inspection APIs by:

- Feeding mutated transaction bytes into `transaction.decode`
- Treating `decode` and `validate_context_free_consensus` `Error(_)` results as
  clean outcomes
- Continuing every successful decode through context-free consensus validation,
  output script classification, serialization, and txid/wtxid computation
- Checking exact full-wire serialization round trips
- Recording any unhandled exception with the run's initial RNG state, iteration,
  seed transaction txid, mutation, and mutated hex

> In short:  
> The exercised pipeline should not be crashable with input alone; any crash is
> a bug that should be reproducible from the reported initial RNG state,
> iteration, and mutated hex.

---
