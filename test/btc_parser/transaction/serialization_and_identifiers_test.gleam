import btc_parser/transaction.{NoOutputs}
import gleam/bit_array
import gleam/crypto.{Sha256}
import support/bitcoin_wire.{compact_size}
import support/transaction_wire.{
  assemble_segwit_transaction_bytes, build_input_bytes,
  build_minimal_legacy_transaction_bytes, build_output_bytes, repeat_byte,
  transaction_version_1_bytes,
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
