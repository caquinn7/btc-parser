//// Performance benchmarks for the public `btc_parser/block` workflows.
////
//// Block inputs are constructed and deserialized before timing begins so each
//// timed row measures only the named block operation.

import btc_parser/block.{type Block, type Parsed}
import btc_parser/transaction.{type Transaction}
import btc_parser_benchmarks/internal/benchmark.{
  type PerfCaseInput, type PerfCaseResult, type PerfMeasurementConfig,
  type PerfSectionDefinition, MeasurementCurvePoint, PerfCaseInput,
  PerfMeasurementConfig, PerfSectionDefinition, measure_cases, measure_curve,
}
import btc_parser_benchmarks/internal/bitcoin_wire.{compact_size}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/string
import simplifile

/// Returns concrete block benchmark sections in their domain-defined order.
pub fn section_definitions() -> List(PerfSectionDefinition) {
  [
    PerfSectionDefinition(
      "block.compute-merkle-root.fixtures",
      measure_fixture_merkle_root,
    ),
    PerfSectionDefinition(
      "block.compute-merkle-root.synthetic-transactions",
      measure_synthetic_transaction_merkle_root,
    ),
  ]
}

fn measure_fixture_merkle_root() -> List(PerfCaseResult) {
  measure_cases(
    [mainnet_898064_block_case()],
    measurement_config(1),
    "compute_merkle_root",
    block.compute_merkle_root,
  )
}

fn mainnet_898064_block_case() -> PerfCaseInput(Block(Parsed)) {
  let mainnet_898064_tx_count = 2450
  let mainnet_898064_legacy_tx_count = 218
  let mainnet_898064_segwit_tx_count = 2232
  let mainnet_898064_total_size = 1_576_176
  let mainnet_898064_base_size = 805_947

  let assert Ok(fixture_hex) =
    simplifile.read("fixtures/block/mainnet-898064.hex")
  let assert Ok(block_bytes) =
    fixture_hex
    |> string.trim
    |> bit_array.base16_decode

  assert bit_array.byte_size(block_bytes) == mainnet_898064_total_size

  let assert Ok(parsed_block) = block.deserialize(block_bytes)
  assert block.get_transaction_count(parsed_block) == mainnet_898064_tx_count
  assert block.compute_base_size(parsed_block) == mainnet_898064_base_size
  assert block.compute_total_size(parsed_block) == mainnet_898064_total_size

  let transactions = block.get_transactions(parsed_block)
  let #(legacy_count, segwit_count) = count_transaction_encodings(transactions)

  assert legacy_count == mainnet_898064_legacy_tx_count
  assert segwit_count == mainnet_898064_segwit_tx_count

  let #(computed_root, mutated) = block.compute_merkle_root(parsed_block)
  let header_root =
    parsed_block
    |> block.get_header
    |> block.get_header_merkle_root

  assert computed_root == header_root
  assert !mutated

  PerfCaseInput(
    "mainnet block=898064 transactions=2450 base_size=805947",
    bit_array.byte_size(block_bytes),
    parsed_block,
  )
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

fn measure_synthetic_transaction_merkle_root() -> List(PerfCaseResult) {
  measure_curve(
    [
      MeasurementCurvePoint([1], measurement_config(100)),
      MeasurementCurvePoint([100], measurement_config(10)),
      MeasurementCurvePoint([1000], measurement_config(1)),
    ],
    list.map(_, synthetic_transaction_block_case),
    "compute_merkle_root",
    block.compute_merkle_root,
  )
}

fn synthetic_transaction_block_case(
  transaction_count: Int,
) -> PerfCaseInput(Block(Parsed)) {
  let tx_bytes = build_unique_minimal_legacy_transactions(transaction_count)
  let block_bytes = <<
    0:size(640),
    compact_size(transaction_count):bits,
    bit_array.concat(tx_bytes):bits,
  >>

  let assert Ok(parsed_block) = block.deserialize(block_bytes)
  assert block.get_transaction_count(parsed_block) == transaction_count

  let #(root, mutated) = block.compute_merkle_root(parsed_block)
  assert bit_array.byte_size(root) == 32
  assert !mutated

  PerfCaseInput(
    "synthetic legacy transactions=" <> int.to_string(transaction_count),
    bit_array.byte_size(block_bytes),
    parsed_block,
  )
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

fn measurement_config(operations_per_timed_call: Int) -> PerfMeasurementConfig {
  PerfMeasurementConfig(
    operations_per_timed_call:,
    warmup_ms: 250,
    duration_ms: 1000,
  )
}
