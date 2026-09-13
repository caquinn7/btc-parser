import btc_parser/transaction.{type Input, type OutPoint}
import support/bitcoin_wire.{compact_size}
import support/transaction_wire.{
  build_input_bytes, build_minimal_output_section_bytes, repeat_byte,
  transaction_version_1_bytes,
}

// ============================================================================
// input_has_null_outpoint and is_null_outpoint
// ============================================================================

pub fn input_has_null_outpoint_returns_true_for_coinbase_marker_test() {
  let input = input_from_outpoint_fields(<<0:size(256)>>, 0xFFFFFFFF)
  assert transaction.input_has_null_outpoint(input)
}

pub fn input_has_null_outpoint_returns_false_for_regular_input_test() {
  let input = input_from_outpoint_fields(repeat_byte(1, 32), 0)
  assert !transaction.input_has_null_outpoint(input)
}

pub fn is_null_outpoint_returns_true_for_coinbase_marker_test() {
  let outpoint = outpoint_from_fields(<<0:size(256)>>, 0xFFFFFFFF)
  assert transaction.is_null_outpoint(outpoint)
}

pub fn is_null_outpoint_returns_false_for_regular_outpoint_test() {
  let outpoint = outpoint_from_fields(repeat_byte(1, 32), 0)
  assert !transaction.is_null_outpoint(outpoint)
}

pub fn is_null_outpoint_requires_zero_txid_and_max_vout_test() {
  let zero_txid_outpoint = outpoint_from_fields(<<0:size(256)>>, 0)
  let max_vout_outpoint = outpoint_from_fields(repeat_byte(1, 32), 0xFFFFFFFF)

  assert !transaction.is_null_outpoint(zero_txid_outpoint)
  assert !transaction.is_null_outpoint(max_vout_outpoint)
}

/// Obtain an opaque input containing the given outpoint fields.
fn input_from_outpoint_fields(
  outpoint_txid: BitArray,
  outpoint_vout: Int,
) -> Input {
  let input = build_input_bytes(outpoint_txid, outpoint_vout, <<>>, 0)
  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    transaction.deserialize(<<
      transaction_version_1_bytes:bits,
      compact_size(1):bits,
      input:bits,
      build_minimal_output_section_bytes():bits,
      lock_time:bits,
    >>)

  let assert [first_input] = transaction.get_inputs(tx)
  first_input
}

fn outpoint_from_fields(
  outpoint_txid: BitArray,
  outpoint_vout: Int,
) -> OutPoint {
  input_from_outpoint_fields(outpoint_txid, outpoint_vout)
  |> transaction.get_input_outpoint
}
