//// Fuzz testing harness for the `btc_parser/block` block parser.
////
//// The harness mutates complete mainnet blocks and exercises block
//// deserialization and its related public APIs. Any byte input must result in
//// either a successful operation or a defined error, never an unhandled
//// exception.

import btc_parser/block.{type PowLimit}
import btc_parser_fuzz/fuzz_result.{type FuzzResult, FuzzResult}
import btc_parser_fuzz/internal/mutation
import btc_parser_fuzz/internal/rng.{type Rng}
import btc_parser_fuzz/internal/trace.{type Trace}
import exception.{type Exception}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/string

/// Details for one fuzz iteration that raised an unhandled exception.
pub type IterationFailure {
  IterationFailure(
    /// One-based iteration number within the fuzz run.
    iteration: Int,
    /// Seed block, mutation kind, and resulting bytes for this failure.
    mutated_block: MutatedBlock,
    /// Hex-encoded mutated block bytes for copying into regression tests.
    mutated_block_hex: String,
    /// Exception rescued while deserializing, validating, inspecting,
    /// serializing, or hashing the mutated block.
    exception: Exception,
  )
}

/// Block bytes produced by applying a mutation to one corpus seed.
pub type MutatedBlock {
  MutatedBlock(
    /// Original corpus block selected for this iteration.
    seed_block: SeedBlock,
    /// Structural mutation applied to the original block bytes.
    mutation: Mutation,
    /// Mutated wire bytes passed into the parser pipeline.
    bytes: BitArray,
  )
}

/// Corpus block used as a baseline for structural mutation.
pub type SeedBlock {
  SeedBlock(
    /// Display-format block hash recorded in the seed corpus, not the
    /// little-endian block-hash byte order used on the wire.
    block_hash: String,
    /// Raw wire bytes decoded from the corpus entry.
    bytes: BitArray,
  )
}

/// Mutation strategy selected for a fuzz iteration.
pub type Mutation {
  /// Cut the byte stream at a random position and discard the tail.
  Truncate
  /// Replace a small number of bytes with random byte values.
  FlipBytes
  /// Toggle a small number of individual bits.
  FlipBits
  /// Insert a short random byte sequence at a random position.
  InsertBytes
  /// Remove a short contiguous byte span.
  DeleteSpan
  /// Copy a short byte span and insert the copy elsewhere.
  DuplicateSpan
  /// Replace a short byte span with zero bytes of the same length.
  ZeroSpan
  /// Mutate a heuristic CompactSize candidate in the byte stream.
  MutateCompactSizeCandidate
  /// Mutate the block transaction-count CompactSize at byte offset 80.
  MutateTransactionCount
}

/// Runs the block fuzz harness and returns failures plus reproducibility metadata.
pub fn run(
  seed_blocks: List(SeedBlock),
  iteration_count: Int,
  rng: Rng,
) -> FuzzResult(IterationFailure) {
  let rng_state = rng.state(rng)
  let pow_limit = mainnet_pow_limit()

  let #(failures, trace) =
    run_iterations(
      seed_blocks,
      iteration_count,
      1,
      [],
      trace.new(),
      rng,
      pow_limit,
    )

  FuzzResult(
    iteration_count:,
    initial_rng_state: rng_state,
    trace_hash: trace.to_hex(trace),
    failures: list.reverse(failures),
  )
}

/// Parses seed corpus file contents into blocks for the fuzz harness.
///
/// Each accepted line has the pipe-delimited form `block_hash|codes|hex`, where
/// `block_hash` is kept as a display-format identifier and `hex` is decoded into
/// raw block wire bytes. Lines that do not match that shape are ignored.
pub fn parse_seed_blocks(file_content: String) -> List(SeedBlock) {
  file_content
  |> string.split("\n")
  |> list.filter_map(fn(line) {
    case string.split(line, "|") {
      [block_hash, _codes, hex_str] -> {
        let assert Ok(bytes) = bit_array.base16_decode(hex_str)
        Ok(SeedBlock(block_hash:, bytes:))
      }
      _ -> Error(Nil)
    }
  })
}

/// Formats an iteration failure for the fuzz report.
pub fn iteration_failure_to_string(failure: IterationFailure) -> String {
  "  #"
  <> int.to_string(failure.iteration)
  <> "\n    seed_block: "
  <> failure.mutated_block.seed_block.block_hash
  <> "\n    mutation: "
  <> string.inspect(failure.mutated_block.mutation)
  <> "\n    hex: "
  <> failure.mutated_block_hex
  <> "\n    exception: "
  <> string.inspect(failure.exception)
}

fn run_iterations(
  blocks: List(SeedBlock),
  remaining: Int,
  iteration: Int,
  acc: List(IterationFailure),
  trace: Trace,
  rng: Rng,
  pow_limit: PowLimit,
) -> #(List(IterationFailure), Trace) {
  case remaining == 0 {
    True -> #(acc, trace)
    False -> {
      let assert Ok(#(seed_block, rng)) = rng.sample_one(rng, from: blocks)
      let #(mutated_block, rng) = mutate(seed_block, rng)
      let trace = trace.update(trace, mutated_block.bytes)

      let iteration_result =
        exception.rescue(fn() {
          run_deserialize(mutated_block.bytes, pow_limit)
        })

      let acc = case iteration_result {
        Ok(_) -> acc
        Error(exception) -> [
          IterationFailure(
            iteration:,
            mutated_block:,
            mutated_block_hex: bit_array.base16_encode(mutated_block.bytes),
            exception:,
          ),
          ..acc
        ]
      }

      run_iterations(
        blocks,
        remaining - 1,
        iteration + 1,
        acc,
        trace,
        rng,
        pow_limit,
      )
    }
  }
}

fn run_deserialize(mutated_block_bytes: BitArray, pow_limit: PowLimit) -> Nil {
  case block.deserialize(mutated_block_bytes) {
    Ok(parsed_block) -> {
      let _ = block.validate_context_free_consensus(parsed_block, pow_limit)

      let header = block.get_header(parsed_block)
      let _ = block.get_header_version(header)
      let previous_block_hash = block.get_header_previous_block_hash(header)
      let recorded_merkle_root = block.get_header_merkle_root(header)
      let _ = block.get_header_timestamp(header)
      let _ = block.get_header_target(header)
      let _ = block.get_header_nonce(header)

      let transactions = block.get_transactions(parsed_block)
      assert block.get_transaction_count(parsed_block)
        == list.length(transactions)

      let base_size = block.compute_base_size(parsed_block)
      let total_size = block.compute_total_size(parsed_block)
      assert total_size == bit_array.byte_size(mutated_block_bytes)
      assert block.compute_weight(parsed_block) == base_size * 3 + total_size
      assert block.serialize(parsed_block) == mutated_block_bytes

      let serialized_header = block.serialize_header(header)
      let block_hash = block.compute_block_hash(parsed_block)
      let #(computed_merkle_root, _) = block.compute_merkle_root(parsed_block)

      assert bit_array.byte_size(serialized_header) == 80
      assert bit_array.byte_size(previous_block_hash) == 32
      assert bit_array.byte_size(block_hash) == 32
      assert bit_array.byte_size(recorded_merkle_root) == 32
      assert bit_array.byte_size(computed_merkle_root) == 32

      Nil
    }

    Error(_) -> Nil
  }
}

fn mutate(seed_block: SeedBlock, rng: Rng) -> #(MutatedBlock, Rng) {
  let mutations = [
    #(Truncate, mutation.truncate),
    #(FlipBytes, mutation.flip_bytes),
    #(FlipBits, mutation.flip_bits),
    #(InsertBytes, mutation.insert_bytes),
    #(DeleteSpan, mutation.delete_span),
    #(DuplicateSpan, mutation.duplicate_span),
    #(ZeroSpan, mutation.zero_span),
    #(
      MutateCompactSizeCandidate,
      mutation.mutate_heuristic_compact_size_candidate,
    ),
    #(MutateTransactionCount, fn(bytes, rng) {
      mutation.mutate_compact_size_at(bytes, 80, rng)
    }),
  ]

  let assert Ok(#(#(mutation, mutation_fn), rng)) =
    rng.sample_one(rng, mutations)

  let #(mutated_bytes, rng) = mutation_fn(seed_block.bytes, rng)
  #(MutatedBlock(seed_block:, mutation:, bytes: mutated_bytes), rng)
}

fn mainnet_pow_limit() -> PowLimit {
  let assert Ok(pow_limit) = block.new_pow_limit(<<0:208, 0xFF, 0xFF, 0:32>>)

  pow_limit
}
