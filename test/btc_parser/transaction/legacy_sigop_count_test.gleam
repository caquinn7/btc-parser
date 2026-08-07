import btc_parser/transaction
import gleam/bit_array
import gleam/list
import support/bitcoin_wire.{compact_size}
import support/transaction_wire.{
  assemble_segwit_transaction_bytes, build_input_bytes, build_output_bytes,
  repeat_byte, transaction_version_1_bytes,
}

// ============================================================================
// Basic counting and aggregation
// ============================================================================

pub fn legacy_sigop_count_for_empty_input_and_output_scripts_is_zero_test() {
  assert compute_legacy_sigop_count([<<>>], [<<>>]) == 0
}

pub fn legacy_sigop_count_aggregates_inputs_and_outputs_test() {
  assert compute_legacy_sigop_count([<<0xAC>>, <<0xAD>>], [<<0xAE>>, <<0xAF>>])
    == 42
}

pub fn legacy_sigop_count_ignores_non_sigop_opcodes_including_checksigadd_test() {
  assert compute_legacy_sigop_count([<<0x00, 0x51, 0x63, 0xBA>>], [
      <<0x68, 0x76, 0x87, 0x6A>>,
    ])
    == 0
}

pub fn legacy_sigop_count_counts_multisig_as_twenty_regardless_of_arity_test() {
  assert compute_legacy_sigop_count([<<>>], [<<0x52, 0xAE>>]) == 20
}

pub fn legacy_sigop_count_is_static_regardless_of_execution_branches_test() {
  assert compute_legacy_sigop_count([<<>>], [<<0x00, 0x63, 0xAC, 0x68>>]) == 1
}

// ============================================================================
// Valid push instructions
// ============================================================================

pub fn legacy_sigop_count_skips_direct_push_payloads_test() {
  let script = <<0xAC, 0x01, 0xAC, 0xAC>>
  assert compute_legacy_sigop_count([<<>>], [script]) == 2
}

pub fn legacy_sigop_count_skips_direct_push_payloads_of_maximum_length_test() {
  let pushed_sigops = repeat_byte(0xAC, 75)
  let script = <<0xAC, 75, pushed_sigops:bits, 0xAC>>

  assert compute_legacy_sigop_count([<<>>], [script]) == 2
}

pub fn legacy_sigop_count_skips_pushdata1_payloads_test() {
  // This is intentionally a non-minimal encoding for a one-byte push.
  let script = <<0xAC, 0x4C, 0x01, 0xAC, 0xAC>>
  assert compute_legacy_sigop_count([<<>>], [script]) == 2
}

pub fn legacy_sigop_count_skips_pushdata2_payloads_test() {
  let pushed_sigops = repeat_byte(0xAC, 256)
  let script = <<0xAC, 0x4D, 256:little-size(16), pushed_sigops:bits, 0xAC>>

  assert compute_legacy_sigop_count([<<>>], [script]) == 2
}

pub fn legacy_sigop_count_skips_pushdata4_payloads_test() {
  // This is intentionally a non-minimal encoding for a 256-byte push.
  let pushed_sigops = repeat_byte(0xAC, 256)
  let script = <<0xAC, 0x4E, 256:little-size(32), pushed_sigops:bits, 0xAC>>

  assert compute_legacy_sigop_count([<<>>], [script]) == 2
}

// ============================================================================
// Malformed push handling
// ============================================================================

pub fn legacy_sigop_count_stops_at_a_truncated_direct_push_test() {
  let script = <<0xAC, 0x02, 0xAC>>
  assert compute_legacy_sigop_count([<<>>], [script]) == 1
}

pub fn legacy_sigop_count_stops_at_an_incomplete_pushdata1_length_test() {
  let script = <<0xAC, 0x4C>>
  assert compute_legacy_sigop_count([<<>>], [script]) == 1
}

pub fn legacy_sigop_count_stops_at_a_truncated_pushdata1_payload_test() {
  let script = <<0xAC, 0x4C, 0x02, 0xAC>>
  assert compute_legacy_sigop_count([<<>>], [script]) == 1
}

pub fn legacy_sigop_count_stops_at_an_incomplete_pushdata2_length_test() {
  let script = <<0xAC, 0x4D, 0xAC>>
  assert compute_legacy_sigop_count([<<>>], [script]) == 1
}

pub fn legacy_sigop_count_stops_at_a_truncated_pushdata2_payload_test() {
  let script = <<0xAC, 0x4D, 0x02:little-size(16), 0xAC>>
  assert compute_legacy_sigop_count([<<>>], [script]) == 1
}

pub fn legacy_sigop_count_stops_at_an_incomplete_pushdata4_length_test() {
  let script = <<0xAC, 0x4E, 0xAC, 0xAC, 0xAC>>
  assert compute_legacy_sigop_count([<<>>], [script]) == 1
}

pub fn legacy_sigop_count_stops_at_a_truncated_pushdata4_payload_test() {
  let script = <<0xAC, 0x4E, 0x02:little-size(32), 0xAC>>
  assert compute_legacy_sigop_count([<<>>], [script]) == 1
}

// ============================================================================
// Witness exclusion and stack safety
// ============================================================================

pub fn legacy_sigop_count_ignores_witness_items_test() {
  let input = build_input_bytes(repeat_byte(0x01, 32), 0, <<0xAC>>, 0)
  let output = build_output_bytes(<<0:little-size(64)>>, <<>>)
  let witness_item = <<0xAC, 0xAD, 0xAE, 0xAF>>
  let witness_stack = <<
    compact_size(1):bits,
    compact_size(bit_array.byte_size(witness_item)):bits,
    witness_item:bits,
  >>
  let tx =
    deserialize_transaction(
      assemble_segwit_transaction_bytes([input], [output], [witness_stack]),
    )

  assert transaction.compute_legacy_sigop_count(tx) == 1
}

pub fn legacy_sigop_count_handles_ten_thousand_sigops_without_recursion_overflow_test() {
  let script = repeat_byte(0xAC, 10_000)
  assert compute_legacy_sigop_count([<<>>], [script]) == 10_000
}

pub fn legacy_sigop_count_handles_ten_thousand_byte_push_only_script_without_recursion_overflow_test() {
  let script =
    list.repeat(<<0x01, 0x00>>, 5000)
    |> bit_array.concat

  assert bit_array.byte_size(script) == 10_000
  assert compute_legacy_sigop_count([<<>>], [script]) == 0
}

// ============================================================================
// Transaction fixtures
// ============================================================================

fn compute_legacy_sigop_count(
  input_scripts: List(BitArray),
  output_scripts: List(BitArray),
) -> Int {
  input_scripts
  |> build_legacy_transaction_bytes(output_scripts)
  |> deserialize_transaction
  |> transaction.compute_legacy_sigop_count
}

fn build_legacy_transaction_bytes(
  input_scripts: List(BitArray),
  output_scripts: List(BitArray),
) -> BitArray {
  let inputs =
    input_scripts
    |> list.index_map(fn(bytes, i) {
      build_input_bytes(repeat_byte(i + 1, 32), i, bytes, 0)
    })

  let outputs =
    output_scripts
    |> list.map(build_output_bytes(<<0:little-size(64)>>, _))

  <<
    transaction_version_1_bytes:bits,
    compact_size(list.length(inputs)):bits,
    bit_array.concat(inputs):bits,
    compact_size(list.length(outputs)):bits,
    bit_array.concat(outputs):bits,
    0:little-size(32),
  >>
}

fn deserialize_transaction(bytes: BitArray) {
  let assert Ok(tx) = transaction.deserialize(bytes)
  tx
}
