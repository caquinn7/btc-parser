import btc_parser/transaction.{
  DecodeFailed, InsufficientBytes, MaxInputCount, MaxOutputCount, MaxScriptSize,
  MaxTransactionSize, MaxWitnessStackItemCount, MaxWitnessStackPayloadSize,
  PolicyLimitExceeded,
}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import support/bitcoin_wire.{compact_size}
import support/transaction_assertions.{check_transaction_decode_error}
import support/transaction_wire.{
  assemble_segwit_transaction_bytes, build_input_bytes,
  build_minimal_input_section_bytes, build_minimal_legacy_transaction_bytes,
  build_minimal_output_section_bytes, build_output_bytes, min_input_size_bytes,
  min_output_size_bytes, repeat_byte, transaction_version_1_bytes,
}

// ============================================================================
// deserialize_hex_with_policy
// ============================================================================

pub fn deserialize_hex_with_policy_accepts_tx_at_max_tx_size_test() {
  let bytes = build_minimal_legacy_transaction_bytes(1)
  let policy = policy_with_max_tx_size(bit_array.byte_size(bytes))

  let assert Ok(tx) =
    bytes
    |> bit_array.base16_encode
    |> transaction.deserialize_hex_with_policy(policy)

  assert transaction.serialize(tx) == bytes
}

pub fn deserialize_hex_with_policy_wraps_policy_limit_error_test() {
  let bytes = build_minimal_legacy_transaction_bytes(1)
  let tx_size = bit_array.byte_size(bytes)
  let policy = policy_with_max_tx_size(tx_size - 1)

  let assert Error(DecodeFailed(error)) =
    bytes
    |> bit_array.base16_encode
    |> transaction.deserialize_hex_with_policy(policy)

  assert check_transaction_decode_error(error, 0, "transaction")
    == PolicyLimitExceeded(MaxTransactionSize, tx_size, tx_size - 1)
}

// ============================================================================
// Decode policy configuration
// ============================================================================

pub fn default_decode_policy_returns_expected_values_test() {
  let policy = transaction.default_decode_policy()

  assert transaction.decode_policy_max_tx_size(policy) == 400_000
  assert transaction.decode_policy_max_input_count(policy) == 100_000
  assert transaction.decode_policy_max_output_count(policy) == 100_000
  assert transaction.decode_policy_max_script_size(policy) == 10_000
  assert transaction.decode_policy_max_witness_stack_item_count(policy) == None
  assert transaction.decode_policy_max_witness_stack_payload_size(policy)
    == None
}

pub fn decode_policy_builder_overrides_default_limits_test() {
  let policy =
    transaction.default_decode_policy()
    |> transaction.decode_policy_with_max_tx_size(123)
    |> transaction.decode_policy_with_max_input_count(4)
    |> transaction.decode_policy_with_max_output_count(5)
    |> transaction.decode_policy_with_max_script_size(6)
    |> transaction.decode_policy_with_max_witness_stack_item_count(Some(7))
    |> transaction.decode_policy_with_max_witness_stack_payload_size(Some(8))

  assert transaction.decode_policy_max_tx_size(policy) == 123
  assert transaction.decode_policy_max_input_count(policy) == 4
  assert transaction.decode_policy_max_output_count(policy) == 5
  assert transaction.decode_policy_max_script_size(policy) == 6
  assert transaction.decode_policy_max_witness_stack_item_count(policy)
    == Some(7)
  assert transaction.decode_policy_max_witness_stack_payload_size(policy)
    == Some(8)
}

// ============================================================================
// deserialize_with_policy: transaction size
// ============================================================================

pub fn deserialize_with_policy_accepts_tx_at_max_tx_size_test() {
  // Build a minimal valid tx and confirm it deserializes when max_tx_size
  // exactly equals its byte length.
  let input_count = 1
  let input_padding = <<0:little-size({ min_input_size_bytes * 8 })>>
  let lock_time = <<0:little-size(32)>>
  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    compact_size(input_count):bits,
    input_padding:bits,
    build_minimal_output_section_bytes():bits,
    lock_time:bits,
  >>
  let tx_size = bit_array.byte_size(tx_bytes)

  let assert Ok(_) =
    transaction.deserialize_with_policy(
      tx_bytes,
      policy_with_max_tx_size(tx_size),
    )
}

pub fn deserialize_with_policy_rejects_tx_exceeding_max_tx_size_test() {
  // Build a minimal valid tx and confirm it is rejected when max_tx_size is
  // one byte less than its actual size.
  let input_count = 1
  let input_padding = <<0:little-size({ min_input_size_bytes * 8 })>>
  let lock_time = <<0:little-size(32)>>
  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    compact_size(input_count):bits,
    input_padding:bits,
    build_minimal_output_section_bytes():bits,
    lock_time:bits,
  >>
  let tx_size = bit_array.byte_size(tx_bytes)
  let max_tx_size = tx_size - 1

  let assert Error(decode_err) =
    transaction.deserialize_with_policy(
      tx_bytes,
      policy_with_max_tx_size(max_tx_size),
    )

  assert check_transaction_decode_error(decode_err, 0, "transaction")
    == PolicyLimitExceeded(MaxTransactionSize, tx_size, max_tx_size)
}

pub fn deserialize_with_policy_rejects_tx_well_above_max_tx_size_test() {
  let tx_size = 100
  let max_tx_size = 10
  let assert Error(decode_err) =
    transaction.deserialize_with_policy(
      <<0:size({ tx_size * 8 })>>,
      policy_with_max_tx_size(max_tx_size),
    )

  assert check_transaction_decode_error(decode_err, 0, "transaction")
    == PolicyLimitExceeded(MaxTransactionSize, tx_size, max_tx_size)
}

// ============================================================================
// deserialize_with_policy: input and output counts
// ============================================================================

pub fn deserialize_with_policy_accepts_input_count_at_max_input_count_test() {
  // Supply enough bytes that policy, not structural feasibility, is the limit.

  let max_input_count = 3
  let input_count = max_input_count
  let input_padding = <<
    0:little-size({ input_count * min_input_size_bytes * 8 }),
  >>
  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    transaction.deserialize_with_policy(
      <<
        transaction_version_1_bytes:bits,
        compact_size(input_count):bits,
        input_padding:bits,
        build_minimal_output_section_bytes():bits,
        lock_time:bits,
      >>,
      policy_with_max_input_count(max_input_count),
    )

  assert transaction.get_input_count(tx) == input_count
}

pub fn deserialize_with_policy_rejects_input_count_exceeding_max_input_count_test() {
  // Supply enough bytes that policy, not structural feasibility, rejects the count.

  let max_input_count = 2
  let input_count = max_input_count + 1
  let input_padding = <<
    0:little-size({ input_count * min_input_size_bytes * 8 }),
  >>

  let assert Error(decode_err) =
    transaction.deserialize_with_policy(
      <<
        transaction_version_1_bytes:bits,
        input_count:size(8),
        input_padding:bits,
      >>,
      policy_with_max_input_count(max_input_count),
    )

  assert check_transaction_decode_error(
      decode_err,
      4,
      "transaction.inputs.count",
    )
    == PolicyLimitExceeded(MaxInputCount, input_count, max_input_count)
}

pub fn deserialize_with_policy_prioritizes_structural_input_count_error_test() {
  // Only two inputs can fit, making structural feasibility the active limit.

  let available_input_count = 2
  let input_count = available_input_count + 1
  let non_limiting_max_input_count = input_count
  let input_padding = <<
    0:little-size({ available_input_count * min_input_size_bytes * 8 }),
  >>

  let assert Error(decode_err) =
    transaction.deserialize_with_policy(
      <<
        transaction_version_1_bytes:bits,
        compact_size(input_count):bits,
        input_padding:bits,
      >>,
      policy_with_max_input_count(non_limiting_max_input_count),
    )

  assert check_transaction_decode_error(
      decode_err,
      4,
      "transaction.inputs.count",
    )
    == InsufficientBytes(
      claimed: available_input_count * min_input_size_bytes + 1,
      remaining: available_input_count * min_input_size_bytes,
    )
}

pub fn deserialize_with_policy_accepts_input_count_at_structural_boundary_test() {
  // Exactly two inputs can fit, exercising the structural boundary.

  let input_count = 2
  let non_limiting_max_input_count = input_count + 1
  let input_padding = <<
    0:little-size({ input_count * min_input_size_bytes * 8 }),
  >>
  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    transaction.deserialize_with_policy(
      <<
        transaction_version_1_bytes:bits,
        compact_size(input_count):bits,
        input_padding:bits,
        build_minimal_output_section_bytes():bits,
        lock_time:bits,
      >>,
      policy_with_max_input_count(non_limiting_max_input_count),
    )

  assert transaction.get_input_count(tx) == input_count
}

pub fn deserialize_with_policy_accepts_output_count_at_max_output_count_test() {
  // Supply enough bytes that policy, not structural feasibility, is the limit.

  let max_output_count = 3
  let output_count = max_output_count
  let output1 = build_output_bytes(<<0:little-size(64)>>, <<>>)
  let output2 = build_output_bytes(<<0:little-size(64)>>, <<>>)
  let output3 = build_output_bytes(<<0:little-size(64)>>, <<>>)
  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    transaction.deserialize_with_policy(
      <<
        transaction_version_1_bytes:bits,
        build_minimal_input_section_bytes():bits,
        compact_size(output_count):bits,
        output1:bits,
        output2:bits,
        output3:bits,
        lock_time:bits,
      >>,
      policy_with_max_output_count(max_output_count),
    )

  assert transaction.get_output_count(tx) == output_count
}

pub fn deserialize_with_policy_rejects_output_count_exceeding_max_output_count_test() {
  // Supply enough bytes that policy, not structural feasibility, rejects the count.

  let max_output_count = 2
  let output_count = max_output_count + 1
  let output1 = build_output_bytes(<<0:little-size(64)>>, <<>>)
  let output2 = build_output_bytes(<<0:little-size(64)>>, <<>>)
  let output3 = build_output_bytes(<<0:little-size(64)>>, <<>>)
  let lock_time = <<0:little-size(32)>>

  let assert Error(decode_err) =
    transaction.deserialize_with_policy(
      <<
        transaction_version_1_bytes:bits,
        build_minimal_input_section_bytes():bits,
        compact_size(output_count):bits,
        output1:bits,
        output2:bits,
        output3:bits,
        lock_time:bits,
      >>,
      policy_with_max_output_count(max_output_count),
    )

  assert check_transaction_decode_error(
      decode_err,
      46,
      "transaction.outputs.count",
    )
    == PolicyLimitExceeded(MaxOutputCount, output_count, max_output_count)
}

pub fn deserialize_with_policy_prioritizes_structural_output_count_error_test() {
  // Only two outputs can fit, making structural feasibility the active limit.

  let available_output_count = 2
  let output_count = available_output_count + 1
  let non_limiting_max_output_count = output_count
  let output1 = build_output_bytes(<<0:little-size(64)>>, <<>>)
  let output2 = build_output_bytes(<<0:little-size(64)>>, <<>>)

  let assert Error(decode_err) =
    transaction.deserialize_with_policy(
      <<
        transaction_version_1_bytes:bits,
        build_minimal_input_section_bytes():bits,
        compact_size(output_count):bits,
        output1:bits,
        output2:bits,
      >>,
      policy_with_max_output_count(non_limiting_max_output_count),
    )

  assert check_transaction_decode_error(
      decode_err,
      46,
      "transaction.outputs.count",
    )
    == InsufficientBytes(
      claimed: available_output_count * min_output_size_bytes + 1,
      remaining: available_output_count * min_output_size_bytes,
    )
}

pub fn deserialize_with_policy_accepts_output_count_at_structural_boundary_test() {
  // Exactly two outputs can fit, exercising the structural boundary.

  let output_count = 2
  let non_limiting_max_output_count = output_count + 1
  let output1 = build_output_bytes(<<0:little-size(64)>>, <<>>)
  let output2 = build_output_bytes(<<0:little-size(64)>>, <<>>)
  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    transaction.deserialize_with_policy(
      <<
        transaction_version_1_bytes:bits,
        build_minimal_input_section_bytes():bits,
        compact_size(output_count):bits,
        output1:bits,
        output2:bits,
        lock_time:bits,
      >>,
      policy_with_max_output_count(non_limiting_max_output_count),
    )

  assert transaction.get_output_count(tx) == output_count
}

// ============================================================================
// deserialize_with_policy: script size
// ============================================================================

pub fn deserialize_with_policy_rejects_scriptsig_exceeding_max_script_size_test() {
  let policy = transaction.default_decode_policy()
  let max_script_size = transaction.decode_policy_max_script_size(policy)
  let oversized_script_size = max_script_size + 1
  let input_count = compact_size(1)

  let outpoint_txid_bytes = <<0:size(256)>>
  let outpoint_vout = 0
  let script_sig = <<0:size({ oversized_script_size * 8 })>>
  let sequence = 0

  let input_bytes =
    build_input_bytes(outpoint_txid_bytes, outpoint_vout, script_sig, sequence)

  let assert Error(decode_err) =
    transaction.deserialize_with_policy(
      <<
        transaction_version_1_bytes:bits,
        input_count:bits,
        input_bytes:bits,
      >>,
      policy,
    )

  assert check_transaction_decode_error(
      decode_err,
      41,
      "transaction.inputs[0].script_sig.length",
    )
    == PolicyLimitExceeded(
      MaxScriptSize,
      oversized_script_size,
      max_script_size,
    )
}

pub fn deserialize_with_policy_rejects_scriptpubkey_exceeding_max_script_size_test() {
  let policy = transaction.default_decode_policy()
  let max_script_size = transaction.decode_policy_max_script_size(policy)
  let oversized_script_size = max_script_size + 1
  let output_count = compact_size(1)

  let value = <<0:little-size(64)>>
  let script_pubkey = <<0:size({ oversized_script_size * 8 })>>

  let output_bytes = build_output_bytes(value, script_pubkey)

  let assert Error(decode_err) =
    transaction.deserialize_with_policy(
      <<
        transaction_version_1_bytes:bits,
        build_minimal_input_section_bytes():bits,
        output_count:bits,
        output_bytes:bits,
      >>,
      policy,
    )

  assert check_transaction_decode_error(
      decode_err,
      55,
      "transaction.outputs[0].script_pubkey.length",
    )
    == PolicyLimitExceeded(
      MaxScriptSize,
      oversized_script_size,
      max_script_size,
    )
}

pub fn deserialize_with_policy_accepts_scriptpubkey_at_max_script_size_test() {
  let policy = transaction.default_decode_policy()
  let max_script_size = transaction.decode_policy_max_script_size(policy)
  let value_satoshis = 75_000_000
  let script_pubkey_bytes = <<0:size({ max_script_size * 8 })>>
  let output =
    build_output_bytes(<<value_satoshis:little-size(64)>>, script_pubkey_bytes)
  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    transaction.deserialize_with_policy(
      <<
        transaction_version_1_bytes:bits,
        build_minimal_input_section_bytes():bits,
        compact_size(1):bits,
        output:bits,
        lock_time:bits,
      >>,
      policy,
    )

  let outputs = transaction.get_outputs(tx)
  let assert [first_output] = outputs

  let actual_value =
    first_output
    |> transaction.get_output_value

  assert actual_value == value_satoshis

  let actual_script_pubkey_bytes =
    first_output
    |> transaction.get_output_script_pubkey
    |> transaction.get_raw_script_bytes

  assert bit_array.byte_size(actual_script_pubkey_bytes) == max_script_size
}

// ============================================================================
// deserialize_with_policy: witness limits
// ============================================================================

pub fn deserialize_with_policy_accepts_witness_stack_at_max_item_count_test() {
  let max_witness_stack_item_count = 3

  let input = build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output_bytes(<<1000:little-size(64)>>, <<>>)

  let witness_items =
    int.range(0, max_witness_stack_item_count, with: <<>>, run: fn(acc, _) {
      <<acc:bits, compact_size(5):bits, 1, 2, 3, 4, 5>>
    })

  let witness_stack = <<
    compact_size(max_witness_stack_item_count):bits,
    witness_items:bits,
  >>

  let tx_bytes =
    assemble_segwit_transaction_bytes([input], [output], [witness_stack])

  let policy =
    policy_with_max_witness_stack_item_count(max_witness_stack_item_count)

  let assert Ok(tx) = transaction.deserialize_with_policy(tx_bytes, policy)

  let assert Ok(witnesses) = transaction.get_witnesses(tx)
  let assert [stack] = witnesses

  let items = transaction.get_witness_items(stack)
  assert list.length(items) == max_witness_stack_item_count
}

pub fn deserialize_with_policy_rejects_witness_stack_exceeding_max_item_count_test() {
  let max_witness_stack_item_count = 2

  let input = build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output_bytes(<<1000:little-size(64)>>, <<>>)

  let witness_items =
    int.range(0, max_witness_stack_item_count + 1, with: <<>>, run: fn(acc, _) {
      <<acc:bits, compact_size(5):bits, 1, 2, 3, 4, 5>>
    })

  let witness_stack = <<
    compact_size(max_witness_stack_item_count + 1):bits,
    witness_items:bits,
  >>

  let tx_bytes =
    assemble_segwit_transaction_bytes([input], [output], [witness_stack])

  let policy =
    policy_with_max_witness_stack_item_count(max_witness_stack_item_count)

  let assert Error(decode_err) =
    transaction.deserialize_with_policy(tx_bytes, policy)

  assert check_transaction_decode_error(
      decode_err,
      58,
      "transaction.witnesses[0].items.count",
    )
    == PolicyLimitExceeded(
      MaxWitnessStackItemCount,
      max_witness_stack_item_count + 1,
      max_witness_stack_item_count,
    )
}

pub fn deserialize_with_policy_accepts_witness_stack_at_max_payload_size_test() {
  let max_witness_stack_payload_size = 50

  let input = build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output_bytes(<<1000:little-size(64)>>, <<>>)

  // Payload sizes sum to the exact policy boundary: 20 + 15 + 15 = 50.
  let witness_items = <<
    compact_size(20):bits,
    repeat_byte(0xAA, 20):bits,
    compact_size(15):bits,
    repeat_byte(0xBB, 15):bits,
    compact_size(15):bits,
    repeat_byte(0xCC, 15):bits,
  >>

  let witness_stack = <<compact_size(3):bits, witness_items:bits>>

  let tx_bytes =
    assemble_segwit_transaction_bytes([input], [output], [witness_stack])

  let policy =
    policy_with_max_witness_stack_payload_size(max_witness_stack_payload_size)

  let assert Ok(tx) = transaction.deserialize_with_policy(tx_bytes, policy)

  let assert Ok(witnesses) = transaction.get_witnesses(tx)
  let assert [stack] = witnesses

  let items = transaction.get_witness_items(stack)
  assert list.length(items) == 3

  let total_payload_size =
    items
    |> list.map(fn(item) {
      item
      |> transaction.get_witness_item_bytes
      |> bit_array.byte_size
    })
    |> list.fold(0, fn(acc, size) { acc + size })

  assert total_payload_size == max_witness_stack_payload_size
}

pub fn deserialize_with_policy_rejects_witness_stack_exceeding_max_payload_size_test() {
  let max_witness_stack_payload_size = 50

  let input = build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output_bytes(<<1000:little-size(64)>>, <<>>)

  // The third item crosses the boundary: 20 + 15 + 16 = 51.
  let witness_items = <<
    compact_size(20):bits,
    repeat_byte(0xAA, 20):bits,
    compact_size(15):bits,
    repeat_byte(0xBB, 15):bits,
    compact_size(16):bits,
    repeat_byte(0xCC, 16):bits,
  >>

  let witness_stack = <<compact_size(3):bits, witness_items:bits>>

  let tx_bytes =
    assemble_segwit_transaction_bytes([input], [output], [witness_stack])

  let policy =
    policy_with_max_witness_stack_payload_size(max_witness_stack_payload_size)

  let assert Error(decode_err) =
    transaction.deserialize_with_policy(tx_bytes, policy)

  assert check_transaction_decode_error(
      decode_err,
      96,
      "transaction.witnesses[0].items[2]",
    )
    == PolicyLimitExceeded(
      MaxWitnessStackPayloadSize,
      51,
      max_witness_stack_payload_size,
    )
}

// ============================================================================
// Policy Builder Helpers
// ============================================================================

fn policy_with_max_tx_size(max_tx_size: Int) {
  transaction.default_decode_policy()
  |> transaction.decode_policy_with_max_tx_size(max_tx_size)
}

fn policy_with_max_input_count(max_input_count: Int) {
  transaction.default_decode_policy()
  |> transaction.decode_policy_with_max_input_count(max_input_count)
}

fn policy_with_max_output_count(max_output_count: Int) {
  transaction.default_decode_policy()
  |> transaction.decode_policy_with_max_output_count(max_output_count)
}

fn policy_with_max_witness_stack_item_count(max_witness_stack_item_count: Int) {
  transaction.default_decode_policy()
  |> transaction.decode_policy_with_max_witness_stack_item_count(Some(
    max_witness_stack_item_count,
  ))
}

fn policy_with_max_witness_stack_payload_size(
  max_witness_stack_payload_size: Int,
) {
  transaction.default_decode_policy()
  |> transaction.decode_policy_with_max_witness_stack_payload_size(Some(
    max_witness_stack_payload_size,
  ))
}
