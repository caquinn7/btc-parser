import btc_parser/transaction.{
  CoinbaseWithMultipleInputs, DuplicateInput, InvalidCoinbaseScriptSigLength,
  NoInputs, NoOutputs, OutputValueOutOfRange, TotalOutputValueOutOfRange,
}
import gleam/list
import support/bitcoin_wire.{compact_size}
import support/transaction_wire.{
  build_input_bytes, build_output_bytes, repeat_byte,
  transaction_version_1_bytes,
}

// ============================================================================
// validate_context_free_consensus
// ============================================================================

pub fn validate_context_free_consensus_collects_no_inputs_and_no_outputs_test() {
  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    0x00,
    0x00,
    0:little-size(32),
  >>

  let assert Ok(tx) = transaction.deserialize(tx_bytes)

  assert transaction.validate_context_free_consensus(tx)
    == Error([NoInputs, NoOutputs])
}

pub fn validate_context_free_consensus_rejects_tx_with_no_outputs_test() {
  let input_count = compact_size(1)
  let input = build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)
  let output_count = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    input_count:bits,
    input:bits,
    output_count:bits,
    lock_time:bits,
  >>

  let assert Ok(tx) = transaction.deserialize(tx_bytes)

  assert transaction.validate_context_free_consensus(tx) == Error([NoOutputs])
}

pub fn validate_context_free_consensus_rejects_tx_with_negative_output_value_test() {
  let input_count = compact_size(1)
  let input = build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)
  let output_count = compact_size(1)
  // -1 as signed int64
  let negative_value = <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    input_count:bits,
    input:bits,
    output_count:bits,
    negative_value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(tx) = transaction.deserialize(tx_bytes)

  assert transaction.validate_context_free_consensus(tx)
    == Error([OutputValueOutOfRange(0, -1)])
}

pub fn validate_context_free_consensus_rejects_tx_with_output_exceeding_supply_test() {
  let input_count = compact_size(1)
  let input = build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)
  let output_count = compact_size(1)
  let excessive_value = <<2_100_000_000_000_001:little-size(64)>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    input_count:bits,
    input:bits,
    output_count:bits,
    excessive_value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(tx) = transaction.deserialize(tx_bytes)

  assert transaction.validate_context_free_consensus(tx)
    == Error([OutputValueOutOfRange(0, 2_100_000_000_000_001)])
}

pub fn validate_context_free_consensus_accepts_tx_with_total_outputs_equal_to_supply_test() {
  let input_count = compact_size(1)
  let input = build_input_bytes(<<1:size(256)>>, 0, <<>>, 0)
  let output_count = compact_size(2)
  let value1 = <<1_100_000_000_000_000:little-size(64)>>
  let value2 = <<1_000_000_000_000_000:little-size(64)>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    input_count:bits,
    input:bits,
    output_count:bits,
    value1:bits,
    script_pubkey_length:bits,
    value2:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(tx) = transaction.deserialize(tx_bytes)
  let assert Ok(_) = transaction.validate_context_free_consensus(tx)
}

pub fn validate_context_free_consensus_rejects_tx_with_total_outputs_exceeding_supply_test() {
  // Both outputs are individually valid; only their cumulative value is excessive.
  let input_count = compact_size(1)
  let input = build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)
  let output_count = compact_size(2)
  let value1 = <<1_100_000_000_000_000:little-size(64)>>
  let value2 = <<1_100_000_000_000_000:little-size(64)>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    input_count:bits,
    input:bits,
    output_count:bits,
    value1:bits,
    script_pubkey_length:bits,
    value2:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(tx) = transaction.deserialize(tx_bytes)

  assert transaction.validate_context_free_consensus(tx)
    == Error([TotalOutputValueOutOfRange(1, 2_200_000_000_000_000)])
}

pub fn validate_context_free_consensus_rejects_coinbase_with_multiple_inputs_test() {
  let input_count = compact_size(2)

  let coinbase_input =
    build_input_bytes(<<0:size(256)>>, 0xFFFFFFFF, <<0, 0>>, 0)

  let regular_input = build_input_bytes(<<1:size(256)>>, 0, <<>>, 0)

  let output_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    input_count:bits,
    coinbase_input:bits,
    regular_input:bits,
    output_count:bits,
    value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(tx) = transaction.deserialize(tx_bytes)

  assert transaction.validate_context_free_consensus(tx)
    == Error([CoinbaseWithMultipleInputs])
}

pub fn validate_context_free_consensus_rejects_multiple_coinbase_inputs_test() {
  let input_count = compact_size(2)

  let coinbase_input1 =
    build_input_bytes(<<0:size(256)>>, 0xFFFFFFFF, <<0, 0>>, 0)
  let coinbase_input2 =
    build_input_bytes(<<0:size(256)>>, 0xFFFFFFFF, <<0, 0>>, 0)

  let output_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    input_count:bits,
    coinbase_input1:bits,
    coinbase_input2:bits,
    output_count:bits,
    value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(tx) = transaction.deserialize(tx_bytes)

  assert transaction.validate_context_free_consensus(tx)
    == Error([CoinbaseWithMultipleInputs])
}

pub fn validate_context_free_consensus_rejects_coinbase_with_scriptsig_too_short_test() {
  let input_count = compact_size(1)
  let coinbase_input =
    build_input_bytes(<<0:size(256)>>, 0xFFFFFFFF, <<0x01>>, 0)
  let output_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    input_count:bits,
    coinbase_input:bits,
    output_count:bits,
    value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(tx) = transaction.deserialize(tx_bytes)

  assert transaction.validate_context_free_consensus(tx)
    == Error([InvalidCoinbaseScriptSigLength])
}

pub fn validate_context_free_consensus_rejects_coinbase_with_scriptsig_too_long_test() {
  let input_count = compact_size(1)

  let coinbase_input =
    build_input_bytes(<<0:size(256)>>, 0xFFFFFFFF, <<0:size(808)>>, 0)

  let output_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    input_count:bits,
    coinbase_input:bits,
    output_count:bits,
    value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(tx) = transaction.deserialize(tx_bytes)

  assert transaction.validate_context_free_consensus(tx)
    == Error([InvalidCoinbaseScriptSigLength])
}

pub fn validate_context_free_consensus_accepts_coinbase_with_scriptsig_min_length_test() {
  let input_count = compact_size(1)

  let coinbase_input =
    build_input_bytes(<<0:size(256)>>, 0xFFFFFFFF, <<0:size(16)>>, 0)

  let output_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    input_count:bits,
    coinbase_input:bits,
    output_count:bits,
    value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(tx) = transaction.deserialize(tx_bytes)
  let assert Ok(_) = transaction.validate_context_free_consensus(tx)
}

pub fn validate_context_free_consensus_accepts_coinbase_with_scriptsig_max_length_test() {
  let input_count = compact_size(1)

  let coinbase_input =
    build_input_bytes(<<0:size(256)>>, 0xFFFFFFFF, <<0:size(800)>>, 0)

  let output_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    input_count:bits,
    coinbase_input:bits,
    output_count:bits,
    value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(tx) = transaction.deserialize(tx_bytes)
  let assert Ok(_) = transaction.validate_context_free_consensus(tx)
}

pub fn validate_context_free_consensus_returns_multiple_errors_test() {
  // Combine independent coinbase-shape and output-value violations.
  let input_count = compact_size(2)

  let coinbase_input1 =
    build_input_bytes(<<0:size(256)>>, 0xFFFFFFFF, <<0, 0>>, 0)
  let regular_input = build_input_bytes(<<1:size(256)>>, 0, <<0, 0>>, 0)

  let output_count = compact_size(1)
  let negative_value = <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    input_count:bits,
    coinbase_input1:bits,
    regular_input:bits,
    output_count:bits,
    negative_value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(tx) = transaction.deserialize(tx_bytes)

  let assert Error(errors) = transaction.validate_context_free_consensus(tx)

  assert list.contains(errors, CoinbaseWithMultipleInputs)
  assert list.contains(errors, OutputValueOutOfRange(0, -1))
  assert list.length(errors) == 2
}

pub fn validate_context_free_consensus_rejects_tx_with_duplicate_inputs_test() {
  let input_count = compact_size(2)
  let shared_txid = repeat_byte(0xAB, 32)
  let input0 = build_input_bytes(shared_txid, 0, <<>>, 0xFFFFFFFF)
  let input1 = build_input_bytes(shared_txid, 0, <<>>, 0xFFFFFFFF)
  let output_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    input_count:bits,
    input0:bits,
    input1:bits,
    output_count:bits,
    value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(tx) = transaction.deserialize(tx_bytes)
  let assert [input0, ..] = transaction.get_inputs(tx)
  let duplicate_outpoint = transaction.get_input_outpoint(input0)

  assert transaction.validate_context_free_consensus(tx)
    == Error([DuplicateInput(duplicate_outpoint, 0, 1)])
}

pub fn validate_context_free_consensus_rejects_duplicate_input_at_non_adjacent_indices_test() {
  let input_count = compact_size(3)
  let shared_txid = repeat_byte(0xAB, 32)
  let other_txid = repeat_byte(0xCD, 32)
  let input0 = build_input_bytes(shared_txid, 0, <<>>, 0xFFFFFFFF)
  let input1 = build_input_bytes(other_txid, 1, <<>>, 0xFFFFFFFF)
  let input2 = build_input_bytes(shared_txid, 0, <<>>, 0xFFFFFFFF)
  let output_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    input_count:bits,
    input0:bits,
    input1:bits,
    input2:bits,
    output_count:bits,
    value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(tx) = transaction.deserialize(tx_bytes)
  let assert [input0, ..] = transaction.get_inputs(tx)
  let duplicate_outpoint = transaction.get_input_outpoint(input0)

  assert transaction.validate_context_free_consensus(tx)
    == Error([DuplicateInput(duplicate_outpoint, 0, 2)])
}

pub fn validate_context_free_consensus_accepts_inputs_with_same_txid_but_different_vout_test() {
  // Same txid but different output indices are distinct outpoints — not a duplicate
  let input_count = compact_size(2)
  let txid = repeat_byte(0xAB, 32)
  let input0 = build_input_bytes(txid, 0, <<>>, 0xFFFFFFFF)
  let input1 = build_input_bytes(txid, 1, <<>>, 0xFFFFFFFF)
  let output_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    input_count:bits,
    input0:bits,
    input1:bits,
    output_count:bits,
    value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(tx) = transaction.deserialize(tx_bytes)
  let assert Ok(_) = transaction.validate_context_free_consensus(tx)
}

pub fn validate_context_free_consensus_duplicate_input_reported_alongside_other_errors_test() {
  let input_count = compact_size(2)
  let shared_txid = repeat_byte(0xAB, 32)
  let input0 = build_input_bytes(shared_txid, 0, <<>>, 0xFFFFFFFF)
  let input1 = build_input_bytes(shared_txid, 0, <<>>, 0xFFFFFFFF)
  let output_count = compact_size(1)
  // -1 as signed int64
  let negative_value = <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    input_count:bits,
    input0:bits,
    input1:bits,
    output_count:bits,
    negative_value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(tx) = transaction.deserialize(tx_bytes)
  let assert [input0, ..] = transaction.get_inputs(tx)
  let duplicate_outpoint = transaction.get_input_outpoint(input0)

  let assert Error(errors) = transaction.validate_context_free_consensus(tx)
  assert list.contains(errors, OutputValueOutOfRange(0, -1))
  assert list.contains(errors, DuplicateInput(duplicate_outpoint, 0, 1))
  assert list.length(errors) == 2
}

// ============================================================================
// has_coinbase_shape
// ============================================================================

pub fn has_coinbase_shape_regular_transaction_returns_false_test() {
  let input_count = compact_size(1)
  let regular_input =
    build_input_bytes(repeat_byte(1, 32), 42, <<0, 1, 2>>, 0xFFFFFFFE)
  let output_count = compact_size(1)
  let output = build_output_bytes(<<50_000_000:little-size(64)>>, <<>>)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    input_count:bits,
    regular_input:bits,
    output_count:bits,
    output:bits,
    lock_time:bits,
  >>

  let assert Ok(tx) = transaction.deserialize(tx_bytes)
  let assert Ok(validated_tx) = transaction.validate_context_free_consensus(tx)
  assert !transaction.has_coinbase_shape(validated_tx)
}

pub fn has_coinbase_shape_coinbase_transaction_test() {
  let input_count = compact_size(1)
  let coinbase_input =
    build_input_bytes(<<0:size(256)>>, 0xFFFFFFFF, <<0:size(400)>>, 0)
  let output_count = compact_size(1)
  let output = build_output_bytes(<<5_000_000_000:little-size(64)>>, <<>>)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    input_count:bits,
    coinbase_input:bits,
    output_count:bits,
    output:bits,
    lock_time:bits,
  >>

  let assert Ok(tx) = transaction.deserialize(tx_bytes)
  let assert Ok(validated_tx) = transaction.validate_context_free_consensus(tx)
  assert transaction.has_coinbase_shape(validated_tx)
}
