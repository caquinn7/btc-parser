//// Fuzz testing harness for the `btc_parser/block` block parser.
////
//// The harness mutates complete mainnet blocks and exercises block
//// deserialization and its related public APIs. Any byte input must result in
//// either a successful operation or a defined error, never an unhandled
//// exception.

import btc_parser/block.{
  type PowLimit, MaxBlockSize, MaxTransactionCount, PolicyLimitExceeded,
}
import btc_parser/transaction
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
  /// Mutate one complete transaction while leaving the enclosing block structure.
  MutateContainedTransaction(Int, ContainedTransactionMutation)
  /// Remove one complete transaction and decrement the encoded transaction count.
  RemoveTransaction(Int)
  /// Duplicate one complete transaction and increment the encoded transaction count.
  DuplicateTransaction(Int)
}

/// Byte-level mutation applied to one transaction contained in a block.
pub type ContainedTransactionMutation {
  /// Cut the contained transaction at a random position and discard the tail.
  ContainedTruncate
  /// Replace a small number of contained-transaction bytes with random values.
  ContainedFlipBytes
  /// Toggle a small number of individual contained-transaction bits.
  ContainedFlipBits
  /// Insert a short random byte sequence into the contained transaction.
  ContainedInsertBytes
  /// Remove a short contiguous byte span from the contained transaction.
  ContainedDeleteSpan
  /// Copy a short contained-transaction byte span and insert the copy elsewhere.
  ContainedDuplicateSpan
  /// Replace a short contained-transaction byte span with zero bytes.
  ContainedZeroSpan
  /// Mutate a heuristic CompactSize candidate in the contained transaction.
  ContainedMutateCompactSizeCandidate
}

/// Trusted corpus data prepared once before the fuzz loop starts.
///
/// This representation keeps only public-API-derived transaction boundaries,
/// so structure-aware mutations do not need to reparse the corpus block.
type PreparedSeedBlock {
  PreparedSeedBlock(
    seed_block: SeedBlock,
    transaction_count: Int,
    transaction_count_width: Int,
    header_and_count_prefix: BitArray,
    transaction_bytes: List(BitArray),
  )
}

/// An entry in the fixed mutation registry.
type MutationStrategy {
  WholeBlockMutation(Mutation, fn(BitArray, Rng) -> #(BitArray, Rng))
  ContainedTransactionStrategy
  RemoveTransactionStrategy
  DuplicateTransactionStrategy
}

/// Runs the block fuzz harness and returns failures plus reproducibility metadata.
pub fn run(
  seed_blocks: List(SeedBlock),
  iteration_count: Int,
  rng: Rng,
) -> FuzzResult(IterationFailure) {
  let rng_state = rng.state(rng)
  let pow_limit = mainnet_pow_limit()
  let prepared_seed_blocks = prepare_seed_blocks(seed_blocks)

  let #(failures, trace) =
    run_iterations(
      prepared_seed_blocks,
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
  blocks: List(PreparedSeedBlock),
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
      let assert Ok(#(prepared_seed_block, rng)) =
        rng.sample_one(rng, from: blocks)
      let #(mutated_block, rng) = mutate(prepared_seed_block, rng)
      let trace = trace.update(trace, mutated_block.bytes)

      let iteration_result =
        exception.rescue(fn() {
          run_deserialize(
            mutated_block.bytes,
            mutated_block.mutation,
            pow_limit,
          )
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

fn run_deserialize(
  mutated_block_bytes: BitArray,
  selected_mutation: Mutation,
  pow_limit: PowLimit,
) -> Nil {
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

      let txs = block.get_transactions(parsed_block)
      assert block.get_transaction_count(parsed_block) == list.length(txs)

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

    Error(error) -> {
      let panic_msg =
        "count-adjusted block mutation unexpectedly failed to deserialize: "
        <> string.inspect(error)

      case selected_mutation {
        RemoveTransaction(_) -> panic as panic_msg

        DuplicateTransaction(_) ->
          case block.get_decode_error_kind(error) {
            PolicyLimitExceeded(MaxBlockSize, _, _) -> Nil
            PolicyLimitExceeded(MaxTransactionCount, _, _) -> Nil
            _ -> panic as panic_msg
          }

        _ -> Nil
      }
    }
  }
}

fn prepare_seed_blocks(
  seed_blocks: List(SeedBlock),
) -> List(PreparedSeedBlock) {
  list.map(seed_blocks, prepare_seed_block)
}

fn prepare_seed_block(seed_block: SeedBlock) -> PreparedSeedBlock {
  let assert Ok(parsed_block) = block.deserialize(seed_block.bytes)
  let transaction_count = block.get_transaction_count(parsed_block)
  let transactions = block.get_transactions(parsed_block)
  let transaction_bytes = list.map(transactions, transaction.serialize)
  let transaction_count_width = compact_size_width(transaction_count)
  let serialized_block = block.serialize(parsed_block)

  assert transaction_count == list.length(transactions)
  assert serialized_block == seed_block.bytes

  let prefix_length = 80 + transaction_count_width
  let assert Ok(header_and_count_prefix) =
    bit_array.slice(seed_block.bytes, 0, prefix_length)
  assert bit_array.concat([header_and_count_prefix, ..transaction_bytes])
    == seed_block.bytes

  PreparedSeedBlock(
    seed_block:,
    transaction_count:,
    transaction_count_width:,
    header_and_count_prefix:,
    transaction_bytes:,
  )
}

fn compact_size_width(value: Int) -> Int {
  case value {
    v if v < 0 -> panic as "transaction count cannot be negative"
    v if v <= 252 -> 1
    v if v <= 65_535 -> 3
    v if v <= 4_294_967_295 -> 5
    _ -> 9
  }
}

fn mutate(
  prepared_seed_block: PreparedSeedBlock,
  rng: Rng,
) -> #(MutatedBlock, Rng) {
  let mutation_strategies = mutation_strategies(prepared_seed_block)
  let assert Ok(#(mutation_strategy, rng)) =
    rng.sample_one(rng, mutation_strategies)

  case mutation_strategy {
    WholeBlockMutation(mutation, mutation_fn) -> {
      let #(block_bytes, rng) =
        mutation_fn(prepared_seed_block.seed_block.bytes, rng)

      #(
        MutatedBlock(
          seed_block: prepared_seed_block.seed_block,
          mutation:,
          bytes: block_bytes,
        ),
        rng,
      )
    }

    ContainedTransactionStrategy ->
      mutate_contained_transaction(prepared_seed_block, rng)

    RemoveTransactionStrategy -> remove_transaction(prepared_seed_block, rng)

    DuplicateTransactionStrategy ->
      duplicate_transaction(prepared_seed_block, rng)
  }
}

fn mutation_strategies(
  prepared_seed_block: PreparedSeedBlock,
) -> List(MutationStrategy) {
  let whole_block_strategies = [
    WholeBlockMutation(Truncate, mutation.truncate),
    WholeBlockMutation(FlipBytes, mutation.flip_bytes),
    WholeBlockMutation(FlipBits, mutation.flip_bits),
    WholeBlockMutation(InsertBytes, mutation.insert_bytes),
    WholeBlockMutation(DeleteSpan, mutation.delete_span),
    WholeBlockMutation(DuplicateSpan, mutation.duplicate_span),
    WholeBlockMutation(ZeroSpan, mutation.zero_span),
    WholeBlockMutation(
      MutateCompactSizeCandidate,
      mutation.mutate_heuristic_compact_size_candidate,
    ),
    WholeBlockMutation(MutateTransactionCount, fn(bytes, rng) {
      mutation.mutate_compact_size_at(bytes, 80, rng)
    }),
  ]

  case prepared_seed_block.transaction_bytes {
    [] -> whole_block_strategies
    _ ->
      list.append(whole_block_strategies, [
        ContainedTransactionStrategy,
        RemoveTransactionStrategy,
        DuplicateTransactionStrategy,
      ])
  }
}

fn mutate_contained_transaction(
  prepared_seed_block: PreparedSeedBlock,
  rng: Rng,
) -> #(MutatedBlock, Rng) {
  let #(index, rng) = select_transaction_index(prepared_seed_block, rng)

  let assert Ok(selected_tx_bytes) =
    list.first(list.drop(prepared_seed_block.transaction_bytes, index))

  let contained_mutations = [
    #(ContainedTruncate, mutation.truncate),
    #(ContainedFlipBytes, mutation.flip_bytes),
    #(ContainedFlipBits, mutation.flip_bits),
    #(ContainedInsertBytes, mutation.insert_bytes),
    #(ContainedDeleteSpan, mutation.delete_span),
    #(ContainedDuplicateSpan, mutation.duplicate_span),
    #(ContainedZeroSpan, mutation.zero_span),
    #(
      ContainedMutateCompactSizeCandidate,
      mutation.mutate_heuristic_compact_size_candidate,
    ),
  ]

  let assert Ok(#(#(contained_mutation, contained_mutation_fn), rng)) =
    rng.sample_one(rng, contained_mutations)

  let #(mutated_tx_bytes, rng) = contained_mutation_fn(selected_tx_bytes, rng)

  let updated_txs_bytes =
    edit_transaction_bytes(prepared_seed_block.transaction_bytes, index, fn(_) {
      [mutated_tx_bytes]
    })

  let block_bytes =
    rebuild_block(
      prepared_seed_block.header_and_count_prefix,
      updated_txs_bytes,
    )

  #(
    MutatedBlock(
      seed_block: prepared_seed_block.seed_block,
      mutation: MutateContainedTransaction(index, contained_mutation),
      bytes: block_bytes,
    ),
    rng,
  )
}

fn remove_transaction(
  prepared_seed_block: PreparedSeedBlock,
  rng: Rng,
) -> #(MutatedBlock, Rng) {
  let #(index, rng) = select_transaction_index(prepared_seed_block, rng)
  let tx_bytes =
    edit_transaction_bytes(prepared_seed_block.transaction_bytes, index, fn(_) {
      []
    })
  let header_and_count_prefix =
    rewrite_transaction_count(
      prepared_seed_block,
      prepared_seed_block.transaction_count - 1,
    )
  let block_bytes = rebuild_block(header_and_count_prefix, tx_bytes)

  #(
    MutatedBlock(
      seed_block: prepared_seed_block.seed_block,
      mutation: RemoveTransaction(index),
      bytes: block_bytes,
    ),
    rng,
  )
}

fn duplicate_transaction(
  prepared_seed_block: PreparedSeedBlock,
  rng: Rng,
) -> #(MutatedBlock, Rng) {
  let #(index, rng) = select_transaction_index(prepared_seed_block, rng)
  let tx_bytes =
    edit_transaction_bytes(
      prepared_seed_block.transaction_bytes,
      index,
      fn(bytes) { [bytes, bytes] },
    )
  let header_and_count_prefix =
    rewrite_transaction_count(
      prepared_seed_block,
      prepared_seed_block.transaction_count + 1,
    )
  let block_bytes = rebuild_block(header_and_count_prefix, tx_bytes)

  #(
    MutatedBlock(
      seed_block: prepared_seed_block.seed_block,
      mutation: DuplicateTransaction(index),
      bytes: block_bytes,
    ),
    rng,
  )
}

fn select_transaction_index(
  prepared_seed_block: PreparedSeedBlock,
  rng: Rng,
) -> #(Int, Rng) {
  assert prepared_seed_block.transaction_count > 0
  rng.next_bounded(rng, prepared_seed_block.transaction_count)
}

fn rewrite_transaction_count(
  prepared_seed_block: PreparedSeedBlock,
  tx_count: Int,
) -> BitArray {
  mutation.rewrite_compact_size(
    prepared_seed_block.header_and_count_prefix,
    mutation.CompactSizeCandidate(
      start: 80,
      width: prepared_seed_block.transaction_count_width,
      value: prepared_seed_block.transaction_count,
    ),
    tx_count,
  )
}

fn rebuild_block(
  header_and_count_prefix: BitArray,
  txs_bytes: List(BitArray),
) -> BitArray {
  bit_array.concat([header_and_count_prefix, ..txs_bytes])
}

fn edit_transaction_bytes(
  txs_bytes: List(BitArray),
  index: Int,
  edit: fn(BitArray) -> List(BitArray),
) -> List(BitArray) {
  edit_transaction_bytes_loop(txs_bytes, index, 0, edit, [])
}

fn edit_transaction_bytes_loop(
  txs_bytes: List(BitArray),
  index: Int,
  current_index: Int,
  edit: fn(BitArray) -> List(BitArray),
  acc: List(BitArray),
) -> List(BitArray) {
  case txs_bytes {
    [] -> list.reverse(acc)

    [bytes, ..rest] -> {
      let acc = case current_index == index {
        True ->
          list.fold(edit(bytes), acc, fn(acc, tx_bytes) { [tx_bytes, ..acc] })

        False -> [bytes, ..acc]
      }
      edit_transaction_bytes_loop(rest, index, current_index + 1, edit, acc)
    }
  }
}

fn mainnet_pow_limit() -> PowLimit {
  let assert Ok(pow_limit) = block.new_pow_limit(<<0:208, 0xFF, 0xFF, 0:32>>)
  pow_limit
}
