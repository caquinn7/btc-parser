import btc_parser/transaction.{
  DecodeFailed, InsufficientBytes, IntegerOutOfRange, InvalidHex,
  InvalidSegwitMarkerFlag, NonMinimalCompactSize, SuperfluousWitnessRecord,
  TrailingBytes, UnexpectedEof,
}
import gleam/bit_array
import support/bitcoin_wire.{compact_size}
import support/target
import support/transaction_assertions.{check_transaction_decode_error}
import support/transaction_wire.{
  assemble_segwit_transaction_bytes, build_input_bytes,
  build_minimal_input_section_bytes, build_minimal_legacy_transaction_bytes,
  build_minimal_output_section_bytes, build_output_bytes, min_input_size_bytes,
  min_output_size_bytes, repeat_byte, transaction_version_1_bytes,
}

// ============================================================================
// deserialize_hex: invalid hex input
// ============================================================================

pub fn deserialize_hex_errors_on_odd_length_string_test() {
  assert transaction.deserialize_hex("010") == Error(InvalidHex)
}

pub fn deserialize_hex_errors_on_invalid_hex_characters_test() {
  assert transaction.deserialize_hex("0102zz") == Error(InvalidHex)
}

pub fn deserialize_hex_errors_on_string_with_whitespace_test() {
  assert transaction.deserialize_hex("01 02 03 04") == Error(InvalidHex)
}

// ============================================================================
// deserialize: transaction framing
// ============================================================================

pub fn deserialize_version_at_signed_max_as_unsigned_test() {
  let assert Ok(result) =
    transaction.deserialize(build_minimal_legacy_transaction_bytes(0x7FFFFFFF))

  assert transaction.get_version(result) == 2_147_483_647
}

pub fn deserialize_version_above_signed_max_as_unsigned_test() {
  let assert Ok(result) =
    transaction.deserialize(build_minimal_legacy_transaction_bytes(0x80000000))

  assert transaction.get_version(result) == 2_147_483_648
}

pub fn deserialize_max_unsigned_version_as_unsigned_test() {
  let assert Ok(result) =
    transaction.deserialize(build_minimal_legacy_transaction_bytes(0xFFFFFFFF))

  assert transaction.get_version(result) == 4_294_967_295
}

pub fn deserialize_errors_on_empty_string_test() {
  let assert Error(DecodeFailed(decode_err)) = transaction.deserialize_hex("")

  assert check_transaction_decode_error(decode_err, 0, "transaction.version")
    == UnexpectedEof(bytes_needed: 4, remaining: 0)
}

pub fn deserialize_errors_when_input_shorter_than_4_bytes_test() {
  let assert Error(DecodeFailed(decode_err)) =
    transaction.deserialize_hex("010203")

  assert check_transaction_decode_error(decode_err, 0, "transaction.version")
    == UnexpectedEof(4, 3)
}

pub fn deserialize_errors_on_non_byte_aligned_input_test() {
  // A trailing bit makes the remainder non-byte-aligned, so the first
  // fixed-width read fails even though byte_size rounds up.
  let valid_bytes = build_minimal_legacy_transaction_bytes(1)
  let unaligned = <<valid_bytes:bits, 0:1>>

  let assert Error(decode_err) = transaction.deserialize(unaligned)

  let expected_remaining = bit_array.byte_size(valid_bytes) + 1
  assert check_transaction_decode_error(decode_err, 0, "transaction.version")
    == UnexpectedEof(bytes_needed: 4, remaining: expected_remaining)
}

pub fn deserialize_does_not_misclassify_segwit_when_marker_and_flag_are_missing_test() {
  let assert Error(decode_err) =
    transaction.deserialize(transaction_version_1_bytes)

  assert check_transaction_decode_error(
      decode_err,
      4,
      "transaction.inputs.count",
    )
    == UnexpectedEof(1, 0)
}

pub fn deserialize_does_not_misclassify_segwit_when_marker_and_flag_are_truncated_test() {
  let marker = <<0:size(8)>>

  let assert Error(decode_err) =
    transaction.deserialize(<<transaction_version_1_bytes:bits, marker:bits>>)

  assert check_transaction_decode_error(
      decode_err,
      5,
      "transaction.outputs.count",
    )
    == UnexpectedEof(1, 0)
}

pub fn deserialize_returns_invalid_segwit_marker_flag_error_test() {
  let marker = <<0:size(8)>>
  let flag = <<2:little-size(8)>>

  let assert Error(decode_err) =
    transaction.deserialize(<<
      transaction_version_1_bytes:bits,
      marker:bits,
      flag:bits,
    >>)

  assert check_transaction_decode_error(
      decode_err,
      4,
      "transaction.segwit.marker_and_flag",
    )
    == InvalidSegwitMarkerFlag(0, 2)
}

pub fn deserialize_treats_zero_input_and_output_counts_as_empty_legacy_tx_test() {
  let lock_time = 42
  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    0x00,
    0x00,
    lock_time:little-size(32),
  >>

  let assert Ok(tx) = transaction.deserialize(tx_bytes)

  assert !transaction.is_segwit(tx)
  assert transaction.get_input_count(tx) == 0
  assert transaction.get_inputs(tx) == []
  assert transaction.get_output_count(tx) == 0
  assert transaction.get_outputs(tx) == []
  assert transaction.get_lock_time(tx) == lock_time
}

pub fn deserialize_reports_lock_time_decode_error_path_test() {
  let tx_without_lock_time = <<
    transaction_version_1_bytes:bits,
    build_minimal_input_section_bytes():bits,
    build_minimal_output_section_bytes():bits,
  >>

  let assert Error(decode_err) = transaction.deserialize(tx_without_lock_time)

  assert check_transaction_decode_error(decode_err, 56, "transaction.lock_time")
    == UnexpectedEof(4, 0)
}

pub fn deserialize_rejects_legacy_tx_with_trailing_byte_test() {
  let lock_time = <<0:little-size(32)>>

  let valid_tx = <<
    transaction_version_1_bytes:bits,
    build_minimal_input_section_bytes():bits,
    build_minimal_output_section_bytes():bits,
    lock_time:bits,
  >>

  let assert Error(decode_err) =
    transaction.deserialize(<<valid_tx:bits, 0x42:size(8)>>)

  let expected_offset = bit_array.byte_size(valid_tx)
  assert check_transaction_decode_error(
      decode_err,
      expected_offset,
      "transaction",
    )
    == TrailingBytes(1)
}

pub fn deserialize_rejects_segwit_tx_with_trailing_byte_test() {
  let input = build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output_bytes(<<0:little-size(64)>>, <<>>)
  let witness_stack = <<
    compact_size(1):bits,
    compact_size(0):bits,
  >>

  let valid_tx =
    assemble_segwit_transaction_bytes([input], [output], [witness_stack])

  let assert Error(decode_err) =
    transaction.deserialize(<<valid_tx:bits, 0xFF:size(8)>>)

  let expected_offset = bit_array.byte_size(valid_tx)
  assert check_transaction_decode_error(
      decode_err,
      expected_offset,
      "transaction",
    )
    == TrailingBytes(1)
}

// ============================================================================
// deserialize: inputs
// ============================================================================

pub fn deserialize_rejects_input_count_when_minimum_input_bytes_are_unavailable_test() {
  // Stop one byte short of the minimum encoded input size.

  let input_count = 1
  let input_padding = <<
    0:little-size({ 1 * { min_input_size_bytes - 1 } * 8 }),
  >>

  let assert Error(decode_err) =
    transaction.deserialize(<<
      transaction_version_1_bytes:bits,
      compact_size(input_count):bits,
      input_padding:bits,
    >>)

  assert check_transaction_decode_error(
      decode_err,
      4,
      "transaction.inputs.count",
    )
    == InsufficientBytes(
      remaining: min_input_size_bytes - 1,
      claimed: min_input_size_bytes,
    )
}

pub fn deserialize_preserves_single_input_test() {
  let input_count = compact_size(1)

  let outpoint_txid_bytes = repeat_byte(1, 32)
  let outpoint_vout = 5
  let script_sig_bytes = <<0x48, 0x30, 0x45, 0x02, 0x21>>
  let sequence = 0xFFFFFFFE

  let input_bytes =
    build_input_bytes(
      outpoint_txid_bytes,
      outpoint_vout,
      script_sig_bytes,
      sequence,
    )

  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    transaction.deserialize(<<
      transaction_version_1_bytes:bits,
      input_count:bits,
      input_bytes:bits,
      build_minimal_output_section_bytes():bits,
      lock_time:bits,
    >>)

  assert transaction.get_input_count(tx) == 1
  let inputs = transaction.get_inputs(tx)
  let assert [first_input] = inputs

  let outpoint = transaction.get_input_outpoint(first_input)

  assert transaction.get_outpoint_txid(outpoint) == outpoint_txid_bytes
  assert transaction.get_outpoint_vout(outpoint) == outpoint_vout

  assert transaction.get_input_sequence(first_input) == sequence

  let actual_script_sig_bytes =
    first_input
    |> transaction.get_input_script_sig
    |> transaction.get_raw_script_bytes

  assert actual_script_sig_bytes == script_sig_bytes
  assert first_input
    |> transaction.get_input_script_sig
    |> transaction.get_script_size
    == bit_array.byte_size(script_sig_bytes)
}

pub fn deserialize_preserves_empty_scriptsig_test() {
  let input_count = compact_size(1)

  let outpoint_txid_bytes = <<0:size(256)>>
  let outpoint_vout = 0xFFFFFFFF
  let script_sig_bytes = <<>>
  let sequence = 0xFFFFFFFE

  let input_bytes =
    build_input_bytes(
      outpoint_txid_bytes,
      outpoint_vout,
      script_sig_bytes,
      sequence,
    )

  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    transaction.deserialize(<<
      transaction_version_1_bytes:bits,
      input_count:bits,
      input_bytes:bits,
      build_minimal_output_section_bytes():bits,
      lock_time:bits,
    >>)

  let inputs = transaction.get_inputs(tx)
  let assert [first_input] = inputs

  let actual_script_sig_bytes =
    first_input
    |> transaction.get_input_script_sig
    |> transaction.get_raw_script_bytes

  assert actual_script_sig_bytes == <<>>
}

pub fn deserialize_preserves_multiple_inputs_test() {
  let input_count = compact_size(3)

  let outpoint1_txid_bytes = repeat_byte(1, 32)
  let outpoint2_txid_bytes = repeat_byte(2, 32)
  let outpoint3_txid_bytes = repeat_byte(3, 32)

  let outpoint1_vout = 0
  let outpoint2_vout = 1
  let outpoint3_vout = 2

  let sig1_bytes = <<>>
  let sig2_bytes = <<0x01>>
  let sig3_bytes = <<0xAA, 0xBB>>

  let seq1 = 0xFFFFFFFF
  let seq2 = 0
  let seq3 = 1

  let input1_bytes =
    build_input_bytes(outpoint1_txid_bytes, outpoint1_vout, sig1_bytes, seq1)
  let input2_bytes =
    build_input_bytes(outpoint2_txid_bytes, outpoint2_vout, sig2_bytes, seq2)
  let input3_bytes =
    build_input_bytes(outpoint3_txid_bytes, outpoint3_vout, sig3_bytes, seq3)

  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    transaction.deserialize(<<
      transaction_version_1_bytes:bits,
      input_count:bits,
      input1_bytes:bits,
      input2_bytes:bits,
      input3_bytes:bits,
      build_minimal_output_section_bytes():bits,
      lock_time:bits,
    >>)

  assert transaction.get_input_count(tx) == 3
  let inputs = transaction.get_inputs(tx)
  let assert [input1, input2, input3] = inputs

  let outpoint1 = transaction.get_input_outpoint(input1)

  assert transaction.get_outpoint_txid(outpoint1) == outpoint1_txid_bytes
  assert transaction.get_outpoint_vout(outpoint1) == outpoint1_vout
  assert transaction.get_input_sequence(input1) == seq1
  assert input1
    |> transaction.get_input_script_sig
    |> transaction.get_raw_script_bytes
    == sig1_bytes

  let outpoint2 = transaction.get_input_outpoint(input2)

  assert transaction.get_outpoint_txid(outpoint2) == outpoint2_txid_bytes
  assert transaction.get_outpoint_vout(outpoint2) == outpoint2_vout
  assert transaction.get_input_sequence(input2) == seq2
  assert input2
    |> transaction.get_input_script_sig
    |> transaction.get_raw_script_bytes
    == sig2_bytes

  let outpoint3 = transaction.get_input_outpoint(input3)

  assert transaction.get_outpoint_txid(outpoint3) == outpoint3_txid_bytes
  assert transaction.get_outpoint_vout(outpoint3) == outpoint3_vout
  assert transaction.get_input_sequence(input3) == seq3
  assert input3
    |> transaction.get_input_script_sig
    |> transaction.get_raw_script_bytes
    == sig3_bytes
}

pub fn deserialize_rejects_scriptsig_length_exceeds_remaining_bytes_test() {
  // Build a transaction where the scriptSig length claims 100 bytes
  // but only 10 remain.

  let input_count = compact_size(1)

  let outpoint_txid_bytes = <<0:size(256)>>
  let outpoint_vout_bytes = <<0:little-size(32)>>

  let script_sig_length = compact_size(100)

  let partial_script_sig = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>

  let input_bytes = <<
    outpoint_txid_bytes:bits,
    outpoint_vout_bytes:bits,
    script_sig_length:bits,
    partial_script_sig:bits,
  >>

  let assert Error(decode_err) =
    transaction.deserialize(<<
      transaction_version_1_bytes:bits,
      input_count:bits,
      input_bytes:bits,
    >>)

  assert check_transaction_decode_error(
      decode_err,
      41,
      "transaction.inputs[0].script_sig.length",
    )
    == InsufficientBytes(claimed: 100, remaining: 10)
}

pub fn deserialize_returns_error_with_current_input_index_test() {
  // Parse one complete input first so the failure path must retain index 1.
  let input_count = compact_size(2)

  let input1_bytes = build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)

  let input2_outpoint_txid_bytes = <<0:size(256)>>
  let input2_outpoint_vout_bytes = <<0:little-size(32)>>
  let input2_script_sig_length = compact_size(100)
  let input2_partial = <<
    input2_outpoint_txid_bytes:bits,
    input2_outpoint_vout_bytes:bits,
    input2_script_sig_length:bits,
  >>
  let remaining_bytes = <<0:little-size(32)>>

  let assert Error(decode_err) =
    transaction.deserialize(<<
      transaction_version_1_bytes:bits,
      input_count:bits,
      input1_bytes:bits,
      input2_partial:bits,
      remaining_bytes:bits,
    >>)

  assert check_transaction_decode_error(
      decode_err,
      82,
      "transaction.inputs[1].script_sig.length",
    )
    == InsufficientBytes(claimed: 100, remaining: 4)
}

pub fn deserialize_reports_indexed_input_outpoint_txid_decode_error_path_test() {
  let first_input = build_input_bytes(<<0:size(256)>>, 0, repeat_byte(0, 41), 0)
  let partial_second_input = repeat_byte(0, 10)

  let assert Error(decode_err) =
    transaction.deserialize(<<
      transaction_version_1_bytes:bits,
      compact_size(2):bits,
      first_input:bits,
      partial_second_input:bits,
    >>)

  assert check_transaction_decode_error(
      decode_err,
      87,
      "transaction.inputs[1].outpoint.txid",
    )
    == UnexpectedEof(32, 10)
}

pub fn deserialize_reports_indexed_input_outpoint_vout_decode_error_path_test() {
  let first_input = build_input_bytes(<<0:size(256)>>, 0, repeat_byte(0, 7), 0)
  let partial_second_input = <<0:size(256), 0:size(16)>>

  let assert Error(decode_err) =
    transaction.deserialize(<<
      transaction_version_1_bytes:bits,
      compact_size(2):bits,
      first_input:bits,
      partial_second_input:bits,
    >>)

  assert check_transaction_decode_error(
      decode_err,
      85,
      "transaction.inputs[1].outpoint.vout",
    )
    == UnexpectedEof(4, 2)
}

pub fn deserialize_reports_indexed_input_sequence_decode_error_path_test() {
  let first_input = build_input_bytes(<<0:size(256)>>, 0, repeat_byte(0, 4), 0)
  let second_input_without_sequence = <<0:size(256), 0:size(32), 0>>

  let assert Error(decode_err) =
    transaction.deserialize(<<
      transaction_version_1_bytes:bits,
      compact_size(2):bits,
      first_input:bits,
      second_input_without_sequence:bits,
    >>)

  assert check_transaction_decode_error(
      decode_err,
      87,
      "transaction.inputs[1].sequence",
    )
    == UnexpectedEof(4, 0)
}

// ============================================================================
// deserialize: outputs
// ============================================================================

pub fn deserialize_rejects_output_count_when_minimum_output_bytes_are_unavailable_test() {
  // Stop one byte short of the minimum encoded output size.

  let output_count = 1
  let output_padding = <<
    0:little-size({ 1 * { min_output_size_bytes - 1 } * 8 }),
  >>

  let assert Error(decode_err) =
    transaction.deserialize(<<
      transaction_version_1_bytes:bits,
      build_minimal_input_section_bytes():bits,
      compact_size(output_count):bits,
      output_padding:bits,
    >>)

  assert check_transaction_decode_error(
      decode_err,
      46,
      "transaction.outputs.count",
    )
    == InsufficientBytes(
      remaining: min_output_size_bytes - 1,
      claimed: min_output_size_bytes,
    )
}

pub fn deserialize_accepts_legacy_tx_with_zero_outputs_test() {
  // Structural deserialization permits zero outputs; consensus validation does not.
  let output_count = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    build_minimal_input_section_bytes():bits,
    output_count:bits,
    lock_time:bits,
  >>

  let assert Ok(tx) = transaction.deserialize(tx_bytes)
  assert !transaction.is_segwit(tx)
  assert transaction.get_output_count(tx) == 0
  assert transaction.get_outputs(tx) == []
}

pub fn deserialize_reports_indexed_output_value_decode_error_path_test() {
  let first_output =
    build_output_bytes(<<0:little-size(64)>>, repeat_byte(0, 9))
  let partial_second_output_value = <<0:size(32)>>

  let assert Error(decode_err) =
    transaction.deserialize(<<
      transaction_version_1_bytes:bits,
      build_minimal_input_section_bytes():bits,
      compact_size(2):bits,
      first_output:bits,
      partial_second_output_value:bits,
    >>)

  assert check_transaction_decode_error(
      decode_err,
      65,
      "transaction.outputs[1].value",
    )
    == UnexpectedEof(8, 4)
}

pub fn deserialize_accepts_segwit_tx_with_zero_outputs_test() {
  // Structural deserialization permits zero outputs; consensus validation does not.
  let marker = <<0x00>>
  let flag = <<0x01>>
  let input_count = compact_size(1)
  let input = build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)
  let output_count = compact_size(0)
  // One zero-length item counts as witness data.
  let witness_stack = <<
    compact_size(1):bits,
    compact_size(0):bits,
  >>
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    marker:bits,
    flag:bits,
    input_count:bits,
    input:bits,
    output_count:bits,
    witness_stack:bits,
    lock_time:bits,
  >>

  let assert Ok(tx) = transaction.deserialize(tx_bytes)
  assert transaction.is_segwit(tx)
  assert transaction.get_input_count(tx) == 1
  assert transaction.get_output_count(tx) == 0
  assert transaction.get_outputs(tx) == []
}

pub fn deserialize_preserves_single_output_test() {
  let value_satoshis = 100_000_000
  let script_pubkey_bytes = <<0x76, 0xa9, 0x14>>
  let output =
    build_output_bytes(<<value_satoshis:little-size(64)>>, script_pubkey_bytes)
  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    transaction.deserialize(<<
      transaction_version_1_bytes:bits,
      build_minimal_input_section_bytes():bits,
      compact_size(1):bits,
      output:bits,
      lock_time:bits,
    >>)

  assert transaction.get_output_count(tx) == 1
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

  assert actual_script_pubkey_bytes == script_pubkey_bytes
}

pub fn deserialize_preserves_multiple_outputs_test() {
  let output_count = compact_size(3)

  let value1 = <<0:little-size(64)>>
  let value2 = <<100_000_000:little-size(64)>>
  let value3 = <<50_000_000:little-size(64)>>

  let script1_bytes = <<>>
  let script2_bytes = <<0x01>>
  let script3_bytes = <<0xAA, 0xBB>>

  let output1_bytes = build_output_bytes(value1, script1_bytes)
  let output2_bytes = build_output_bytes(value2, script2_bytes)
  let output3_bytes = build_output_bytes(value3, script3_bytes)

  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    transaction.deserialize(<<
      transaction_version_1_bytes:bits,
      build_minimal_input_section_bytes():bits,
      output_count:bits,
      output1_bytes:bits,
      output2_bytes:bits,
      output3_bytes:bits,
      lock_time:bits,
    >>)

  assert transaction.get_output_count(tx) == 3
  let outputs = transaction.get_outputs(tx)
  let assert [output1, output2, output3] = outputs

  let actual_value1 =
    output1
    |> transaction.get_output_value

  assert actual_value1 == 0

  let actual_script1_bytes =
    output1
    |> transaction.get_output_script_pubkey
    |> transaction.get_raw_script_bytes

  assert actual_script1_bytes == script1_bytes

  let actual_value2 =
    output2
    |> transaction.get_output_value

  assert actual_value2 == 100_000_000

  let actual_script2_bytes =
    output2
    |> transaction.get_output_script_pubkey
    |> transaction.get_raw_script_bytes

  assert actual_script2_bytes == script2_bytes

  let actual_value3 =
    output3
    |> transaction.get_output_value

  assert actual_value3 == 50_000_000

  let actual_script3_bytes =
    output3
    |> transaction.get_output_script_pubkey
    |> transaction.get_raw_script_bytes

  assert actual_script3_bytes == script3_bytes
}

pub fn deserialize_preserves_empty_scriptpubkey_test() {
  let value_satoshis = 50_000_000
  let script_pubkey_bytes = <<>>
  let output =
    build_output_bytes(<<value_satoshis:little-size(64)>>, script_pubkey_bytes)
  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    transaction.deserialize(<<
      transaction_version_1_bytes:bits,
      build_minimal_input_section_bytes():bits,
      compact_size(1):bits,
      output:bits,
      lock_time:bits,
    >>)

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

  assert actual_script_pubkey_bytes == <<>>
}

pub fn deserialize_handles_output_value_min_i64_for_target_test() {
  // Create an output with value = minimum i64 (-9223372036854775808)
  // This value exceeds JavaScript's MIN_SAFE_INTEGER, so conversion fails.

  let output_count = compact_size(1)

  // Minimum i64: sign bit set, all other bits clear
  let value_min_i64 = <<0, 0, 0, 0, 0, 0, 0, 0x80>>

  let script_pubkey_length = compact_size(0)

  let output_bytes = <<
    value_min_i64:bits,
    script_pubkey_length:bits,
  >>
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    build_minimal_input_section_bytes():bits,
    output_count:bits,
    output_bytes:bits,
    lock_time:bits,
  >>

  case target.is_javascript() {
    True -> {
      let assert Error(decode_err) = transaction.deserialize(tx_bytes)

      assert check_transaction_decode_error(
          decode_err,
          47,
          "transaction.outputs[0].value",
        )
        == IntegerOutOfRange("-9223372036854775808")
    }

    False -> {
      let min_i64_output_value = {
        // Compute from smaller literals to avoid JavaScript truncation warning
        let two_to_31 = 2_147_483_648
        let two_to_32 = 4_294_967_296
        0 - two_to_31 * two_to_32
      }

      let assert Ok(tx) = transaction.deserialize(tx_bytes)
      let assert [output] = transaction.get_outputs(tx)
      assert transaction.get_output_value(output) == min_i64_output_value
    }
  }
}

pub fn deserialize_rejects_scriptpubkey_length_exceeding_remaining_bytes_test() {
  // Build an output where the scriptPubKey length claims 100 bytes
  // but only 10 remain.

  let output_count = compact_size(1)

  let value = <<0:little-size(64)>>
  let script_pubkey_length = compact_size(100)

  let partial_script_pubkey = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>

  let output_bytes = <<
    value:bits,
    script_pubkey_length:bits,
    partial_script_pubkey:bits,
  >>

  let assert Error(decode_err) =
    transaction.deserialize(<<
      transaction_version_1_bytes:bits,
      build_minimal_input_section_bytes():bits,
      output_count:bits,
      output_bytes:bits,
    >>)

  assert check_transaction_decode_error(
      decode_err,
      55,
      "transaction.outputs[0].script_pubkey.length",
    )
    == InsufficientBytes(claimed: 100, remaining: 10)
}

// ============================================================================
// deserialize: witnesses
// ============================================================================

pub fn deserialize_rejects_segwit_tx_with_zero_inputs_test() {
  let marker = <<0x00>>
  let flag = <<0x01>>
  let input_count = compact_size(0)
  let output_count = compact_size(1)
  let output = build_output_bytes(<<0:little-size(64)>>, <<>>)
  let lock_time = <<0:little-size(32)>>
  let expected_witness_offset = 4 + 2 + 1 + 1 + bit_array.byte_size(output)

  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    marker:bits,
    flag:bits,
    input_count:bits,
    output_count:bits,
    output:bits,
    lock_time:bits,
  >>

  let assert Error(decode_err) = transaction.deserialize(tx_bytes)

  assert check_transaction_decode_error(
      decode_err,
      expected_witness_offset,
      "transaction",
    )
    == SuperfluousWitnessRecord
}

pub fn deserialize_rejects_segwit_tx_with_all_empty_witness_stacks_test() {
  let input1 = build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)
  let input2 =
    build_input_bytes(repeat_byte(1, 32), 1, <<0x01, 0x02>>, 0xFFFFFFFF)

  let output = build_output_bytes(<<1000:little-size(64)>>, <<0x76, 0xa9>>)

  // All-empty witness stacks make extended serialization superfluous.
  let witness_stack1 = compact_size(0)
  let witness_stack2 = compact_size(0)
  let expected_witness_offset =
    4
    + 2
    + 1
    + bit_array.byte_size(input1)
    + bit_array.byte_size(input2)
    + 1
    + bit_array.byte_size(output)

  let tx_bytes =
    assemble_segwit_transaction_bytes([input1, input2], [output], [
      witness_stack1,
      witness_stack2,
    ])

  let assert Error(decode_err) = transaction.deserialize(tx_bytes)

  assert check_transaction_decode_error(
      decode_err,
      expected_witness_offset,
      "transaction",
    )
    == SuperfluousWitnessRecord
}

pub fn deserialize_segwit_tx_allows_empty_stack_when_another_stack_has_item_test() {
  let input1 = build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)
  let input2 =
    build_input_bytes(repeat_byte(1, 32), 1, <<0x01, 0x02>>, 0xFFFFFFFF)
  let output = build_output_bytes(<<1000:little-size(64)>>, <<0x76, 0xa9>>)

  let empty_stack = compact_size(0)
  let stack_with_empty_item = <<
    compact_size(1):bits,
    compact_size(0):bits,
  >>

  let tx_bytes =
    assemble_segwit_transaction_bytes([input1, input2], [output], [
      empty_stack,
      stack_with_empty_item,
    ])

  let assert Ok(tx) = transaction.deserialize(tx_bytes)

  let assert Ok(witnesses) = transaction.get_witnesses(tx)
  let assert [stack1, stack2] = witnesses

  assert transaction.is_witness_stack_empty(stack1)
  let items1 = transaction.get_witness_items(stack1)
  assert items1 == []

  assert !transaction.is_witness_stack_empty(stack2)
  let items2 = transaction.get_witness_items(stack2)
  let assert [empty_item] = items2
  assert transaction.get_witness_item_bytes(empty_item) == <<>>

  assert transaction.serialize(tx) == tx_bytes
}

pub fn deserialize_witness_stack_with_multiple_items_test() {
  let input = build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output_bytes(<<1000:little-size(64)>>, <<>>)

  let witness_item1_data = <<0x48, 0x30, 0x45>>
  let witness_item2_data = <<0x21, 0x02, 0x03>>
  let witness_item3_data = <<0xAA, 0xBB, 0xCC, 0xDD>>

  let witness_item1 = <<
    compact_size(bit_array.byte_size(witness_item1_data)):bits,
    witness_item1_data:bits,
  >>
  let witness_item2 = <<
    compact_size(bit_array.byte_size(witness_item2_data)):bits,
    witness_item2_data:bits,
  >>
  let witness_item3 = <<
    compact_size(bit_array.byte_size(witness_item3_data)):bits,
    witness_item3_data:bits,
  >>

  let witness_stack = <<
    compact_size(3):bits,
    witness_item1:bits,
    witness_item2:bits,
    witness_item3:bits,
  >>

  let tx_bytes =
    assemble_segwit_transaction_bytes([input], [output], [witness_stack])

  let assert Ok(tx) = transaction.deserialize(tx_bytes)

  assert transaction.is_segwit(tx)

  let assert Ok(witnesses) = transaction.get_witnesses(tx)
  let assert [stack] = witnesses

  let items = transaction.get_witness_items(stack)
  let assert [item1, item2, item3] = items

  let data1 = transaction.get_witness_item_bytes(item1)
  let data2 = transaction.get_witness_item_bytes(item2)
  let data3 = transaction.get_witness_item_bytes(item3)

  assert data1 == witness_item1_data
  assert data2 == witness_item2_data
  assert data3 == witness_item3_data

  assert transaction.serialize(tx) == tx_bytes
}

pub fn deserialize_witness_item_with_zero_length_test() {
  let input = build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output_bytes(<<1000:little-size(64)>>, <<>>)

  // A zero-length item still makes the witness record non-empty.
  let witness_stack = <<
    compact_size(1):bits,
    compact_size(0):bits,
  >>

  let tx_bytes =
    assemble_segwit_transaction_bytes([input], [output], [witness_stack])

  let assert Ok(tx) = transaction.deserialize(tx_bytes)

  assert transaction.is_segwit(tx)

  let assert Ok(witnesses) = transaction.get_witnesses(tx)
  let assert [stack] = witnesses

  let items = transaction.get_witness_items(stack)
  let assert [item] = items

  let data = transaction.get_witness_item_bytes(item)
  assert bit_array.byte_size(data) == 0
}

pub fn deserialize_witness_item_length_exceeds_remaining_bytes_test() {
  let input = build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output_bytes(<<1000:little-size(64)>>, <<>>)

  // Build witness stack where item length exceeds remaining bytes
  // Claim 100 bytes for the item but only provide 10 bytes of data
  let witness_item_data = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>
  let witness_stack = <<
    compact_size(1):bits,
    compact_size(100):bits,
    witness_item_data:bits,
  >>

  let tx_bytes =
    assemble_segwit_transaction_bytes([input], [output], [witness_stack])

  let assert Error(decode_err) = transaction.deserialize(tx_bytes)

  // The remaining bytes are the 10-byte payload and 4-byte lock time.
  assert check_transaction_decode_error(
      decode_err,
      59,
      "transaction.witnesses[0].items[0].length",
    )
    == InsufficientBytes(claimed: 100, remaining: 14)
}

pub fn deserialize_rejects_non_minimal_witness_item_count_test() {
  let input = build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output_bytes(<<1000:little-size(64)>>, <<>>)
  let non_minimal_item_count = <<0xFD, 0x01, 0x00>>
  let tx_bytes =
    assemble_segwit_transaction_bytes([input], [output], [
      non_minimal_item_count,
    ])

  let assert Error(decode_err) = transaction.deserialize(tx_bytes)

  assert check_transaction_decode_error(
      decode_err,
      58,
      "transaction.witnesses[0].items.count",
    )
    == NonMinimalCompactSize(3, 1)
}

pub fn deserialize_reports_truncated_witness_item_count_test() {
  let input = build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output_bytes(<<1000:little-size(64)>>, <<>>)

  // End the byte stream inside the CompactSize value so later fields cannot
  // complete the encoding.
  let truncated_item_count = <<0xFD, 0x01>>
  let tx_bytes = <<
    transaction_version_1_bytes:bits,
    0x00,
    0x01,
    compact_size(1):bits,
    input:bits,
    compact_size(1):bits,
    output:bits,
    truncated_item_count:bits,
  >>

  let assert Error(decode_err) = transaction.deserialize(tx_bytes)

  assert check_transaction_decode_error(
      decode_err,
      58,
      "transaction.witnesses[0].items.count",
    )
    == UnexpectedEof(bytes_needed: 2, remaining: 1)
}

pub fn deserialize_rejects_non_minimal_witness_item_length_test() {
  let input = build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output_bytes(<<1000:little-size(64)>>, <<>>)
  let witness_stack = <<
    compact_size(1):bits,
    0xFD,
    0x01,
    0x00,
  >>
  let tx_bytes =
    assemble_segwit_transaction_bytes([input], [output], [witness_stack])

  let assert Error(decode_err) = transaction.deserialize(tx_bytes)

  assert check_transaction_decode_error(
      decode_err,
      59,
      "transaction.witnesses[0].items[0].length",
    )
    == NonMinimalCompactSize(3, 1)
}
