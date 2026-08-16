import btc_parser/transaction.{NoOutputs}
import gleam/bit_array
import gleam/crypto.{Sha256}
import support/bitcoin_wire.{compact_size}
import support/target
import support/transaction_wire.{
  assemble_segwit_transaction_bytes, build_input_bytes,
  build_minimal_legacy_transaction_bytes, build_output_bytes, repeat_byte,
  transaction_version_1_bytes,
}

// ============================================================================
// Transaction size and weight computation
// ============================================================================

pub fn compute_sizes_and_weight_for_one_minimal_legacy_transaction_test() {
  let tx_bytes = build_minimal_legacy_transaction_bytes(1)
  let assert Ok(tx) = transaction.deserialize(tx_bytes)

  assert transaction.compute_base_size(tx) == 60
  assert transaction.compute_total_size(tx) == 60
  assert transaction.compute_weight(tx) == 240
}

pub fn compute_sizes_and_weight_for_two_input_segwit_transaction_with_mixed_witness_stacks_test() {
  let input0 = build_input_bytes(repeat_byte(0x01, 32), 0, <<>>, 0)
  let input1 = build_input_bytes(repeat_byte(0x02, 32), 1, <<>>, 0)
  let output = build_output_bytes(<<1000:64-little>>, <<>>)
  let large_witness_item = repeat_byte(0x42, 253)
  let empty_witness_stack = compact_size(0)
  let populated_witness_stack = <<
    compact_size(2):bits,
    compact_size(0):bits,
    compact_size(bit_array.byte_size(large_witness_item)):bits,
    large_witness_item:bits,
  >>
  let tx_bytes =
    assemble_segwit_transaction_bytes([input0, input1], [output], [
      empty_witness_stack,
      populated_witness_stack,
    ])

  let assert Ok(tx) = transaction.deserialize(tx_bytes)

  assert transaction.compute_base_size(tx) == 101
  assert transaction.compute_total_size(tx) == 362
  assert transaction.compute_weight(tx) == 665
}

// ============================================================================
// serialize and serialize_stripped
// ============================================================================

pub fn serialize_round_trips_high_bit_version_wire_bytes_test() {
  let original_bytes = build_minimal_legacy_transaction_bytes(0x80000000)
  let assert Ok(result) = transaction.deserialize(original_bytes)

  assert transaction.serialize_stripped(result) == original_bytes
  assert transaction.serialize(result) == original_bytes
}

pub fn serialize_stripped_preserves_input_and_output_order_test() {
  let input0 = build_input_bytes(repeat_byte(0x11, 32), 1, <<0x51>>, 0x01020304)
  let input1 =
    build_input_bytes(repeat_byte(0x22, 32), 2, <<0x52, 0x53>>, 0x05060708)
  let output0 = build_output_bytes(<<1000:64-little>>, <<0x54>>)
  let output1 = build_output_bytes(<<2000:64-little>>, <<0x55, 0x56>>)
  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    compact_size(2):bits,
    input0:bits,
    input1:bits,
    compact_size(2):bits,
    output0:bits,
    output1:bits,
    0x090A0B0C:32-little,
  >>

  let assert Ok(tx) = transaction.deserialize(tx_bytes)

  assert transaction.serialize_stripped(tx) == tx_bytes
}

pub fn serialize_stripped_preserves_signed_and_large_output_values_test() {
  let input = build_input_bytes(repeat_byte(0x11, 32), 1, <<>>, 0xFFFFFFFF)
  let negative_output =
    build_output_bytes(<<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>, <<>>)
  let max_money_output =
    build_output_bytes(<<0x00, 0x40, 0x07, 0x5A, 0xF0, 0x75, 0x07, 0x00>>, <<>>)
  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    compact_size(1):bits,
    input:bits,
    compact_size(2):bits,
    negative_output:bits,
    max_money_output:bits,
    0:32-little,
  >>

  let assert Ok(tx) = transaction.deserialize(tx_bytes)

  assert transaction.serialize_stripped(tx) == tx_bytes
}

pub fn serialize_stripped_preserves_i64_boundary_output_values_on_erlang_test() {
  case target.is_javascript() {
    True -> Nil
    False -> {
      let input = build_input_bytes(repeat_byte(0x11, 32), 1, <<>>, 0xFFFFFFFF)
      let min_i64_output =
        build_output_bytes(<<0, 0, 0, 0, 0, 0, 0, 0x80>>, <<>>)
      let max_i64_output =
        build_output_bytes(
          <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F>>,
          <<>>,
        )
      let tx_bytes = <<
        transaction_version_1_bytes:bits,
        compact_size(1):bits,
        input:bits,
        compact_size(2):bits,
        min_i64_output:bits,
        max_i64_output:bits,
        0:32-little,
      >>

      let assert Ok(tx) = transaction.deserialize(tx_bytes)

      assert transaction.serialize_stripped(tx) == tx_bytes
    }
  }
}

pub fn serialize_and_hashing_accept_context_free_invalid_segwit_tx_test() {
  let input = build_input_bytes(repeat_byte(1, 32), 0, <<>>, 0xFFFFFFFF)
  let witness_item = <<0x42>>
  let witness_stack = <<
    compact_size(1):bits,
    compact_size(bit_array.byte_size(witness_item)):bits,
    witness_item:bits,
  >>
  let wire_bytes =
    assemble_segwit_transaction_bytes([input], [], [witness_stack])
  let stripped_bytes = <<
    transaction_version_1_bytes:bits,
    compact_size(1):bits,
    input:bits,
    compact_size(0):bits,
    0:little-size(32),
  >>

  let assert Ok(tx) = transaction.deserialize(wire_bytes)
  assert transaction.validate_context_free_consensus(tx) == Error([NoOutputs])

  assert transaction.serialize_stripped(tx) == stripped_bytes
  assert transaction.serialize(tx) == wire_bytes

  let expected_txid =
    stripped_bytes
    |> crypto.hash(Sha256, _)
    |> crypto.hash(Sha256, _)

  let expected_wtxid =
    wire_bytes
    |> crypto.hash(Sha256, _)
    |> crypto.hash(Sha256, _)

  assert transaction.compute_txid(tx) == expected_txid
  assert transaction.compute_wtxid(tx) == expected_wtxid
}

// ============================================================================
// compute_txid and compute_wtxid
// ============================================================================

pub fn compute_txid_matches_manual_dsha256_test() {
  let input_count = compact_size(1)
  let input = build_input_bytes(repeat_byte(1, 32), 0, <<>>, 0xFFFFFFFF)
  let output_count = compact_size(1)
  let output = build_output_bytes(<<1000:little-size(64)>>, <<>>)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    input_count:bits,
    input:bits,
    output_count:bits,
    output:bits,
    lock_time:bits,
  >>

  let expected_txid =
    tx_bytes
    |> crypto.hash(Sha256, _)
    |> crypto.hash(Sha256, _)

  let assert Ok(tx) = transaction.deserialize(tx_bytes)
  let txid = transaction.compute_txid(tx)

  assert txid == expected_txid
}

pub fn compute_wtxid_matches_manual_dsha256_test() {
  let input = build_input_bytes(repeat_byte(1, 32), 0, <<>>, 0xFFFFFFFF)
  let output = build_output_bytes(<<1000:little-size(64)>>, <<>>)

  let witness_item = <<0x42>>
  let witness_item_length = bit_array.byte_size(witness_item)
  let witness_stack = <<
    compact_size(1):bits,
    compact_size(witness_item_length):bits,
    witness_item:bits,
  >>

  let tx_bytes =
    assemble_segwit_transaction_bytes([input], [output], [witness_stack])

  // wtxid hashes extended serialization, including witness data.
  let expected_wtxid =
    tx_bytes
    |> crypto.hash(Sha256, _)
    |> crypto.hash(Sha256, _)

  let assert Ok(tx) = transaction.deserialize(tx_bytes)
  let wtxid = transaction.compute_wtxid(tx)

  assert wtxid == expected_wtxid
}

pub fn compute_txid_differs_from_wtxid_for_segwit_test() {
  let input = build_input_bytes(repeat_byte(1, 32), 0, <<>>, 0xFFFFFFFF)
  let output = build_output_bytes(<<1000:little-size(64)>>, <<>>)
  let witness_item = <<0x42>>
  let witness_stack = <<
    compact_size(1):bits,
    compact_size(bit_array.byte_size(witness_item)):bits,
    witness_item:bits,
  >>
  let tx_bytes =
    assemble_segwit_transaction_bytes([input], [output], [witness_stack])
  let assert Ok(tx) = transaction.deserialize(tx_bytes)

  let txid = transaction.compute_txid(tx)
  let wtxid = transaction.compute_wtxid(tx)

  assert txid != wtxid
}

pub fn compute_txid_equals_compute_wtxid_for_legacy_tx_test() {
  let assert Ok(tx) =
    transaction.deserialize(build_minimal_legacy_transaction_bytes(1))

  let txid = transaction.compute_txid(tx)
  let wtxid = transaction.compute_wtxid(tx)

  assert txid == wtxid
}
