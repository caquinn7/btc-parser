# AGENTS.md

## Project Purpose

`btc_parser` is a Gleam library for working with Bitcoin data structures. Its
transaction domain deserializes wire bytes, exposes transaction fields,
classifies output scripts, serializes transactions, and runs context-free
consensus checks. Its block domain deserializes and serializes complete blocks,
exposes header fields and embedded transactions, computes sizes, weights,
Merkle roots, and block hashes, and runs context-free consensus checks. It aims
to mirror Bitcoin's wire format closely, expose malformed encodings as structured
errors, and remain portable across Erlang and JavaScript targets.

This library does not perform full transaction or block validation. Do not add
behavior that requires UTXO lookup, script execution, signature verification,
chain state, mempool policy, or network/RPC access unless the project scope
changes.

## Architecture

- `src/btc_parser/transaction.gleam` defines the public transaction API and
  transaction data model. It contains opaque transaction/input/output/script
  types, whole-value deserialization, decode policy, decode errors, output script
  classification, context-free consensus validation, serialization, and
  txid/wtxid computation.
- `src/btc_parser/block.gleam` defines the public block API and block/header
  data model. It deserializes complete blocks by decoding a block header,
  CompactSize transaction count, and contained transaction prefixes; exposes
  header and transaction accessors; and owns block decode policies and
  block-level decode errors. It computes block sizes, weights, Merkle roots, and
  block hashes; serializes headers and complete blocks; and performs documented
  context-free consensus validation using a caller-supplied proof-of-work limit.
- `src/btc_parser/internal/reader.gleam` is the byte reader. It owns offset
  tracking and byte-aligned reads.
- `src/btc_parser/internal/parser.gleam` is a small parser combinator layer
  used to attach parse contexts and indexed locations to errors.
- `src/btc_parser/internal/decode.gleam` maps shared reader and CompactSize
  errors into domain-owned decode errors and converts exact unsigned 64-bit
  values to target-safe `Int`s.
- `src/btc_parser/internal/compact_size.gleam` handles Bitcoin CompactSize
  read/encode, including minimal-encoding checks.
- `src/btc_parser/internal/fixed_int/*.gleam` stores signed and unsigned
  fixed-width values, including 64-bit and 256-bit integers, as little-endian
  bytes so values remain exact on JavaScript.
- `src/btc_parser/internal/hash256.gleam` stores 256-bit hashes in wire-order
  little-endian bytes for transaction identifiers, block-header hashes, and
  merkle roots.
- `src/btc_parser/internal/pow_target.gleam` expands compact target encodings,
  preserves nonzero unsigned 256-bit targets exactly, and compares targets,
  proof-of-work limits, and block hashes without target-native integer loss.
- `src/btc_parser/internal/lifecycle.gleam` provides the shared phantom types
  that mark parsed values and values that passed available context-free
  validation.
- `dev/fuzz/transaction/` contains the transaction fuzz suite, report, and seed
  corpus; `dev/fuzz/internal/` contains shared fuzz utilities.
- `benchmarks/` is an independent Gleam project that consumes `btc_parser`
  through its public API. `benchmarks/src/btc_parser_benchmarks/transaction/`
  and `benchmarks/src/btc_parser_benchmarks/block/` contain domain-specific
  workloads and builders; `benchmarks/src/btc_parser_benchmarks/suite.gleam`
  combines their canonical registries, resolves domain and nested selectors
  such as `transaction.deserialize` and `block.compute-merkle-root`, captures
  metadata once, and runs sections in canonical order.
  `benchmarks/src/btc_parser_benchmarks/internal/benchmark.gleam` owns shared
  measurement primitives,
  `benchmarks/src/btc_parser_benchmarks/internal/bitcoin_wire.gleam` owns the
  shared CompactSize encoder, and
  `benchmarks/src/btc_parser_benchmarks/report.gleam` owns domain-neutral
  table/CSV reporting. The `bytes` column is the complete serialized size of
  the input value for a row, regardless of its domain.
- `docs/` documents the public transaction and block APIs and output script
  classification.

## Serialization Terminology

Use these terms consistently across the public API and internal implementation:

- **Serialize / deserialize** describe whole-value operations over canonical
  Bitcoin wire-format serialization. Public deserialization must consume the
  entire input. Wire-format canonicality describes the encoding, not consensus
  validity; a `Parsed` value has not yet passed context-free consensus validation.
- **Decode** describes interpreting one complete Bitcoin structure from the
  beginning of an input, possibly leaving trailing bytes for an enclosing
  decoder.
- **Parse** refers to the internal, composable parser machinery used to implement
  decoding.
- **Parsed** is the phantom state for a structurally valid in-memory value that
  has not yet passed context-free consensus validation.
- Decoding behavior and failures use `DecodePolicy`, `DecodeError`, and related
  names. Hex entry points use `DeserializeHexError` to distinguish invalid hex
  from underlying decode failures.

## Build And Test Commands

- `gleam format` - format files/directories passed as arguments; defaults to the
  current directory.
- `gleam build` - compile the default target from `gleam.toml` (`erlang` here).
  Use `gleam build --target javascript` to compile the JavaScript target.
- `gleam test -t erlang` - run the test suite on the Erlang target.
- `gleam test -t javascript --runtime node` - run the test suite on JavaScript
  using Node.
- `gleam test -t javascript --runtime deno` - run the test suite on JavaScript
  using Deno.
- `gleam test -t javascript --runtime bun` - run the test suite on JavaScript
  using Bun.
- See `dev/fuzz/README.md` for fuzz commands, seed replay, scope, and
  target/runtime guidance.
- See `benchmarks/README.md` for performance commands, report formats,
  benchmark coverage, and target/runtime guidance. Run the complete suite with
  `./benchmarks/run`; benchmark arguments follow `--`, as in
  `./benchmarks/run -- --section transaction.deserialize.fixtures`.

Run unit tests on both Erlang and at least one JavaScript runtime for meaningful
library code changes; the number of target-specific tests is small, but almost
all tests run on every target. Changes confined to the fuzz or standalone
benchmark harnesses do not require running the unit test suite; validate the
affected harness directly on the appropriate targets and runtimes instead. Run
unit tests when the same change also touches library code or shared behavior
covered by those tests.
Run all JavaScript runtimes before publishing a package release, changing public
API behavior, or touching runtime-sensitive code such as `BitArray`, fixed-width
integers, CompactSize, serialization, hashing, or FFI.
Use Node as the default JavaScript runtime for fuzz and performance validation.
Also use Deno and Bun when a harness change touches JavaScript FFI,
runtime-sensitive `BitArray` or integer behavior, runtime configuration,
file/timer/CLI behavior, or a runtime-specific bug.

## Correctness Invariants

- Preserve Bitcoin wire order and little-endian byte order. Public transaction
  hashes, outpoint txids, block hashes, and merkle roots are exposed in
  the same little-endian order used on the wire.
- Preserve exact proof-of-work arithmetic across targets. `Uint256` values use
  exactly 32 little-endian bytes; `PowTarget` and `PowLimit` additionally
  guarantee a nonzero unsigned value. `new_pow_limit` validates only this
  representation, so callers remain responsible for selecting the correct
  network limit.
- Preserve the phantom-type validation boundary. Block deserialization produces
  `Block(Parsed)` containing `Transaction(Parsed)` values.
  `transaction.validate_context_free_consensus` upgrades an individual
  transaction, while `block.validate_context_free_consensus` upgrades a block
  and its contained transactions to `ContextFreeValidated`. APIs whose
  documented guarantees depend on context-free validation should keep that
  requirement.
- Public deserializers must consume exactly one value. Extra bytes after a
  complete block or transaction must return `TrailingBytes`, not be ignored.
- CompactSize integers, including block transaction counts, must reject
  non-minimal encodings.
- Do not pass user-controlled CompactSize-derived values directly into reader
  byte-count operations or repeat helpers. First convert them to `Int` with
  decode-error handling, then validate them against the current reader state and
  any relevant policy limit.
- Decode errors must include accurate byte offsets and context stacks from outer
  to inner context, such as `InBlock`, `AtTransaction(n)`, `InTransaction`,
  `AtInput(n)`, and `AtField(...)`.
- Resource limits are policy, not consensus. Exceeding a transaction or block
  `DecodePolicy` limit should report `PolicyLimitExceeded`; structurally
  impossible lengths/counts should report `InsufficientBytes` or `UnexpectedEof`.
- Reader and parser code should not panic on user-controlled input. Prefer
  returning structured `DecodeError`s for prevalidated variable-length reads even
  when a prior check should make failure impossible. Reserve `assert`/`panic`
  for fixed-width reads after successful reader checks or for private
  representation invariants proven locally.
- Witness stack count must match input count for SegWit transactions.
- Extended SegWit serialization must contain at least one witness item across
  all input stacks. An all-empty witness record is superfluous; a zero-length
  item still counts as present.
- `serialize_stripped` excludes SegWit marker/flag and witness data. `serialize`
  includes them only for SegWit transactions.

## Scope and Semantic Constraints

- Keep transaction and block validation aligned with their documented local
  `validate_context_free_consensus` scopes; do not add context-dependent checks
  such as UTXO lookup, block subsidy, or block-height validation.
- Treat the caller-supplied `PowLimit` as a maximum target only. Block validation
  checks that the compact target is valid, does not exceed that limit, and is
  satisfied by the header hash; it does not derive the required target from
  preceding headers or validate a Signet block solution.
- Keep structural inspection separate from validation: helpers may identify wire
  shapes, markers, and script templates, but consensus meaning should flow
  through documented validation APIs.
- Output script classification is structural and should stay aligned with
  `classify_output_script` docs and tests; do not turn it into script execution,
  key validation, or consensus validation. NullData classification remains relay
  policy, not consensus validation.
- Unknown witness programs should remain forward-compatible and distinct from
  `NonStandard`.

## Coding Conventions

- Run `gleam format` and match nearby code for naming, control flow,
  parser/result patterns, and public API documentation style.
- Use `count` for numbers of elements, `length` for byte counts encoded in
  wire-format length prefixes, and `size` for measured or calculated byte
  footprints and resource limits.
- Treat source doc comments, tests, and focused docs as the detailed behavior
  source of truth; keep `AGENTS.md` focused on scope, invariants, and workflow
  guardrails.
- Update relevant source doc comments and focused docs as part of code changes
  when they would otherwise become stale.
- Prefer opaque domain types and accessor functions over exposing representation.
- Keep public API documentation clear about byte order, validation state, and
  whether a transaction or block check is structural, policy, or consensus.
- Use parser helpers (`read_field`, `read_compact_size_as_int`,
  `parser.with_context`, `parser.indexed_repeat`) so new decode failures get
  consistent offsets and contexts.
- Use `Result` for malformed input and validation failures. Reserve panic/assert
  for impossible internal states.
- Be careful with target-specific integer behavior. Use `int64`/`uint64` helpers
  and string conversions for values that may exceed JavaScript safe integer
  limits.
- Keep internal modules internal unless a new public capability is intentional.

## Testing Strategy

- Add focused unit tests near the behavior changed. Mirror source module paths
  under `test/`, adding the `_test` suffix for test modules; for example,
  transaction behavior is covered by `deserialize_test.gleam`,
  `deserialize_with_policy_test.gleam`, `structural_inspection_test.gleam`,
  `validate_context_free_consensus_test.gleam`, and
  `serialization_and_identifiers_test.gleam` under
  `test/btc_parser/transaction/`; real transaction wire examples are stored in
  `test/btc_parser/transaction/fixtures/` and exercised by
  `fixture_test.gleam`.
  Block behavior is covered by `block_test.gleam`,
  `compute_merkle_root_test.gleam`, `pow_limit_test.gleam`,
  `validate_context_free_consensus_test.gleam`, and `fixture_test.gleam` under
  `test/btc_parser/block/`; real mainnet block examples are stored in its
  `fixtures/` directory.
- Test both success and exact failure shape for transaction and block
  deserializer changes: error kind, offset, and context stack.
- Include boundary tests for limits: exactly at limit, one over limit, truncated
  data, non-minimal CompactSize, and trailing bytes where relevant.
- When changing repeated parser helpers, include a JavaScript test at the
  relevant policy maximum to catch stack-exhaustion regressions that small
  fixtures do not expose.
- For consensus changes, test valid blocks and transactions, isolated
  violations, and deterministic multiple-error collection when validators can
  report together.
- For serialization or hashing changes, include known vectors or manual double
  SHA-256 comparisons and round-trip checks.
- For script classification, test exact byte templates plus near misses that
  should be `NonStandard` or `UnknownWitnessProgram`.
- Run the transaction fuzz harness after changes to shared byte-level parsing,
  CompactSize handling, reader/parser internals, or transaction decode policy
  enforcement. Run fuzz with an explicit seed, or record the generated seed from
  the output, so any failure can be reproduced. Record the failing seed/hex if a
  crash or hang is found.
- Run the standalone benchmark harness after performance-sensitive changes to
  shared decode infrastructure, transaction behavior, or block behavior. Use
  prefixed selectors (for example,
  `./benchmarks/run -- --section transaction.deserialize.fixtures` or
  `./benchmarks/run -- --section block.compute-merkle-root`) to target a
  workload. Compare trends within the same machine, target, and runtime rather
  than treating absolute numbers as portable.

## Performance Considerations

- Enforce cheap size/count limits before allocating or recursing over large
  collections.
- Preserve fail-fast behavior for impossible counts, oversized scripts, oversized
  witness stacks, and cumulative witness payload limits.
- Avoid conversions that lose precision on JavaScript. Keep 64-bit and 256-bit
  values as byte-backed wrappers until a safe conversion is proven.
- Avoid quadratic (O(n^2)) list or `BitArray` work in parser hot paths.
  Accumulate lists in reverse and reverse once, as the parser helpers do.
- Keep recursive parser loops syntactically tail-recursive. Do not place the
  recursive call inside a `use` continuation, `result.try` callback, or other
  closure; the JavaScript backend cannot optimize hidden recursion and may
  exhaust the call stack. Pattern-match the `Result` directly and recurse from
  the successful branch.
- Do not silently relax default policy limits. They protect callers deserializing
  untrusted bytes even though some consensus-valid transactions may exceed them.
- Keep the default benchmark suite selective. Add benchmark rows only when they
  cover a distinct public operation, scaling dimension, fail-fast path, or
  transaction shape not already represented.
