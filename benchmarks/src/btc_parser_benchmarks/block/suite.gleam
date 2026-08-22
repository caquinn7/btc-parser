//// Performance benchmarks for the public `btc_parser/block` workflows.
////
//// The suite measures repeated operations that callers are expected to pay for:
//// deserialization, block size and weight calculation, Merkle-root
//// calculation, context-free consensus validation, and serialization. Fixture
//// loading and hex decoding, synthetic transaction and header construction,
//// proof-of-work setup and mining, and preflight assertions are intentionally
//// performed before timing begins. Rows that take parsed blocks are
//// deserialized during setup; deserialization rows time that work directly.
////
//// Benchmark cases run one or more logical operations per timed call. Fast
//// cases use larger batches to reduce timer overhead; slower cases use smaller
//// batches, down to one operation per timed call. Reported throughput and
//// latency are converted back to one logical operation, such as one
//// `deserialize`, `compute_weight`, or
//// `validate_context_free_consensus` call.

import btc_parser/block.{type Block, type Parsed, type PowLimit}
import btc_parser/transaction.{type Transaction}
import btc_parser_benchmarks/internal/benchmark.{
  type MeasurementCurvePoint, type PerfCaseInput, type PerfCaseResult,
  type PerfMeasurementConfig, type PerfSectionDefinition, MeasurementCurvePoint,
  PerfCaseInput, PerfMeasurementConfig, PerfSectionDefinition, measure_cases,
  measure_curve,
}
import btc_parser_benchmarks/internal/bitcoin_wire.{compact_size}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/string
import simplifile

const mainnet_898064_total_size = 1_576_176

const mainnet_898064_label = "mainnet block=898064 transactions=2450 base_size=805947"

const regtest_compact_target = 0x207FFFFF

type PreparedBlock {
  PreparedBlock(bytes: BitArray, parsed_block: Block(Parsed))
}

/// Returns concrete block benchmark sections in workflow order: deserialize,
/// size-and-weight, Merkle-root, context-free validation, then serialization.
pub fn section_definitions() -> List(PerfSectionDefinition) {
  [
    PerfSectionDefinition(
      "block.deserialize.fixtures",
      measure_fixture_block_deserialize,
    ),
    PerfSectionDefinition(
      "block.deserialize.synthetic-transactions",
      measure_synthetic_transaction_block_deserialize,
    ),
    PerfSectionDefinition(
      "block.size-and-weight.fixtures",
      measure_fixture_block_size_and_weight,
    ),
    PerfSectionDefinition(
      "block.size-and-weight.synthetic-transactions",
      measure_synthetic_transaction_block_size_and_weight,
    ),
    PerfSectionDefinition(
      "block.compute-merkle-root.fixtures",
      measure_fixture_merkle_root,
    ),
    PerfSectionDefinition(
      "block.compute-merkle-root.synthetic-transactions",
      measure_synthetic_transaction_merkle_root,
    ),
    PerfSectionDefinition(
      "block.validate-context-free-consensus.fixtures",
      measure_fixture_context_free_consensus_validation,
    ),
    PerfSectionDefinition(
      "block.validate-context-free-consensus.synthetic-transactions",
      measure_synthetic_transaction_context_free_consensus_validation,
    ),
    PerfSectionDefinition(
      "block.serialize.fixtures",
      measure_fixture_block_serialization,
    ),
    PerfSectionDefinition(
      "block.serialize.synthetic-transactions",
      measure_synthetic_transaction_block_serialization,
    ),
  ]
}

// ==============================================================================
// Block deserialization
// ==============================================================================

fn measure_fixture_block_deserialize() -> List(PerfCaseResult) {
  measure_cases(
    [mainnet_898064_deserialize_case()],
    measurement_config(1),
    "deserialize",
    block.deserialize,
  )
}

fn measure_synthetic_transaction_block_deserialize() -> List(PerfCaseResult) {
  measure_curve(
    synthetic_transaction_curve(),
    list.map(_, synthetic_transaction_deserialize_case),
    "deserialize",
    block.deserialize,
  )
}

fn mainnet_898064_deserialize_case() -> PerfCaseInput(BitArray) {
  let block_bytes = mainnet_898064_block_bytes()
  let _ = mainnet_898064_parsed_block(block_bytes)

  PerfCaseInput(
    mainnet_898064_label,
    bit_array.byte_size(block_bytes),
    block_bytes,
  )
}

fn synthetic_transaction_deserialize_case(
  transaction_count: Int,
) -> PerfCaseInput(BitArray) {
  let PreparedBlock(block_bytes, _) =
    synthetic_transaction_prepared_block(transaction_count)

  PerfCaseInput(
    synthetic_transaction_label(transaction_count),
    bit_array.byte_size(block_bytes),
    block_bytes,
  )
}

// ==============================================================================
// Block size and weight
// ==============================================================================

fn measure_fixture_block_size_and_weight() -> List(PerfCaseResult) {
  measure_size_and_weight_cases(
    [mainnet_898064_block_case()],
    measurement_config(10),
  )
}

fn measure_synthetic_transaction_block_size_and_weight() -> List(PerfCaseResult) {
  measure_size_and_weight_curve([
    MeasurementCurvePoint([1, 10], measurement_config(1000)),
    MeasurementCurvePoint([100], measurement_config(100)),
    MeasurementCurvePoint([1000], measurement_config(10)),
  ])
}

fn measure_size_and_weight_curve(
  curve: List(MeasurementCurvePoint),
) -> List(PerfCaseResult) {
  curve
  |> list.flat_map(fn(point) {
    let MeasurementCurvePoint(tx_counts, config) = point
    let inputs = list.map(tx_counts, synthetic_transaction_block_case)
    measure_size_and_weight_cases(inputs, config)
  })
}

fn measure_size_and_weight_cases(
  inputs: List(PerfCaseInput(Block(Parsed))),
  config: PerfMeasurementConfig,
) -> List(PerfCaseResult) {
  [
    measure_cases(inputs, config, "compute_base_size", block.compute_base_size),
    measure_cases(
      inputs,
      config,
      "compute_total_size",
      block.compute_total_size,
    ),
    measure_cases(inputs, config, "compute_weight", block.compute_weight),
  ]
  |> list.flatten
}

// ==============================================================================
// Block Merkle root
// ==============================================================================

fn measure_fixture_merkle_root() -> List(PerfCaseResult) {
  measure_cases(
    [mainnet_898064_block_case()],
    measurement_config(1),
    "compute_merkle_root",
    block.compute_merkle_root,
  )
}

fn measure_synthetic_transaction_merkle_root() -> List(PerfCaseResult) {
  measure_curve(
    synthetic_transaction_curve(),
    list.map(_, synthetic_transaction_block_case),
    "compute_merkle_root",
    block.compute_merkle_root,
  )
}

// ==============================================================================
// Block context-free consensus validation
// ==============================================================================

fn measure_fixture_context_free_consensus_validation() -> List(PerfCaseResult) {
  let pow_limit = mainnet_pow_limit()

  measure_cases(
    [mainnet_898064_block_case()],
    measurement_config(1),
    "validate_context_free_consensus",
    block.validate_context_free_consensus(_, pow_limit),
  )
}

fn measure_synthetic_transaction_context_free_consensus_validation() -> List(
  PerfCaseResult,
) {
  let pow_limit = regtest_pow_limit()

  measure_curve(
    synthetic_transaction_curve(),
    fn(tx_counts) {
      list.map(tx_counts, validation_synthetic_transaction_block_case(
        _,
        pow_limit,
      ))
    },
    "validate_context_free_consensus",
    block.validate_context_free_consensus(_, pow_limit),
  )
}

fn validation_synthetic_transaction_block_case(
  tx_count: Int,
  pow_limit: PowLimit,
) -> PerfCaseInput(Block(Parsed)) {
  let block_bytes = build_validation_synthetic_block_bytes(tx_count)
  let assert Ok(parsed_block) = block.deserialize(block_bytes)

  assert block.get_transaction_count(parsed_block) == tx_count
  assert block.serialize(parsed_block) == block_bytes
  assert block.get_header_target(block.get_header(parsed_block))
    == regtest_compact_target

  let #(computed_root, mutated) = block.compute_merkle_root(parsed_block)
  let header_root =
    parsed_block
    |> block.get_header
    |> block.get_header_merkle_root

  assert computed_root == header_root
  assert !mutated

  let block_hash = block.compute_block_hash(parsed_block)
  let assert <<_:bytes-size(31), most_significant_byte>> = block_hash
  assert most_significant_byte < 0x7F

  let assert Ok(_) =
    block.validate_context_free_consensus(parsed_block, pow_limit)

  PerfCaseInput(
    "synthetic valid legacy transactions=" <> int.to_string(tx_count),
    bit_array.byte_size(block_bytes),
    parsed_block,
  )
}

// ==============================================================================
// Block serialization
// ==============================================================================

fn measure_fixture_block_serialization() -> List(PerfCaseResult) {
  measure_cases(
    [mainnet_898064_block_case()],
    measurement_config(1),
    "serialize",
    block.serialize,
  )
}

fn measure_synthetic_transaction_block_serialization() -> List(PerfCaseResult) {
  measure_curve(
    synthetic_transaction_curve(),
    list.map(_, synthetic_transaction_block_case),
    "serialize",
    block.serialize,
  )
}

// ==============================================================================
// Shared fixture setup
// ==============================================================================

fn mainnet_898064_block_case() -> PerfCaseInput(Block(Parsed)) {
  let block_bytes = mainnet_898064_block_bytes()
  let parsed_block = mainnet_898064_parsed_block(block_bytes)

  PerfCaseInput(
    mainnet_898064_label,
    bit_array.byte_size(block_bytes),
    parsed_block,
  )
}

fn mainnet_898064_block_bytes() -> BitArray {
  let assert Ok(fixture_hex) =
    simplifile.read("fixtures/block/mainnet-898064.hex")
  let assert Ok(block_bytes) =
    fixture_hex
    |> string.trim
    |> bit_array.base16_decode

  assert bit_array.byte_size(block_bytes) == mainnet_898064_total_size
  block_bytes
}

fn mainnet_898064_parsed_block(block_bytes: BitArray) -> Block(Parsed) {
  let assert Ok(parsed_block) = block.deserialize(block_bytes)

  assert block.get_transaction_count(parsed_block) == 2450
  assert block.compute_base_size(parsed_block) == 805_947
  assert block.compute_total_size(parsed_block) == mainnet_898064_total_size
  assert block.compute_weight(parsed_block) == 3_994_017
  assert block.serialize(parsed_block) == block_bytes

  let transactions = block.get_transactions(parsed_block)
  let #(legacy_count, segwit_count) = count_transaction_encodings(transactions)

  assert legacy_count == 218
  assert segwit_count == 2232

  let #(computed_root, mutated) = block.compute_merkle_root(parsed_block)
  let header_root =
    parsed_block
    |> block.get_header
    |> block.get_header_merkle_root

  assert computed_root == header_root
  assert !mutated

  let assert Ok(_) =
    block.validate_context_free_consensus(parsed_block, mainnet_pow_limit())

  parsed_block
}

fn count_transaction_encodings(txs: List(Transaction(s))) -> #(Int, Int) {
  list.fold(txs, #(0, 0), fn(counts, tx) {
    let #(legacy_count, segwit_count) = counts

    case transaction.is_segwit(tx) {
      True -> #(legacy_count, segwit_count + 1)
      False -> #(legacy_count + 1, segwit_count)
    }
  })
}

fn mainnet_pow_limit() -> PowLimit {
  let least_significant_bytes = bit_array.concat(list.repeat(<<0xFF>>, 28))
  let assert Ok(pow_limit) =
    block.new_pow_limit(<<least_significant_bytes:bits, 0:32>>)

  pow_limit
}

// ==============================================================================
// Shared structural synthetic blocks
// ==============================================================================

fn synthetic_transaction_curve() -> List(MeasurementCurvePoint) {
  [
    MeasurementCurvePoint([1, 10], measurement_config(100)),
    MeasurementCurvePoint([100], measurement_config(10)),
    MeasurementCurvePoint([1000], measurement_config(1)),
  ]
}

fn synthetic_transaction_block_case(
  tx_count: Int,
) -> PerfCaseInput(Block(Parsed)) {
  let PreparedBlock(block_bytes, parsed_block) =
    synthetic_transaction_prepared_block(tx_count)

  PerfCaseInput(
    synthetic_transaction_label(tx_count),
    bit_array.byte_size(block_bytes),
    parsed_block,
  )
}

fn synthetic_transaction_prepared_block(tx_count: Int) -> PreparedBlock {
  let tx_bytes = build_unique_minimal_legacy_transactions(tx_count)
  let block_bytes = <<
    0:size(640),
    compact_size(tx_count):bits,
    bit_array.concat(tx_bytes):bits,
  >>

  let assert Ok(parsed_block) = block.deserialize(block_bytes)
  let total_size = block.compute_total_size(parsed_block)
  let base_size = block.compute_base_size(parsed_block)

  assert block.get_transaction_count(parsed_block) == tx_count
  assert total_size == bit_array.byte_size(block_bytes)
  assert block.serialize(parsed_block) == block_bytes
  assert base_size == total_size
  assert block.compute_weight(parsed_block) == total_size * 4

  let #(root, mutated) = block.compute_merkle_root(parsed_block)
  assert bit_array.byte_size(root) == 32
  assert !mutated

  PreparedBlock(block_bytes, parsed_block)
}

fn synthetic_transaction_label(transaction_count: Int) -> String {
  "synthetic legacy transactions=" <> int.to_string(transaction_count)
}

fn build_unique_minimal_legacy_transactions(count: Int) -> List(BitArray) {
  build_unique_minimal_legacy_transactions_loop(1, count, [])
}

fn build_unique_minimal_legacy_transactions_loop(
  version: Int,
  count: Int,
  acc: List(BitArray),
) -> List(BitArray) {
  case version > count {
    True -> list.reverse(acc)
    False -> {
      let acc = [build_minimal_legacy_transaction(version), ..acc]
      build_unique_minimal_legacy_transactions_loop(version + 1, count, acc)
    }
  }
}

fn build_minimal_legacy_transaction(version: Int) -> BitArray {
  <<
    version:little-size(32),
    compact_size(1):bits,
    0:size(256),
    0:little-size(32),
    compact_size(0):bits,
    0:little-size(32),
    compact_size(1):bits,
    0:little-size(64),
    compact_size(0):bits,
    0:little-size(32),
  >>
}

// ==============================================================================
// Validation synthetic blocks
// ==============================================================================

fn build_validation_synthetic_block_bytes(tx_count: Int) -> BitArray {
  let txs = [
    build_valid_minimal_coinbase_legacy_transaction(),
    ..build_unique_minimal_legacy_transactions(tx_count - 1)
  ]
  let transaction_payload = bit_array.concat(txs)
  let provisional_block_bytes = <<
    build_regtest_header(<<0:256>>, 0):bits,
    compact_size(tx_count):bits,
    transaction_payload:bits,
  >>
  let assert Ok(provisional_block) = block.deserialize(provisional_block_bytes)
  let #(merkle_root, mutated) = block.compute_merkle_root(provisional_block)

  assert !mutated

  let header = mine_regtest_header(merkle_root, 0)

  <<
    header:bits,
    compact_size(tx_count):bits,
    transaction_payload:bits,
  >>
}

fn build_valid_minimal_coinbase_legacy_transaction() -> BitArray {
  <<
    1:little-size(32),
    compact_size(1):bits,
    0:size(256),
    0xFFFFFFFF:little-size(32),
    compact_size(2):bits,
    0x00,
    0x01,
    0:little-size(32),
    compact_size(1):bits,
    0:little-size(64),
    compact_size(0):bits,
    0:little-size(32),
  >>
}

fn mine_regtest_header(merkle_root: BitArray, nonce: Int) -> BitArray {
  let max_block_header_nonce = 4_294_967_295
  case nonce > max_block_header_nonce {
    True ->
      panic as "regtest proof-of-work search exhausted the 32-bit nonce range"

    False -> {
      let header = build_regtest_header(merkle_root, nonce)
      let assert Ok(header_block) = block.deserialize(<<header:bits, 0>>)
      let header_hash = block.compute_block_hash(header_block)
      let assert <<_:bytes-size(31), most_significant_byte>> = header_hash

      case most_significant_byte < 0x7F {
        True -> header
        False -> mine_regtest_header(merkle_root, nonce + 1)
      }
    }
  }
}

fn build_regtest_header(merkle_root: BitArray, nonce: Int) -> BitArray {
  <<
    0:little-size(32),
    0:size(256),
    merkle_root:bits,
    0:little-size(32),
    regtest_compact_target:little-size(32),
    nonce:little-size(32),
  >>
}

fn regtest_pow_limit() -> PowLimit {
  let least_significant_bytes = bit_array.concat(list.repeat(<<0xFF>>, 31))
  let assert Ok(pow_limit) =
    block.new_pow_limit(<<least_significant_bytes:bits, 0x7F>>)

  pow_limit
}

fn measurement_config(operations_per_timed_call: Int) -> PerfMeasurementConfig {
  PerfMeasurementConfig(
    operations_per_timed_call:,
    warmup_ms: 250,
    duration_ms: 1000,
  )
}
