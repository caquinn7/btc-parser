# AGENTS.md

## Project Purpose

`btc_tx` is a Gleam library for working with Bitcoin transactions: parsing wire
bytes, inspecting transaction fields, classifying output scripts, serializing
transactions, and running context-free consensus checks. It aims to mirror
Bitcoin's wire format closely, expose malformed encodings as structured errors,
and remain portable across Erlang and JavaScript targets.

This library does not perform full transaction validation. Do not add behavior
that requires UTXO lookup, script execution, signature verification, block
context, mempool policy, or network/RPC access unless the project scope changes.

## Architecture

- `src/btc_tx.gleam` is the public API and main domain model. It contains opaque
  transaction/input/output/script types, decode policy, parse errors, output
  script classification, context-free consensus validation, serialization, and
  txid/wtxid computation.
- `src/internal/reader.gleam` is the byte reader. It owns offset tracking and
  byte-aligned reads.
- `src/internal/parser.gleam` is a small parser combinator layer used to attach
  parse contexts and indexed locations to errors.
- `src/internal/compact_size.gleam` handles Bitcoin CompactSize read/write,
  including minimal-encoding checks.
- `src/internal/fixed_int/*.gleam` stores signed/unsigned 64-bit values as
  little-endian bytes so values remain exact on JavaScript.
- `src/internal/hash32.gleam` stores 32-byte transaction hashes in wire-order
  little-endian bytes.
- `dev/fuzz_test/` contains the mutation-based fuzz harness and seed corpus.
- `dev/perf_test/` contains the `gleam dev perf` benchmark harness and docs for
  interpreting benchmark groups.
- `docs/` documents API behavior and output script classification.

## Build And Test Commands

- `gleam format` - format files/directories passed as arguments; defaults to the
  current directory.
- `gleam build` - compile the default target from `gleam.toml` (`erlang` here).
  Like `gleam test`, it accepts target/runtime options when building another
  target.
- `gleam test -t erlang` - run the test suite on the Erlang target.
- `gleam test -t javascript --runtime node` - run the test suite on JavaScript
  using Node.
- `gleam test -t javascript --runtime deno` - run the test suite on JavaScript
  using Deno.
- `gleam test -t javascript --runtime bun` - run the test suite on JavaScript
  using Bun.
- `gleam dev --target erlang fuzz <iterations> [seed]` - fuzz parser behavior.
- `gleam dev --target javascript --runtime node fuzz <iterations> [seed]` - fuzz
  JS behavior when a JS-specific change is involved.
- `gleam dev --target erlang perf` - run the performance benchmark suite on
  Erlang.
- `gleam dev --target javascript --runtime node perf` - run the performance
  benchmark suite on JavaScript using Node. Use `--runtime deno` or
  `--runtime bun` when a JS runtime-specific change is involved.

Run both Erlang and at least one JavaScript runtime for meaningful code changes;
the number of target-specific tests is small, but almost all tests run on every target.
Run all JavaScript runtimes before publishing a package release, changing public
API behavior, or touching runtime-sensitive code such as `BitArray`, fixed-width
integers, CompactSize, serialization, hashing, or FFI.

## Important Invariants

- Preserve transaction wire order and little-endian byte order. Public hash bytes
  and prevout txids are exposed in the same little-endian order used on the wire.
- Preserve the phantom-type validation boundary. `decode` produces
  `Transaction(Parsed)`, `validate_consensus` is the only public upgrade path to
  `Transaction(Validated)`, and APIs that require validated transactions should
  keep that requirement.
- Parsing must consume exactly one transaction. Extra bytes must return
  `TrailingBytes`, not be ignored.
- CompactSize integers must reject non-minimal encodings.
- Parse errors must include accurate byte offsets and context stacks from outer
  to inner context, such as `InTransaction`, `InInputs`, `AtInput(n)`,
  `AtField(...)`.
- Resource limits are policy, not consensus. Exceeding `DecodePolicy` limits
  should report `PolicyLimitExceeded`; structurally impossible lengths/counts
  should report `InsufficientBytes` or `UnexpectedEof`.
- Reader and parser code should not panic on user-controlled input. Existing
  panics/asserts should remain limited to internal invariants already proven by
  earlier checks.
- Witness stack count must match input count for SegWit transactions.
- `to_stripped_bytes` excludes SegWit marker/flag and witness data. `to_witness_bytes`
  includes them only for SegWit transactions.

## Domain Constraints

- Context-free consensus checks currently include: non-empty inputs/outputs,
  output money range, cumulative output money range, coinbase structure,
  coinbase scriptSig length, and duplicate input detection.
- `max_satoshis` is `2_100_000_000_000_000`.
- Coinbase marker is exactly null prevout: 32 zero bytes plus vout
  `0xFFFFFFFF`.
- Coinbase scriptSig length must be 2 to 100 bytes inclusive after consensus
  validation.
- Output script classification is structural. It recognizes P2PK, P2PKH, P2SH,
  P2WPKH, P2WSH, P2TR, standard bare multisig, standard NullData, future witness
  programs, and `NonStandard`.
- NullData classification follows Bitcoin Core standardness shape: `OP_RETURN`,
  push-only payload, total script length at most 83 bytes. This is relay policy,
  not consensus validation.
- Bare multisig classification is standard bare multisig only: 1 <= m <= n <= 3,
  with valid compressed or uncompressed pubkey pushes.
- Unknown witness outputs should remain forward-compatible and distinct from
  `NonStandard`.

## Coding Conventions

- Follow existing Gleam style and run `gleam format`.
- Prefer opaque domain types and accessor functions over exposing representation.
- Keep public API documentation clear about byte order, validation state, and
  whether a check is structural, policy, or consensus.
- Use parser helpers (`read_field`, `read_compact_size_as_int`,
  `parser.with_context`, `parser.indexed_repeat`) so new parse failures get
  consistent offsets and contexts.
- Use `Result` for malformed input and validation failures. Reserve panic/assert
  for impossible internal states.
- Be careful with target-specific integer behavior. Use `int64`/`uint64` helpers
  and string conversions for values that may exceed JavaScript safe integer
  limits.
- Keep internal modules internal unless a new public capability is intentional.

## Testing Strategy

- Add focused unit tests near the behavior changed, usually in
  `test/btc_tx_test.gleam` for public API behavior or `test/internal/...` for
  internal helpers.
- Test both success and exact failure shape for parser changes: error kind,
  offset, and context stack.
- Include boundary tests for limits: exactly at limit, one over limit, truncated
  data, non-minimal CompactSize, and trailing bytes where relevant.
- For consensus changes, test valid transactions, isolated violations, and
  multiple-error collection when validators can report together.
- For serialization or hashing changes, include known vectors or manual double
  SHA-256 comparisons and round-trip checks.
- For script classification, test exact byte templates plus near misses that
  should be `NonStandard` or `UnknownWitness`.
- Run the fuzz harness after changes to byte-level parsing, CompactSize handling,
  length/count validation, SegWit detection, witness parsing, reader/parser
  internals, or decode policy enforcement. Run with an explicit seed, or record
  the generated seed from the fuzz output, so any failure can be reproduced.
  Record the failing seed/hex if a crash or hang is found.
- Run the perf harness after performance-sensitive changes to decode,
  validation, transaction inspection, serialization, hashing, witness handling,
  parser/list accumulation, `BitArray` handling, or decode policy fail-fast
  behavior. Compare trends within the same machine, target, and runtime rather
  than treating absolute numbers as portable.

## Performance Considerations

- Enforce cheap size/count limits before allocating or recursing over large
  collections.
- Preserve fail-fast behavior for impossible counts, oversized scripts, oversized
  witness stacks, and cumulative witness payload limits.
- Avoid conversions that lose precision on JavaScript. Keep 64-bit values as
  byte-backed wrappers until a safe conversion is proven.
- Avoid quadratic (O(n^2)) list or `BitArray` work in parser hot paths. Accumulate lists in
  reverse and reverse once, as the parser helpers do.
- Do not silently relax default policy limits. They protect callers parsing
  untrusted bytes even though some consensus-valid transactions may exceed them.
- Keep the default perf suite selective. Add benchmark rows only when they cover
  a distinct public operation, scaling dimension, fail-fast path, or transaction
  shape not already represented.
