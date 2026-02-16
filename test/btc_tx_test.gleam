import btc_tx.{
  AtField, AtInput, AtOutput, AtWitnessItem, AtWitnessStack,
  CoinbaseWithMultipleInputs, CompactSizeError, DecodePolicy, InInputs,
  InOutputs, InTransaction, InsufficientBytes, InvalidCoinbaseScriptSigLength,
  InvalidSegWitMarkerFlag, MultipleCoinbaseInputs, NegativeOutputValue, NoInputs,
  NoOutputs, OutputValueExceedsSupply, ParseFailed, PolicyLimitExceeded,
  ReaderError, TotalOutputValueExceedsSupply, TrailingBytes, WitnessPolicy,
}
import gleam/bit_array
import gleam/list
import gleeunit
import internal/compact_size
import internal/reader

const legacy_v1_tx = "0100000001098ebbff18cf40ad3ba02ded7d3558d7ca6ee96c990c8fdfb99cf61d88ad2c680100000000ffffffff01f0a29a3b000000001976a914012e2ba6a051c033b03d712ca2ea00a35eac1e7988ac00000000"

const segwit_v1_tx = "01000000000101db6b1b20aa0fd7b23880be2ecbd4a98130974cf4748fb66092ac4d3ceb1a5477010000001716001479091972186c449eb1ded22b78e40d009bdf0089feffffff02b8b4eb0b000000001976a914a457b684d7f0d539a46a45bbc043f35b59d0d96388ac0008af2f000000001976a914fd270b1ee6abcaea97fea7ad0402e8bd8ad6d77c88ac02473044022047ac8e878352d3ebbde1c94ce3a10d057c24175747116f8288e5d794d12d482f0220217f36a485cae903c713331d877c1f64677e3622ad4010726870540656fe9dcb012103ad1d8e89212f0b92c74d23bb710c00662ad1470198ac48c43f7d6f93a2a2687392040000"

const legacy_v2_tx = "02000000019945a5a440f2d3712ff095cb1efefada1cc52e139defedb92a313daed49d5678010000006a473044022031b6a6b79c666d5568a9ac7c116cacf277e11521aebc6794e2b415ef8c87c899022001fe272499ea32e6e1f6e45eb656973fbb55252f7acc64e1e1ac70837d5b7d9f0121023dec241e4851d1ec1513a48800552bae7be155c6542629636bcaa672eee971dcffffffff01a70200000000000017a9148ce773d254dc5df886b95848880e0b40f10564328700000000"

const version1 = <<1:little-size(32)>>

const min_txin_size_bytes = 41

const min_txout_size_bytes = 9

pub fn main() -> Nil {
  gleeunit.main()
}

// ============================================================================
// Version and SegWit Detection
// ============================================================================

pub fn decode_legacy_full_tx_sets_version_and_is_segwit_false_test() {
  let assert Ok(result) = btc_tx.decode_hex(legacy_v1_tx)

  assert btc_tx.get_version(result) == 1
  assert !btc_tx.is_segwit(result)
}

pub fn decode_legacy_tx_parses_lock_time_test() {
  let assert Ok(result) = btc_tx.decode_hex(legacy_v1_tx)

  // legacy_v1_tx has lock_time = 0 (ends with 00000000 in little-endian)
  assert btc_tx.get_lock_time(result) == 0
}

pub fn decode_segwit_full_tx_sets_version_and_is_segwit_true_test() {
  let assert Ok(result) = btc_tx.decode_hex(segwit_v1_tx)

  assert btc_tx.get_version(result) == 1
  assert btc_tx.is_segwit(result)
}

pub fn decode_segwit_tx_parses_lock_time_test() {
  let assert Ok(result) = btc_tx.decode_hex(segwit_v1_tx)

  // segwit_v1_tx ends with "92040000" which in little-endian is 0x00000492 = 1170
  assert btc_tx.get_lock_time(result) == 1170
}

pub fn decode_legacy_v2_parses_version_2_test() {
  let assert Ok(result) = btc_tx.decode_hex(legacy_v2_tx)

  assert btc_tx.get_version(result) == 2
  assert !btc_tx.is_segwit(result)
}

pub fn decode_errors_when_input_shorter_than_4_bytes_test() {
  let assert Error(ParseFailed(parse_err)) = btc_tx.decode_hex("010203")

  assert btc_tx.parse_error_offset(parse_err) == 0

  assert btc_tx.parse_error_kind(parse_err)
    == ReaderError(reader.UnexpectedEof(4, 3))

  assert btc_tx.parse_error_ctx(parse_err)
    == [InTransaction, AtField("version")]
}

pub fn decode_does_not_misclassify_segwit_when_discriminator_is_missing_test() {
  let assert Error(ParseFailed(parse_err)) = btc_tx.decode(version1)

  assert btc_tx.parse_error_offset(parse_err) == 4

  assert btc_tx.parse_error_kind(parse_err)
    == CompactSizeError(compact_size.ReaderError(reader.UnexpectedEof(1, 0)))

  assert btc_tx.parse_error_ctx(parse_err)
    == [InTransaction, InInputs, AtField("vin_count")]
}

pub fn decode_does_not_misclassify_segwit_when_discriminator_is_truncated_test() {
  let marker = <<0:size(8)>>

  let assert Error(ParseFailed(parse_err)) =
    btc_tx.decode(<<version1:bits, marker:bits>>)

  assert btc_tx.parse_error_offset(parse_err) == 5

  assert btc_tx.parse_error_kind(parse_err)
    == CompactSizeError(compact_size.ReaderError(reader.UnexpectedEof(1, 0)))

  assert btc_tx.parse_error_ctx(parse_err)
    == [InTransaction, InOutputs, AtField("vout_count")]
}

pub fn decode_returns_invalid_segwit_marker_flag_error_test() {
  let marker = <<0:size(8)>>
  let flag = <<2:little-size(8)>>

  let assert Error(ParseFailed(parse_err)) =
    btc_tx.decode(<<version1:bits, marker:bits, flag:bits>>)

  assert btc_tx.parse_error_offset(parse_err) == 4
  assert btc_tx.parse_error_kind(parse_err) == InvalidSegWitMarkerFlag(0, 2)
  assert btc_tx.parse_error_ctx(parse_err)
    == [InTransaction, AtField("segwit_discriminator")]
}

pub fn decode_rejects_segwit_marker_with_zero_flag_test() {
  // Construct: version (4 bytes) + 0x00 + 0x00 which triggers the
  // InvalidSegwitMarkerFlag error because marker=0x00 but flag=0x00 (not 0x01).
  // This validates that transactions attempting to use the SegWit marker
  // with an invalid flag are properly rejected.

  let vin_count = 0
  let input_padding = <<0:little-size({ 1 * min_txin_size_bytes * 8 })>>

  let assert Error(ParseFailed(parse_err)) =
    btc_tx.decode(<<
      version1:bits,
      compact_size(vin_count):bits,
      input_padding:bits,
    >>)

  assert btc_tx.parse_error_offset(parse_err) == 4
  assert btc_tx.parse_error_kind(parse_err) == InvalidSegWitMarkerFlag(0, 0)
  assert btc_tx.parse_error_ctx(parse_err)
    == [InTransaction, AtField("segwit_discriminator")]
}

// ============================================================================
// Input Count (vin_count) Parsing and Validation
// ============================================================================

pub fn validate_vin_count_minimum_succeeds_test() {
  // version (4 bytes) + vin_count (CompactSize = 0x01) + 41 bytes padding

  let vin_count = 1
  let input_padding = <<0:little-size({ 1 * min_txin_size_bytes * 8 })>>
  let lock_time = <<0:little-size(32)>>

  let assert Ok(_) =
    btc_tx.decode(<<
      version1:bits,
      compact_size(vin_count):bits,
      input_padding:bits,
      build_minimal_output():bits,
      lock_time:bits,
    >>)
}

pub fn validate_vin_count_within_limits_succeeds_test() {
  // version (4 bytes) + vin_count (CompactSize = 0x02) + padding for >= 2 inputs
  // padding: 2 * 41 = 82 bytes -> 82 * 8 = 656 bits
  // enforce a policy that permits at least 2 inputs

  let vin_count = 2
  let input_padding = <<0:little-size({ 2 * min_txin_size_bytes * 8 })>>
  let lock_time = <<0:little-size(32)>>

  let assert Ok(_) =
    btc_tx.decode_with_policy(
      <<
        version1:bits,
        compact_size(vin_count):bits,
        input_padding:bits,
        build_minimal_output():bits,
        lock_time:bits,
      >>,
      DecodePolicy(..btc_tx.default_policy, max_vin_count: 10),
    )
}

pub fn validate_vin_count_equals_policy_succeeds_test() {
  // Pick a small policy (3). Create vin_count == 3 and supply >= 3 * 41 bytes padding
  // so that max_inputs_by_bytes >= policy and the policy is the active cap.
  // should succeed when enforcing a policy that allows exactly 3 inputs

  let vin_count = 3
  let input_padding = <<0:little-size({ 3 * min_txin_size_bytes * 8 })>>
  let lock_time = <<0:little-size(32)>>

  let assert Ok(_) =
    btc_tx.decode_with_policy(
      <<
        version1:bits,
        compact_size(vin_count):bits,
        input_padding:bits,
        build_minimal_output():bits,
        lock_time:bits,
      >>,
      DecodePolicy(..btc_tx.default_policy, max_vin_count: 3),
    )
}

pub fn validate_vin_count_exceeds_policy_error_test() {
  // Use a small policy (2). Set vin_count == 3 and provide padding for
  // 3 inputs (3 * 41 = 123 bytes) so max_inputs_by_bytes == 3 (not the limiting factor).
  // With policy == 2, the policy limit is stricter, so validator should reject
  // vin_count == 3 with PolicyLimitExceeded.

  let vin_count = 3
  let input_padding = <<0:little-size({ 3 * min_txin_size_bytes * 8 })>>

  let assert Error(ParseFailed(parse_err)) =
    btc_tx.decode_with_policy(
      <<version1:bits, vin_count:size(8), input_padding:bits>>,
      DecodePolicy(..btc_tx.default_policy, max_vin_count: 2),
    )

  assert btc_tx.parse_error_offset(parse_err) == 4

  assert btc_tx.parse_error_kind(parse_err) == PolicyLimitExceeded(vin_count, 2)

  assert btc_tx.parse_error_ctx(parse_err)
    == [InTransaction, InInputs, AtField("vin_count")]
}

pub fn validate_vin_count_exceeds_structural_error_test() {
  // Provide padding for exactly 2 inputs (2 * 41 = 82 bytes) so
  // max_inputs_by_bytes == 2. Use a large policy so the structural
  // limit is the active cap, then assert vin_count == 3 is rejected.

  let vin_count = 3
  let input_padding = <<0:little-size({ 2 * min_txin_size_bytes * 8 })>>

  let assert Error(ParseFailed(parse_err)) =
    btc_tx.decode_with_policy(
      <<version1:bits, compact_size(vin_count):bits, input_padding:bits>>,
      DecodePolicy(..btc_tx.default_policy, max_vin_count: 100),
    )

  assert btc_tx.parse_error_offset(parse_err) == 4

  assert btc_tx.parse_error_kind(parse_err)
    == InsufficientBytes(
      claimed: 2 * min_txin_size_bytes + 1,
      remaining: 2 * min_txin_size_bytes,
    )

  assert btc_tx.parse_error_ctx(parse_err)
    == [InTransaction, InInputs, AtField("vin_count")]
}

pub fn validate_vin_count_structural_boundary_succeeds_test() {
  // Provide padding for exactly 2 inputs (2 * 41 = 82 bytes) so
  // max_inputs_by_bytes == 2. Use a large policy so the structural
  // limit is the active cap, then assert vin_count == 2 succeeds.

  let vin_count = 2
  let input_padding = <<0:little-size({ vin_count * min_txin_size_bytes * 8 })>>
  let lock_time = <<0:little-size(32)>>

  let assert Ok(_) =
    btc_tx.decode_with_policy(
      <<
        version1:bits,
        compact_size(vin_count):bits,
        input_padding:bits,
        build_minimal_output():bits,
        lock_time:bits,
      >>,
      DecodePolicy(..btc_tx.default_policy, max_vin_count: 100),
    )
}

pub fn validate_vin_count_insufficient_bytes_for_inputs_test() {
  // Construct: version (4 bytes) + vin_count (CompactSize = 0x01) + 40 bytes
  // of padding so that `remaining < min_txin_size` and the validator
  // produces a LengthTooLarge error.

  let vin_count = 1
  let input_padding = <<0:little-size({ 1 * { min_txin_size_bytes - 1 } * 8 })>>

  let assert Error(ParseFailed(parse_err)) =
    btc_tx.decode(<<
      version1:bits,
      compact_size(vin_count):bits,
      input_padding:bits,
    >>)

  assert btc_tx.parse_error_offset(parse_err) == 4

  assert btc_tx.parse_error_kind(parse_err)
    == InsufficientBytes(
      remaining: min_txin_size_bytes - 1,
      claimed: min_txin_size_bytes,
    )

  assert btc_tx.parse_error_ctx(parse_err)
    == [InTransaction, InInputs, AtField("vin_count")]
}

pub fn decode_accepts_segwit_tx_with_zero_inputs_test() {
  // Demonstrate that a transaction with 0 inputs can be represented in bytes
  // and successfully decoded (though it would fail consensus validation).
  // Note: Legacy format cannot encode 0 inputs because the 0x00 byte conflicts
  // with SegWit marker detection, making it impossible to distinguish from SegWit.
  let marker = <<0x00>>
  let flag = <<0x01>>
  let vin_count = compact_size(0)
  let vout_count = compact_size(1)
  let output = build_output(<<0:little-size(64)>>, <<>>)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    marker:bits,
    flag:bits,
    vin_count:bits,
    vout_count:bits,
    output:bits,
    // Empty witness section (0 witness stacks for 0 inputs)
    lock_time:bits,
  >>

  // Should decode successfully as Unvalidated
  let assert Ok(tx) = btc_tx.decode(tx_bytes)
  assert btc_tx.is_segwit(tx)
  assert list.is_empty(btc_tx.get_inputs(tx))
}

// ============================================================================
// Input Structure Parsing
// ============================================================================

pub fn decode_parses_single_input_test() {
  let vin_count = compact_size(1)

  // Create a transaction with a single input with specific prev_out values
  let prev_txid_bytes = repeat_byte(1, 32)
  let vout = 5
  let script_sig_bytes = <<0x48, 0x30, 0x45, 0x02, 0x21>>
  let sequence = 0xFFFFFFFE

  let input_bytes =
    build_input(prev_txid_bytes, vout, script_sig_bytes, sequence)

  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    btc_tx.decode(<<
      version1:bits,
      vin_count:bits,
      input_bytes:bits,
      build_minimal_output():bits,
      lock_time:bits,
    >>)

  // Verify we parsed exactly one input
  let inputs = btc_tx.get_inputs(tx)
  let assert [first_input] = inputs

  // Verify prev_out properties
  let prev_out = btc_tx.get_input_prev_out(first_input)

  let actual_prev_out_txid_bytes =
    prev_out
    |> btc_tx.get_prev_out_txid
    |> btc_tx.txid_to_bytes

  assert actual_prev_out_txid_bytes == prev_txid_bytes
  assert btc_tx.get_prev_out_vout(prev_out) == vout

  // Verify sequence
  assert btc_tx.get_input_sequence(first_input) == sequence

  // Verify scriptSig
  let actual_script_sig_bytes =
    first_input
    |> btc_tx.get_input_script_sig
    |> btc_tx.get_raw_script_bytes

  assert actual_script_sig_bytes == script_sig_bytes
}

pub fn decode_parses_coinbase_input_test() {
  let vin_count = compact_size(1)

  let prev_txid_bytes = <<0:size(256)>>
  let vout = 0xFFFFFFFF
  let script_sig_bytes = <<>>
  let sequence = 0xFFFFFFFE

  let input_bytes =
    build_input(prev_txid_bytes, vout, script_sig_bytes, sequence)

  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    btc_tx.decode(<<
      version1:bits,
      vin_count:bits,
      input_bytes:bits,
      build_minimal_output():bits,
      lock_time:bits,
    >>)

  let inputs = btc_tx.get_inputs(tx)
  let assert [first_input] = inputs

  let prev_out = btc_tx.get_input_prev_out(first_input)

  assert btc_tx.prev_out_is_coinbase(prev_out)
}

pub fn decode_parses_empty_scriptsig_test() {
  let vin_count = compact_size(1)

  let prev_txid_bytes = <<0:size(256)>>
  let vout = 0xFFFFFFFF
  let script_sig_bytes = <<>>
  let sequence = 0xFFFFFFFE

  let input_bytes =
    build_input(prev_txid_bytes, vout, script_sig_bytes, sequence)

  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    btc_tx.decode(<<
      version1:bits,
      vin_count:bits,
      input_bytes:bits,
      build_minimal_output():bits,
      lock_time:bits,
    >>)

  let inputs = btc_tx.get_inputs(tx)
  let assert [first_input] = inputs

  let actual_script_sig_bytes =
    first_input
    |> btc_tx.get_input_script_sig
    |> btc_tx.get_raw_script_bytes

  assert actual_script_sig_bytes == <<>>
}

pub fn decode_parses_multiple_inputs_test() {
  let vin_count = compact_size(3)

  let prev1_txid_bytes = repeat_byte(1, 32)
  let prev2_txid_bytes = repeat_byte(2, 32)
  let prev3_txid_bytes = repeat_byte(3, 32)

  let vout1 = 0
  let vout2 = 1
  let vout3 = 2

  let sig1_bytes = <<>>
  let sig2_bytes = <<0x01>>
  let sig3_bytes = <<0xAA, 0xBB>>

  let seq1 = 0xFFFFFFFF
  let seq2 = 0
  let seq3 = 1

  let in1_bytes = build_input(prev1_txid_bytes, vout1, sig1_bytes, seq1)
  let in2_bytes = build_input(prev2_txid_bytes, vout2, sig2_bytes, seq2)
  let in3_bytes = build_input(prev3_txid_bytes, vout3, sig3_bytes, seq3)

  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    btc_tx.decode(<<
      version1:bits,
      vin_count:bits,
      in1_bytes:bits,
      in2_bytes:bits,
      in3_bytes:bits,
      build_minimal_output():bits,
      lock_time:bits,
    >>)

  let inputs = btc_tx.get_inputs(tx)
  let assert [i1, i2, i3] = inputs

  // input 1
  let prev_out1 = btc_tx.get_input_prev_out(i1)

  let actual_prev1_txid_bytes =
    prev_out1
    |> btc_tx.get_prev_out_txid
    |> btc_tx.txid_to_bytes

  assert actual_prev1_txid_bytes == prev1_txid_bytes
  assert btc_tx.get_prev_out_vout(prev_out1) == vout1
  assert btc_tx.get_input_sequence(i1) == seq1
  assert btc_tx.get_raw_script_bytes(btc_tx.get_input_script_sig(i1))
    == sig1_bytes

  // input 2
  let prev_out2 = btc_tx.get_input_prev_out(i2)

  let actual_prev2_txid_bytes =
    prev_out2
    |> btc_tx.get_prev_out_txid
    |> btc_tx.txid_to_bytes

  assert actual_prev2_txid_bytes == prev2_txid_bytes
  assert btc_tx.get_prev_out_vout(prev_out2) == vout2
  assert btc_tx.get_input_sequence(i2) == seq2
  assert btc_tx.get_raw_script_bytes(btc_tx.get_input_script_sig(i2))
    == sig2_bytes

  // input 3
  let prev_out3 = btc_tx.get_input_prev_out(i3)

  let actual_prev3_txid_bytes =
    prev_out3
    |> btc_tx.get_prev_out_txid
    |> btc_tx.txid_to_bytes

  assert actual_prev3_txid_bytes == prev3_txid_bytes
  assert btc_tx.get_prev_out_vout(prev_out3) == vout3
  assert btc_tx.get_input_sequence(i3) == seq3
  assert btc_tx.get_raw_script_bytes(btc_tx.get_input_script_sig(i3))
    == sig3_bytes
}

// ============================================================================
// ScriptSig Validation
// ============================================================================

pub fn decode_rejects_scriptsig_exceeding_max_size_test() {
  // Build a transaction with scriptSig_len = 10,001 (exceeds MAX_SCRIPT_SIZE of 10,000)

  let vin_count = compact_size(1)

  let prev_txid = <<0:size(256)>>
  let vout = 0
  let script_sig = <<0:size({ 10_001 * 8 })>>
  let sequence = 0

  let input_bytes = build_input(prev_txid, vout, script_sig, sequence)

  let assert Error(ParseFailed(parse_err)) =
    btc_tx.decode(<<
      version1:bits,
      vin_count:bits,
      input_bytes:bits,
    >>)

  assert btc_tx.parse_error_offset(parse_err) == 41

  assert btc_tx.parse_error_kind(parse_err)
    == PolicyLimitExceeded(10_001, 10_000)

  assert btc_tx.parse_error_ctx(parse_err)
    == [InTransaction, InInputs, AtInput(0), AtField("scriptSig_len")]
}

pub fn decode_rejects_scriptsig_length_exceeds_remaining_bytes_test() {
  // Build a transaction where scriptSig_len claims 100 bytes but only 10 bytes remain
  let vin_count = compact_size(1)

  let prev_txid = <<0:size(256)>>
  let vout = <<0:little-size(32)>>

  let script_sig_len = compact_size(100)

  // Only provide 10 bytes of actual data (not enough for the claimed 100)
  let partial_script_sig = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>

  let input_bytes = <<
    prev_txid:bits,
    vout:bits,
    script_sig_len:bits,
    partial_script_sig:bits,
  >>

  let assert Error(ParseFailed(parse_err)) =
    btc_tx.decode(<<
      version1:bits,
      vin_count:bits,
      input_bytes:bits,
    >>)

  assert btc_tx.parse_error_offset(parse_err) == 41

  assert btc_tx.parse_error_kind(parse_err)
    == InsufficientBytes(claimed: 100, remaining: 10)

  assert btc_tx.parse_error_ctx(parse_err)
    == [InTransaction, InInputs, AtInput(0), AtField("scriptSig_len")]
}

pub fn decode_returns_error_with_current_input_index_test() {
  // Build a transaction with 2 inputs where the first parses successfully
  // but the second one has an error, verifying that Input(1) appears in the error context.

  let vin_count = compact_size(2)

  // First input: valid and complete (41 bytes)
  let input1_bytes = build_input(<<0:size(256)>>, 0, <<>>, 0)

  // Second input: claims 100 bytes for scriptSig but we only provide 4 more bytes
  let input2_prev_txid = <<0:size(256)>>
  let input2_vout = <<0:little-size(32)>>
  let input2_script_sig_len = compact_size(100)
  let input2_partial = <<
    input2_prev_txid:bits,
    input2_vout:bits,
    input2_script_sig_len:bits,
  >>
  // Only provide 4 more bytes (for sequence) instead of 100 + 4
  let remaining_bytes = <<0:little-size(32)>>

  let assert Error(ParseFailed(parse_err)) =
    btc_tx.decode(<<
      version1:bits,
      vin_count:bits,
      input1_bytes:bits,
      input2_partial:bits,
      remaining_bytes:bits,
    >>)

  // Verify the error occurred in the second input (index 1)
  assert btc_tx.parse_error_kind(parse_err)
    == InsufficientBytes(claimed: 100, remaining: 4)

  assert btc_tx.parse_error_ctx(parse_err)
    == [InTransaction, InInputs, AtInput(1), AtField("scriptSig_len")]
}

// ============================================================================
// Output Count (vout_count) Parsing and Validation
// ============================================================================

pub fn validate_vout_count_minimum_succeeds_test() {
  let lock_time = <<0:little-size(32)>>

  let assert Ok(_) =
    btc_tx.decode(<<
      version1:bits,
      build_minimal_input():bits,
      build_minimal_output():bits,
      lock_time:bits,
    >>)
}

pub fn validate_vout_count_within_limits_succeeds_test() {
  // enforce a policy that permits at least 2 outputs

  let vout_count = 2
  let output1 = build_output(<<0:little-size(64)>>, <<>>)
  let output2 = build_output(<<0:little-size(64)>>, <<>>)
  let lock_time = <<0:little-size(32)>>

  let assert Ok(_) =
    btc_tx.decode_with_policy(
      <<
        version1:bits,
        build_minimal_input():bits,
        compact_size(vout_count):bits,
        output1:bits,
        output2:bits,
        lock_time:bits,
      >>,
      DecodePolicy(..btc_tx.default_policy, max_vout_count: 10),
    )
}

pub fn validate_vout_count_equals_policy_succeeds_test() {
  // Pick a small policy (3). Create vout_count == 3 and supply 3 minimal outputs
  // so that max_outputs_by_bytes >= policy and the policy is the active cap.
  // should succeed when enforcing a policy that allows exactly 3 outputs

  let vout_count = 3
  let output1 = build_output(<<0:little-size(64)>>, <<>>)
  let output2 = build_output(<<0:little-size(64)>>, <<>>)
  let output3 = build_output(<<0:little-size(64)>>, <<>>)
  let lock_time = <<0:little-size(32)>>

  let assert Ok(_) =
    btc_tx.decode_with_policy(
      <<
        version1:bits,
        build_minimal_input():bits,
        compact_size(vout_count):bits,
        output1:bits,
        output2:bits,
        output3:bits,
        lock_time:bits,
      >>,
      DecodePolicy(..btc_tx.default_policy, max_vout_count: 3),
    )
}

pub fn validate_vout_count_exceeds_policy_error_test() {
  // Use a small policy (2). Set vout_count == 3 and provide 3 outputs
  // (3 * 9 = 27 bytes) so max_outputs_by_bytes == 3 (not the limiting factor).
  // With policy == 2, the policy limit is stricter, so validator should reject
  // vout_count == 3 with PolicyLimitExceeded.

  let vout_count = 3
  let output1 = build_output(<<0:little-size(64)>>, <<>>)
  let output2 = build_output(<<0:little-size(64)>>, <<>>)
  let output3 = build_output(<<0:little-size(64)>>, <<>>)
  let lock_time = <<0:little-size(32)>>

  let assert Error(ParseFailed(parse_err)) =
    btc_tx.decode_with_policy(
      <<
        version1:bits,
        build_minimal_input():bits,
        compact_size(vout_count):bits,
        output1:bits,
        output2:bits,
        output3:bits,
        lock_time:bits,
      >>,
      DecodePolicy(..btc_tx.default_policy, max_vout_count: 2),
    )

  assert btc_tx.parse_error_kind(parse_err)
    == PolicyLimitExceeded(vout_count, 2)

  assert btc_tx.parse_error_ctx(parse_err)
    == [InTransaction, InOutputs, AtField("vout_count")]
}

pub fn validate_vout_count_exceeds_structural_error_test() {
  // Provide exactly 2 outputs (2 * 9 = 18 bytes) so max_outputs_by_bytes == 2.
  // Use a large policy (100) so the structural limit is the active cap,
  // then assert vout_count == 3 is rejected.

  let vout_count = 3
  let output1 = build_output(<<0:little-size(64)>>, <<>>)
  let output2 = build_output(<<0:little-size(64)>>, <<>>)

  let assert Error(ParseFailed(parse_err)) =
    btc_tx.decode_with_policy(
      <<
        version1:bits,
        build_minimal_input():bits,
        compact_size(vout_count):bits,
        output1:bits,
        output2:bits,
      >>,
      DecodePolicy(..btc_tx.default_policy, max_vout_count: 100),
    )

  assert btc_tx.parse_error_offset(parse_err) == 46

  assert btc_tx.parse_error_kind(parse_err)
    == InsufficientBytes(
      claimed: 2 * min_txout_size_bytes + 1,
      remaining: 2 * min_txout_size_bytes,
    )

  assert btc_tx.parse_error_ctx(parse_err)
    == [InTransaction, InOutputs, AtField("vout_count")]
}

pub fn validate_vout_count_structural_boundary_succeeds_test() {
  // Provide exactly 2 outputs (2 * 9 = 18 bytes) so max_outputs_by_bytes == 2.
  // Use a large policy (100) so the structural limit is the active cap,
  // then assert vout_count == 2 succeeds.

  let vout_count = 2
  let output1 = build_output(<<0:little-size(64)>>, <<>>)
  let output2 = build_output(<<0:little-size(64)>>, <<>>)
  let lock_time = <<0:little-size(32)>>

  let assert Ok(_) =
    btc_tx.decode_with_policy(
      <<
        version1:bits,
        build_minimal_input():bits,
        compact_size(vout_count):bits,
        output1:bits,
        output2:bits,
        lock_time:bits,
      >>,
      DecodePolicy(..btc_tx.default_policy, max_vout_count: 100),
    )
}

pub fn validate_vout_count_insufficient_bytes_for_outputs_test() {
  // Construct: version (4 bytes) + vin_count (1) + input (41 bytes) + vout_count (1) + 8 bytes
  // of padding so that `remaining < min_txout_size` and the validator
  // produces a InsufficientBytes error.

  let vout_count = 1
  let output_padding = <<
    0:little-size({ 1 * { min_txout_size_bytes - 1 } * 8 }),
  >>

  let assert Error(ParseFailed(parse_err)) =
    btc_tx.decode(<<
      version1:bits,
      build_minimal_input():bits,
      compact_size(vout_count):bits,
      output_padding:bits,
    >>)

  assert btc_tx.parse_error_kind(parse_err)
    == InsufficientBytes(
      remaining: min_txout_size_bytes - 1,
      claimed: min_txout_size_bytes,
    )

  assert btc_tx.parse_error_ctx(parse_err)
    == [InTransaction, InOutputs, AtField("vout_count")]
}

pub fn decode_accepts_legacy_tx_with_zero_outputs_test() {
  // Demonstrate that a legacy transaction with 0 outputs can be represented
  // in bytes and successfully decoded (though it would fail consensus validation).
  let vout_count = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    build_minimal_input():bits,
    vout_count:bits,
    lock_time:bits,
  >>

  // Should decode successfully as Unvalidated
  let assert Ok(tx) = btc_tx.decode(tx_bytes)
  assert !btc_tx.is_segwit(tx)
  assert list.is_empty(btc_tx.get_outputs(tx))
}

pub fn decode_accepts_segwit_tx_with_zero_outputs_test() {
  // Demonstrate that a SegWit transaction with 0 outputs can be represented
  // in bytes and successfully decoded (though it would fail consensus validation).
  let marker = <<0x00>>
  let flag = <<0x01>>
  let vin_count = compact_size(1)
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let vout_count = compact_size(0)
  let witness_stack_len = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    marker:bits,
    flag:bits,
    vin_count:bits,
    input:bits,
    vout_count:bits,
    // Witness section: 1 empty witness stack for the 1 input
    witness_stack_len:bits,
    lock_time:bits,
  >>

  // Should decode successfully as Unvalidated
  let assert Ok(tx) = btc_tx.decode(tx_bytes)
  assert btc_tx.is_segwit(tx)
  assert list.is_empty(btc_tx.get_outputs(tx))
}

// ============================================================================
// Output Structure Parsing
// ============================================================================

pub fn decode_parses_single_output_test() {
  // Create a transaction with a single output with specific properties
  let value_satoshis = 100_000_000
  let script_pubkey_bytes = <<0x76, 0xa9, 0x14>>
  let output =
    build_output(<<value_satoshis:little-size(64)>>, script_pubkey_bytes)
  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    btc_tx.decode(<<
      version1:bits,
      build_minimal_input():bits,
      compact_size(1):bits,
      output:bits,
      lock_time:bits,
    >>)

  // Verify we parsed exactly one output
  let outputs = btc_tx.get_outputs(tx)
  let assert [first_output] = outputs

  // Verify output properties
  let actual_value =
    first_output
    |> btc_tx.get_output_value
    |> btc_tx.satoshis_to_int

  assert actual_value == value_satoshis

  let actual_script_pubkey_bytes =
    first_output
    |> btc_tx.get_output_script_pubkey
    |> btc_tx.get_raw_script_bytes

  assert actual_script_pubkey_bytes == script_pubkey_bytes
}

pub fn decode_parses_multiple_outputs_test() {
  let vout_count = compact_size(3)

  let value1 = <<0:little-size(64)>>
  let value2 = <<100_000_000:little-size(64)>>
  let value3 = <<50_000_000:little-size(64)>>

  let script1_bytes = <<>>
  let script2_bytes = <<0x01>>
  let script3_bytes = <<0xAA, 0xBB>>

  let out1_bytes = build_output(value1, script1_bytes)
  let out2_bytes = build_output(value2, script2_bytes)
  let out3_bytes = build_output(value3, script3_bytes)

  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    btc_tx.decode(<<
      version1:bits,
      build_minimal_input():bits,
      vout_count:bits,
      out1_bytes:bits,
      out2_bytes:bits,
      out3_bytes:bits,
      lock_time:bits,
    >>)

  let outputs = btc_tx.get_outputs(tx)
  let assert [o1, o2, o3] = outputs

  // output 1
  let actual_value1 =
    o1
    |> btc_tx.get_output_value
    |> btc_tx.satoshis_to_int

  assert actual_value1 == 0

  let actual_script1_bytes =
    o1
    |> btc_tx.get_output_script_pubkey
    |> btc_tx.get_raw_script_bytes

  assert actual_script1_bytes == script1_bytes

  // output 2
  let actual_value2 =
    o2
    |> btc_tx.get_output_value
    |> btc_tx.satoshis_to_int

  assert actual_value2 == 100_000_000

  let actual_script2_bytes =
    o2
    |> btc_tx.get_output_script_pubkey
    |> btc_tx.get_raw_script_bytes

  assert actual_script2_bytes == script2_bytes

  // output 3
  let actual_value3 =
    o3
    |> btc_tx.get_output_value
    |> btc_tx.satoshis_to_int

  assert actual_value3 == 50_000_000

  let actual_script3_bytes =
    o3
    |> btc_tx.get_output_script_pubkey
    |> btc_tx.get_raw_script_bytes

  assert actual_script3_bytes == script3_bytes
}

pub fn decode_parses_empty_scriptpubkey_test() {
  // Create a transaction with an output that has empty scriptPubKey
  let value_satoshis = 50_000_000
  let script_pubkey_bytes = <<>>
  let output =
    build_output(<<value_satoshis:little-size(64)>>, script_pubkey_bytes)
  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    btc_tx.decode(<<
      version1:bits,
      build_minimal_input():bits,
      compact_size(1):bits,
      output:bits,
      lock_time:bits,
    >>)

  // Verify we parsed exactly one output
  let outputs = btc_tx.get_outputs(tx)
  let assert [first_output] = outputs

  // Verify output properties
  let actual_value =
    first_output
    |> btc_tx.get_output_value
    |> btc_tx.satoshis_to_int

  assert actual_value == value_satoshis

  let actual_script_pubkey_bytes =
    first_output
    |> btc_tx.get_output_script_pubkey
    |> btc_tx.get_raw_script_bytes

  assert actual_script_pubkey_bytes == <<>>
}

// ============================================================================
// Output Value Validation
// ============================================================================

@target(javascript)
pub fn decode_rejects_output_value_min_i64_js_test() {
  // Create an output with value = minimum i64 (-9223372036854775808)
  // This value exceeds JavaScript's MIN_SAFE_INTEGER, so conversion fails.

  let vout_count = compact_size(1)

  // Minimum i64: sign bit set, all other bits clear
  let value_min_i64 = <<0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80>>

  let script_pubkey_len = compact_size(0)

  let output_bytes = <<
    value_min_i64:bits,
    script_pubkey_len:bits,
  >>

  let assert Error(ParseFailed(parse_err)) =
    btc_tx.decode(<<
      version1:bits,
      build_minimal_input():bits,
      vout_count:bits,
      output_bytes:bits,
    >>)

  assert btc_tx.parse_error_kind(parse_err)
    == btc_tx.IntegerOutOfRange("-9223372036854775808")

  assert btc_tx.parse_error_ctx(parse_err)
    == [InTransaction, InOutputs, AtOutput(0), AtField("value")]
}

pub fn decode_accepts_outputs_total_value_exactly_at_max_money_test() {
  // Create a transaction with outputs totaling exactly max_satoshis (should succeed)
  // max_satoshis = 2_100_000_000_000_000
  // output1 = 1_050_000_000_000_000
  // output2 = 1_050_000_000_000_000
  // total = 2_100_000_000_000_000 (exactly at limit)

  let vout_count = compact_size(2)
  let value1 = 1_050_000_000_000_000
  let value2 = 1_050_000_000_000_000
  let script_pubkey = <<>>

  let output1 = build_output(<<value1:little-size(64)>>, script_pubkey)
  let output2 = build_output(<<value2:little-size(64)>>, script_pubkey)
  let lock_time = <<0:little-size(32)>>

  let assert Ok(_) =
    btc_tx.decode(<<
      version1:bits,
      build_minimal_input():bits,
      vout_count:bits,
      output1:bits,
      output2:bits,
      lock_time:bits,
    >>)
}

// ============================================================================
// ScriptPubKey Validation
// ============================================================================

pub fn decode_rejects_scriptpubkey_exceeding_max_size_test() {
  // Build a transaction with scriptPubKey_len = 10,001 (exceeds MAX_SCRIPT_SIZE of 10,000)

  let vout_count = compact_size(1)

  let value = <<0:little-size(64)>>
  let script_pubkey = <<0:size({ 10_001 * 8 })>>

  let output_bytes = build_output(value, script_pubkey)

  let assert Error(ParseFailed(parse_err)) =
    btc_tx.decode(<<
      version1:bits,
      build_minimal_input():bits,
      vout_count:bits,
      output_bytes:bits,
    >>)

  assert btc_tx.parse_error_offset(parse_err) == 55

  assert btc_tx.parse_error_kind(parse_err)
    == PolicyLimitExceeded(10_001, 10_000)

  assert btc_tx.parse_error_ctx(parse_err)
    == [InTransaction, InOutputs, AtOutput(0), AtField("scriptPubKey_len")]
}

pub fn decode_parses_scriptpubkey_at_max_size_test() {
  // Create a transaction with an output that has a scriptPubKey of exactly 10,000 bytes (MAX_SCRIPT_SIZE)
  let value_satoshis = 75_000_000
  let script_pubkey_bytes = <<0:size({ 10_000 * 8 })>>
  let output =
    build_output(<<value_satoshis:little-size(64)>>, script_pubkey_bytes)
  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    btc_tx.decode(<<
      version1:bits,
      build_minimal_input():bits,
      compact_size(1):bits,
      output:bits,
      lock_time:bits,
    >>)

  // Verify we parsed exactly one output
  let outputs = btc_tx.get_outputs(tx)
  let assert [first_output] = outputs

  // Verify output properties
  let actual_value =
    first_output
    |> btc_tx.get_output_value
    |> btc_tx.satoshis_to_int

  assert actual_value == value_satoshis

  let actual_script_pubkey_bytes =
    first_output
    |> btc_tx.get_output_script_pubkey
    |> btc_tx.get_raw_script_bytes

  assert bit_array.byte_size(actual_script_pubkey_bytes) == 10_000
}

pub fn validate_scriptpubkey_insufficient_bytes_error_test() {
  // Build a transaction where scriptPubKey_len claims 100 bytes but only 10 bytes remain
  let vout_count = compact_size(1)

  let value = <<0:little-size(64)>>
  let script_pubkey_len = compact_size(100)

  // Only provide 10 bytes of actual data (not enough for the claimed 100)
  let partial_script_pubkey = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>

  let output_bytes = <<
    value:bits,
    script_pubkey_len:bits,
    partial_script_pubkey:bits,
  >>

  let assert Error(ParseFailed(parse_err)) =
    btc_tx.decode(<<
      version1:bits,
      build_minimal_input():bits,
      vout_count:bits,
      output_bytes:bits,
    >>)

  assert btc_tx.parse_error_kind(parse_err)
    == InsufficientBytes(claimed: 100, remaining: 10)

  assert btc_tx.parse_error_ctx(parse_err)
    == [InTransaction, InOutputs, AtOutput(0), AtField("scriptPubKey_len")]
}

// ============================================================================
// Witness Data Parsing
// ============================================================================

pub fn decode_segwit_tx_parses_witness_data_test() {
  // Use the real SegWit transaction constant
  let assert Ok(tx) = btc_tx.decode_hex(segwit_v1_tx)

  // Verify it's identified as a SegWit transaction
  assert btc_tx.is_segwit(tx)

  // Verify basic transaction properties
  assert btc_tx.get_version(tx) == 1

  // Verify inputs were parsed correctly (should have 1 input)
  let inputs = btc_tx.get_inputs(tx)
  let assert [_input] = inputs

  // Verify outputs were parsed correctly (should have 2 outputs)
  let outputs = btc_tx.get_outputs(tx)
  let assert [_output1, _output2] = outputs

  // Verify witness data was parsed
  let assert Ok(witnesses) = btc_tx.get_witnesses(tx)
  let assert [witness_stack] = witnesses

  // Verify the witness stack has 2 items (likely signature and pubkey for P2WPKH)
  let witness_items = btc_tx.get_witness_items(witness_stack)
  let assert [item1, item2] = witness_items

  // Verify the items are non-empty (actual signature and pubkey data)
  assert bit_array.byte_size(btc_tx.get_witness_item_bytes(item1)) > 0
  assert bit_array.byte_size(btc_tx.get_witness_item_bytes(item2)) > 0
}

// empty witness stacks valid b/c segWit txs can contain legacy inputs
pub fn decode_segwit_tx_with_empty_witness_stacks_test() {
  // Build inputs
  let input1 = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let input2 = build_input(repeat_byte(1, 32), 1, <<0x01, 0x02>>, 0xFFFFFFFF)

  // Build output
  let output = build_output(<<1000:little-size(64)>>, <<0x76, 0xa9>>)

  // Empty witness stacks: each input gets a witness stack with 0 items
  let witness_stack1 = compact_size(0)
  let witness_stack2 = compact_size(0)

  let tx_bytes =
    build_segwit_tx([input1, input2], [output], [witness_stack1, witness_stack2])

  let assert Ok(tx) = btc_tx.decode(tx_bytes)

  // Verify it's identified as SegWit
  assert btc_tx.is_segwit(tx)

  // Verify witness data exists
  let assert Ok(witnesses) = btc_tx.get_witnesses(tx)
  let assert [stack1, stack2] = witnesses

  // Verify both stacks are empty
  let items1 = btc_tx.get_witness_items(stack1)
  let items2 = btc_tx.get_witness_items(stack2)

  assert items1 == []
  assert items2 == []
}

pub fn decode_witness_stack_with_multiple_items_test() {
  // Build input
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)

  // Build output
  let output = build_output(<<1000:little-size(64)>>, <<>>)

  // Build witness items with different sizes
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

  let tx_bytes = build_segwit_tx([input], [output], [witness_stack])

  let assert Ok(tx) = btc_tx.decode(tx_bytes)

  // Verify it's SegWit
  assert btc_tx.is_segwit(tx)

  // Get the witness stack
  let assert Ok(witnesses) = btc_tx.get_witnesses(tx)
  let assert [stack] = witnesses

  // Verify it has 3 items
  let items = btc_tx.get_witness_items(stack)
  let assert [item1, item2, item3] = items

  // Verify each item has the correct data
  let data1 = btc_tx.get_witness_item_bytes(item1)
  let data2 = btc_tx.get_witness_item_bytes(item2)
  let data3 = btc_tx.get_witness_item_bytes(item3)

  assert data1 == witness_item1_data
  assert data2 == witness_item2_data
  assert data3 == witness_item3_data
}

pub fn decode_witness_item_with_zero_length_test() {
  // Build input
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)

  // Build output
  let output = build_output(<<1000:little-size(64)>>, <<>>)

  // Build a witness stack with a single zero-length item
  let witness_stack = <<
    compact_size(1):bits,
    compact_size(0):bits,
  >>

  let tx_bytes = build_segwit_tx([input], [output], [witness_stack])

  let assert Ok(tx) = btc_tx.decode(tx_bytes)

  // Verify it's SegWit
  assert btc_tx.is_segwit(tx)

  // Get the witness stack
  let assert Ok(witnesses) = btc_tx.get_witnesses(tx)
  let assert [stack] = witnesses

  // Verify it has 1 item
  let items = btc_tx.get_witness_items(stack)
  let assert [item] = items

  // Verify the item is zero-length
  let data = btc_tx.get_witness_item_bytes(item)
  assert bit_array.byte_size(data) == 0
}

pub fn decode_witness_item_length_exceeds_remaining_bytes_test() {
  // Build input
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)

  // Build output
  let output = build_output(<<1000:little-size(64)>>, <<>>)

  // Build witness stack where item length exceeds remaining bytes
  // Claim 100 bytes for the item but only provide 10 bytes of data
  let witness_item_data = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>
  let witness_stack = <<
    compact_size(1):bits,
    compact_size(100):bits,
    witness_item_data:bits,
  >>

  let tx_bytes = build_segwit_tx([input], [output], [witness_stack])

  let assert Error(ParseFailed(parse_err)) = btc_tx.decode(tx_bytes)

  // The compact_size encoding of 100 takes 3 bytes (0xFD + 2 bytes),
  // so remaining = 10 data bytes + 4 bytes overhead = 14
  assert btc_tx.parse_error_kind(parse_err)
    == InsufficientBytes(claimed: 100, remaining: 14)

  // Verify the error context indicates we're in witness item length parsing
  assert btc_tx.parse_error_ctx(parse_err)
    == [
      InTransaction,
      AtWitnessStack(0),
      AtWitnessItem(0),
      AtField("witnessItem_len"),
    ]
}

pub fn decode_witness_invalid_compact_size_in_stack_length_test() {
  // Build input and output normally
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output(<<1000:little-size(64)>>, <<>>)

  // Manually construct transaction with invalid CompactSize in witness stack length
  // CompactSize 0xFD requires 2 bytes following, but provide only 1 (truncated)
  let marker = <<0x00>>
  let flag = <<0x01>>
  let vin_count = compact_size(1)
  let vout_count = compact_size(1)
  let lock_time = <<0:little-size(32)>>

  // Invalid witness stack: 0xFD followed by only 1 byte (truncated CompactSize)
  let invalid_witness_stack = <<0xFD, 0x01>>

  let tx_bytes = <<
    version1:bits,
    marker:bits,
    flag:bits,
    vin_count:bits,
    input:bits,
    vout_count:bits,
    output:bits,
    invalid_witness_stack:bits,
    lock_time:bits,
  >>

  let assert Error(ParseFailed(parse_err)) = btc_tx.decode(tx_bytes)

  assert btc_tx.parse_error_kind(parse_err)
    == CompactSizeError(compact_size.NonMinimalCompactSize(3, 1))

  // Verify the error context indicates we're in witness stack count parsing
  assert btc_tx.parse_error_ctx(parse_err)
    == [InTransaction, AtWitnessStack(0), AtField("witnessStack_len")]
}

pub fn decode_witness_invalid_compact_size_in_item_length_test() {
  // Build input and output normally
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output(<<1000:little-size(64)>>, <<>>)

  // Manually construct transaction with invalid CompactSize in witness item length
  let marker = <<0x00>>
  let flag = <<0x01>>
  let vin_count = compact_size(1)
  let vout_count = compact_size(1)
  let lock_time = <<0:little-size(32)>>

  // Valid witness stack count (1 item), but invalid item length CompactSize
  // 0xFD requires 2 bytes following, but provide only 1 (truncated)
  let invalid_witness_stack = <<
    compact_size(1):bits,
    0xFD,
    0x01,
  >>

  let tx_bytes = <<
    version1:bits,
    marker:bits,
    flag:bits,
    vin_count:bits,
    input:bits,
    vout_count:bits,
    output:bits,
    invalid_witness_stack:bits,
    lock_time:bits,
  >>

  let assert Error(ParseFailed(parse_err)) = btc_tx.decode(tx_bytes)

  assert btc_tx.parse_error_kind(parse_err)
    == CompactSizeError(compact_size.NonMinimalCompactSize(3, 1))

  // Verify the error context indicates we're in witness item length parsing
  assert btc_tx.parse_error_ctx(parse_err)
    == [
      InTransaction,
      AtWitnessStack(0),
      AtWitnessItem(0),
      AtField("witnessItem_len"),
    ]
}

// ============================================================================
// Witness Item Size (max_item_size) Policy Enforcement
// ============================================================================

pub fn decode_witness_item_at_max_size_succeeds_test() {
  let max_witness_item_size = 50

  // Build input and output
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output(<<1000:little-size(64)>>, <<>>)

  // Build witness stack with item exactly at max_item_size (100 bytes by default)
  let witness_item_data = repeat_byte(0xAB, max_witness_item_size)
  let witness_stack = <<
    compact_size(1):bits,
    compact_size(max_witness_item_size):bits,
    witness_item_data:bits,
  >>

  let tx_bytes = build_segwit_tx([input], [output], [witness_stack])

  let policy =
    DecodePolicy(
      ..btc_tx.default_policy,
      witness_policy: WitnessPolicy(
        ..btc_tx.default_witness_policy,
        max_item_size: max_witness_item_size,
      ),
    )

  let assert Ok(tx) = btc_tx.decode_with_policy(tx_bytes, policy)

  // Verify the witness item has the correct size
  let assert Ok(witnesses) = btc_tx.get_witnesses(tx)
  let assert [stack] = witnesses

  let items = btc_tx.get_witness_items(stack)
  let assert [item] = items

  let data = btc_tx.get_witness_item_bytes(item)
  assert bit_array.byte_size(data) == max_witness_item_size
}

pub fn decode_witness_item_exceeds_custom_max_size_fails_test() {
  let max_witness_item_size = 50

  // Build input and output
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output(<<1000:little-size(64)>>, <<>>)

  // Build witness stack with item exceeding custom max_item_size
  let witness_item_data = repeat_byte(0x42, max_witness_item_size + 1)

  let witness_stack = <<
    compact_size(1):bits,
    compact_size(max_witness_item_size + 1):bits,
    witness_item_data:bits,
  >>

  let tx_bytes = build_segwit_tx([input], [output], [witness_stack])

  let policy =
    DecodePolicy(
      ..btc_tx.default_policy,
      witness_policy: WitnessPolicy(
        ..btc_tx.default_witness_policy,
        max_item_size: max_witness_item_size,
      ),
    )

  let assert Error(ParseFailed(parse_err)) =
    btc_tx.decode_with_policy(tx_bytes, policy)

  assert btc_tx.parse_error_offset(parse_err) == 59

  // Verify the error kind indicates length exceeded max_item_size
  assert btc_tx.parse_error_kind(parse_err)
    == PolicyLimitExceeded(
      max_witness_item_size + 1,
      policy.witness_policy.max_item_size,
    )

  // Verify the error context indicates witness item length validation
  assert btc_tx.parse_error_ctx(parse_err)
    == [
      InTransaction,
      AtWitnessStack(0),
      AtWitnessItem(0),
      AtField("witnessItem_len"),
    ]
}

// ============================================================================
// Witness Items Per Input (max_items_per_input) Policy Enforcement
// ============================================================================

pub fn decode_witness_stack_at_max_items_per_input_succeeds_test() {
  let max_items_per_input = 3

  // Build input and output
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output(<<1000:little-size(64)>>, <<>>)

  // Build witness stack with exactly max_items_per_input items
  let witness_items =
    list.range(0, max_items_per_input - 1)
    |> list.map(fn(_) { <<compact_size(5):bits, 1, 2, 3, 4, 5>> })
    |> list.fold(<<>>, fn(acc, item) { <<acc:bits, item:bits>> })

  let witness_stack = <<
    compact_size(max_items_per_input):bits,
    witness_items:bits,
  >>

  let tx_bytes = build_segwit_tx([input], [output], [witness_stack])

  let policy =
    DecodePolicy(
      ..btc_tx.default_policy,
      witness_policy: WitnessPolicy(
        ..btc_tx.default_witness_policy,
        max_items_per_input: max_items_per_input,
      ),
    )

  let assert Ok(tx) = btc_tx.decode_with_policy(tx_bytes, policy)

  // Verify the witness stack has the correct number of items
  let assert Ok(witnesses) = btc_tx.get_witnesses(tx)
  let assert [stack] = witnesses

  let items = btc_tx.get_witness_items(stack)
  assert list.length(items) == max_items_per_input
}

pub fn decode_witness_stack_exceeds_max_items_per_input_fails_test() {
  let max_items_per_input = 2

  // Build input and output
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output(<<1000:little-size(64)>>, <<>>)

  // Build witness stack with max_items_per_input + 1 items
  let witness_items =
    list.range(0, max_items_per_input)
    |> list.map(fn(_) { <<compact_size(5):bits, 1, 2, 3, 4, 5>> })
    |> list.fold(<<>>, fn(acc, item) { <<acc:bits, item:bits>> })

  let witness_stack = <<
    compact_size(max_items_per_input + 1):bits,
    witness_items:bits,
  >>

  let tx_bytes = build_segwit_tx([input], [output], [witness_stack])

  let policy =
    DecodePolicy(
      ..btc_tx.default_policy,
      witness_policy: WitnessPolicy(
        ..btc_tx.default_witness_policy,
        max_items_per_input: max_items_per_input,
      ),
    )

  let assert Error(ParseFailed(parse_err)) =
    btc_tx.decode_with_policy(tx_bytes, policy)

  assert btc_tx.parse_error_offset(parse_err) == 58

  // Verify the error kind indicates length exceeded max_items_per_input
  assert btc_tx.parse_error_kind(parse_err)
    == PolicyLimitExceeded(
      max_items_per_input + 1,
      policy.witness_policy.max_items_per_input,
    )

  // Verify the error context indicates witness stack length validation
  assert btc_tx.parse_error_ctx(parse_err)
    == [InTransaction, AtWitnessStack(0), AtField("witnessStack_len")]
}

// ============================================================================
// Witness Stack Payload Bytes (max_stack_payload_bytes_per_input) Policy Enforcement
// ============================================================================

pub fn decode_witness_stack_at_max_payload_bytes_succeeds_test() {
  let max_payload_bytes = 50

  // Build input and output
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output(<<1000:little-size(64)>>, <<>>)

  // Build witness stack with items totaling exactly max_payload_bytes
  // 3 items: 20 bytes + 15 bytes + 15 bytes = 50 bytes total
  let witness_items = <<
    compact_size(20):bits,
    repeat_byte(0xAA, 20):bits,
    compact_size(15):bits,
    repeat_byte(0xBB, 15):bits,
    compact_size(15):bits,
    repeat_byte(0xCC, 15):bits,
  >>

  let witness_stack = <<compact_size(3):bits, witness_items:bits>>

  let tx_bytes = build_segwit_tx([input], [output], [witness_stack])

  let policy =
    DecodePolicy(
      ..btc_tx.default_policy,
      witness_policy: WitnessPolicy(
        ..btc_tx.default_witness_policy,
        max_stack_payload_bytes_per_input: max_payload_bytes,
      ),
    )

  let assert Ok(tx) = btc_tx.decode_with_policy(tx_bytes, policy)

  // Verify the witness stack was parsed correctly
  let assert Ok(witnesses) = btc_tx.get_witnesses(tx)
  let assert [stack] = witnesses

  let items = btc_tx.get_witness_items(stack)
  assert list.length(items) == 3

  // Verify total bytes
  let total_bytes =
    items
    |> list.map(fn(item) {
      item
      |> btc_tx.get_witness_item_bytes
      |> bit_array.byte_size
    })
    |> list.fold(0, fn(acc, size) { acc + size })

  assert total_bytes == max_payload_bytes
}

pub fn decode_witness_stack_exceeds_max_payload_bytes_fails_test() {
  let max_payload_bytes = 50

  // Build input and output
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output(<<1000:little-size(64)>>, <<>>)

  // Build witness stack with items totaling more than max_payload_bytes
  // 3 items: 20 bytes + 15 bytes + 16 bytes = 51 bytes total (exceeds 50)
  let witness_items = <<
    compact_size(20):bits,
    repeat_byte(0xAA, 20):bits,
    compact_size(15):bits,
    repeat_byte(0xBB, 15):bits,
    compact_size(16):bits,
    repeat_byte(0xCC, 16):bits,
  >>

  let witness_stack = <<compact_size(3):bits, witness_items:bits>>

  let tx_bytes = build_segwit_tx([input], [output], [witness_stack])

  let policy =
    DecodePolicy(
      ..btc_tx.default_policy,
      witness_policy: WitnessPolicy(
        ..btc_tx.default_witness_policy,
        max_stack_payload_bytes_per_input: max_payload_bytes,
      ),
    )

  let assert Error(ParseFailed(parse_err)) =
    btc_tx.decode_with_policy(tx_bytes, policy)

  // Verify the error kind indicates policy limit was exceeded
  assert btc_tx.parse_error_kind(parse_err)
    == PolicyLimitExceeded(51, max_payload_bytes)

  // Verify the error context indicates witness stack validation
  assert btc_tx.parse_error_ctx(parse_err)
    == [
      InTransaction,
      AtWitnessStack(0),
      AtWitnessItem(2),
      AtField("witnessStack_total_payload_bytes"),
    ]
}

pub fn decode_witness_stack_error_offset_points_to_third_item_test() {
  // Verify that when witnessStack_total_payload_bytes limit is exceeded at the
  // third witness item, the error offset points to the start of the third item's
  // length field

  let max_payload_bytes = 50

  // Build input and output
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output(<<1000:little-size(64)>>, <<>>)

  // Build witness stack with items totaling more than max_payload_bytes
  // 3 items: 20 bytes + 15 bytes + 16 bytes = 51 bytes total (exceeds 50)
  let witness_items = <<
    compact_size(20):bits,
    repeat_byte(0xAA, 20):bits,
    compact_size(15):bits,
    repeat_byte(0xBB, 15):bits,
    compact_size(16):bits,
    repeat_byte(0xCC, 16):bits,
  >>

  let witness_stack = <<compact_size(3):bits, witness_items:bits>>

  let tx_bytes = build_segwit_tx([input], [output], [witness_stack])

  let policy =
    DecodePolicy(
      ..btc_tx.default_policy,
      witness_policy: WitnessPolicy(
        ..btc_tx.default_witness_policy,
        max_stack_payload_bytes_per_input: max_payload_bytes,
      ),
    )

  let assert Error(ParseFailed(parse_err)) =
    btc_tx.decode_with_policy(tx_bytes, policy)

  // Calculate expected offset to start of third witness item's length field:
  // version (4) + marker (1) + flag (1) + vin_count (1) + input (41) +
  // vout_count (1) + output (9) + witness_stack_len (1) +
  // item1_len (1) + item1_bytes (20) + item2_len (1) + item2_bytes (15)
  let expected_offset = 4 + 1 + 1 + 1 + 41 + 1 + 9 + 1 + 1 + 20 + 1 + 15

  assert btc_tx.parse_error_offset(parse_err) == expected_offset
}

// ============================================================================
// Trailing Bytes Detection
// ============================================================================

pub fn decode_rejects_legacy_tx_with_trailing_byte_test() {
  let lock_time = <<0:little-size(32)>>

  // Build a valid legacy transaction
  let valid_tx = <<
    version1:bits,
    build_minimal_input():bits,
    build_minimal_output():bits,
    lock_time:bits,
  >>

  let assert Error(ParseFailed(parse_err)) =
    btc_tx.decode(<<valid_tx:bits, 0x42:size(8)>>)

  assert btc_tx.parse_error_kind(parse_err) == TrailingBytes(1)
  assert btc_tx.parse_error_ctx(parse_err) == [InTransaction]

  let expected_offset = bit_array.byte_size(valid_tx)
  assert btc_tx.parse_error_offset(parse_err) == expected_offset
}

pub fn decode_rejects_segwit_tx_with_trailing_byte_test() {
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output(<<0:little-size(64)>>, <<>>)
  let witness_stack = compact_size(0)

  let valid_tx = build_segwit_tx([input], [output], [witness_stack])

  let assert Error(ParseFailed(parse_err)) =
    btc_tx.decode(<<valid_tx:bits, 0xFF:size(8)>>)

  assert btc_tx.parse_error_kind(parse_err) == TrailingBytes(1)
  assert btc_tx.parse_error_ctx(parse_err) == [InTransaction]

  let expected_offset = bit_array.byte_size(valid_tx)
  assert btc_tx.parse_error_offset(parse_err) == expected_offset
}

// ============================================================================
// Consensus Validation
// ============================================================================

pub fn validate_consensus_accepts_valid_legacy_tx_test() {
  // Use a real legacy transaction that has 1 input and 1 output
  let assert Ok(unvalidated_tx) = btc_tx.decode_hex(legacy_v1_tx)

  assert !btc_tx.is_segwit(unvalidated_tx)

  let assert Ok(validated_tx) = btc_tx.validate_consensus(unvalidated_tx)

  // Verify the validated transaction maintains the same properties
  assert !btc_tx.is_segwit(validated_tx)
  assert btc_tx.get_version(validated_tx) == 1
  assert list.length(btc_tx.get_inputs(validated_tx)) == 1
  assert list.length(btc_tx.get_outputs(validated_tx)) == 1
  assert btc_tx.get_lock_time(validated_tx) == 0
}

pub fn validate_consensus_accepts_valid_segwit_tx_test() {
  // Use a real SegWit transaction that has 1 input, 2 outputs, and witness data
  let assert Ok(unvalidated_tx) = btc_tx.decode_hex(segwit_v1_tx)

  assert btc_tx.is_segwit(unvalidated_tx)

  let assert Ok(validated_tx) = btc_tx.validate_consensus(unvalidated_tx)

  // Verify the validated transaction maintains the same properties
  assert btc_tx.is_segwit(validated_tx)
  assert btc_tx.get_version(validated_tx) == 1
  assert list.length(btc_tx.get_inputs(validated_tx)) == 1
  assert list.length(btc_tx.get_outputs(validated_tx)) == 2
  assert btc_tx.get_lock_time(validated_tx) == 1170

  // Verify witness data is preserved
  let assert Ok(witnesses) = btc_tx.get_witnesses(validated_tx)
  assert list.length(witnesses) == 1
}

pub fn validate_consensus_rejects_tx_with_no_inputs_test() {
  // Build a SegWit transaction with 0 inputs (SegWit format required when vin_count=0)
  let marker = <<0x00>>
  let flag = <<0x01>>
  let vin_count = compact_size(0)
  let vout_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_len = compact_size(0)
  let witness_data = <<>>
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    marker:bits,
    flag:bits,
    vin_count:bits,
    vout_count:bits,
    value:bits,
    script_pubkey_len:bits,
    witness_data:bits,
    lock_time:bits,
  >>

  let assert Ok(unvalidated_tx) = btc_tx.decode(tx_bytes)

  assert btc_tx.validate_consensus(unvalidated_tx) == Error([NoInputs])
}

pub fn validate_consensus_rejects_tx_with_no_outputs_test() {
  // Build a legacy transaction with 1 input and 0 outputs
  let vin_count = compact_size(1)
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let vout_count = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    vin_count:bits,
    input:bits,
    vout_count:bits,
    lock_time:bits,
  >>

  let assert Ok(unvalidated_tx) = btc_tx.decode(tx_bytes)

  assert btc_tx.validate_consensus(unvalidated_tx) == Error([NoOutputs])
}

pub fn validate_consensus_rejects_tx_with_negative_output_value_test() {
  let vin_count = compact_size(1)
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let vout_count = compact_size(1)
  // -1 as signed int64
  let negative_value = <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>
  let script_pubkey_len = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    vin_count:bits,
    input:bits,
    vout_count:bits,
    negative_value:bits,
    script_pubkey_len:bits,
    lock_time:bits,
  >>

  let assert Ok(unvalidated_tx) = btc_tx.decode(tx_bytes)

  assert btc_tx.validate_consensus(unvalidated_tx)
    == Error([NegativeOutputValue])
}

pub fn validate_consensus_rejects_tx_with_output_exceeding_supply_test() {
  // Build a transaction with single output > max_satoshis (2_100_000_000_000_000)
  // Use 2_100_000_000_000_001 which exceeds the max supply
  let vin_count = compact_size(1)
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let vout_count = compact_size(1)
  let excessive_value = <<2_100_000_000_000_001:little-size(64)>>
  let script_pubkey_len = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    vin_count:bits,
    input:bits,
    vout_count:bits,
    excessive_value:bits,
    script_pubkey_len:bits,
    lock_time:bits,
  >>

  let assert Ok(unvalidated_tx) = btc_tx.decode(tx_bytes)

  assert btc_tx.validate_consensus(unvalidated_tx)
    == Error([OutputValueExceedsSupply])
}

pub fn validate_consensus_rejects_tx_with_total_outputs_exceeding_supply_test() {
  // Build a transaction with two outputs that individually are valid but total exceeds max_satoshis
  // Each output: 1_100_000_000_000_000, Total: 2_200_000_000_000_000 > 2_100_000_000_000_000
  let vin_count = compact_size(1)
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let vout_count = compact_size(2)
  let value1 = <<1_100_000_000_000_000:little-size(64)>>
  let value2 = <<1_100_000_000_000_000:little-size(64)>>
  let script_pubkey_len = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    vin_count:bits,
    input:bits,
    vout_count:bits,
    value1:bits,
    script_pubkey_len:bits,
    value2:bits,
    script_pubkey_len:bits,
    lock_time:bits,
  >>

  let assert Ok(unvalidated_tx) = btc_tx.decode(tx_bytes)

  assert btc_tx.validate_consensus(unvalidated_tx)
    == Error([TotalOutputValueExceedsSupply])
}

pub fn validate_consensus_rejects_coinbase_with_multiple_inputs_test() {
  // Build a transaction with 1 coinbase input and 1 regular input
  // Coinbase transactions must have exactly 1 input, so this should fail
  let vin_count = compact_size(2)

  // Coinbase input (prev_txid=all zeros, vout=0xFFFFFFFF)
  let coinbase_input = build_input(<<0:size(256)>>, 0xFFFFFFFF, <<0, 0>>, 0)

  // Regular input (non-zero prev_txid)
  let regular_input = build_input(<<1:size(256)>>, 0, <<>>, 0)

  let vout_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_len = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    vin_count:bits,
    coinbase_input:bits,
    regular_input:bits,
    vout_count:bits,
    value:bits,
    script_pubkey_len:bits,
    lock_time:bits,
  >>

  let assert Ok(unvalidated_tx) = btc_tx.decode(tx_bytes)

  assert btc_tx.validate_consensus(unvalidated_tx)
    == Error([CoinbaseWithMultipleInputs])
}

pub fn validate_consensus_rejects_tx_with_multiple_coinbase_inputs_test() {
  // Build a transaction with 2 coinbase inputs
  // This violates the rule that a transaction can only have one coinbase input
  let vin_count = compact_size(2)
  let coinbase_input = build_input(<<0:size(256)>>, 0xFFFFFFFF, <<0, 0>>, 0)
  let vout_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_len = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    vin_count:bits,
    coinbase_input:bits,
    coinbase_input:bits,
    vout_count:bits,
    value:bits,
    script_pubkey_len:bits,
    lock_time:bits,
  >>

  let assert Ok(unvalidated_tx) = btc_tx.decode(tx_bytes)

  assert btc_tx.validate_consensus(unvalidated_tx)
    == Error([MultipleCoinbaseInputs])
}

pub fn validate_consensus_rejects_coinbase_with_scriptsig_too_short_test() {
  // Build a coinbase transaction with scriptSig of 1 byte (minimum is 2 bytes)
  let vin_count = compact_size(1)
  // Coinbase input with 1-byte scriptSig (too short)
  let coinbase_input = build_input(<<0:size(256)>>, 0xFFFFFFFF, <<0x01>>, 0)
  let vout_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_len = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    vin_count:bits,
    coinbase_input:bits,
    vout_count:bits,
    value:bits,
    script_pubkey_len:bits,
    lock_time:bits,
  >>

  let assert Ok(unvalidated_tx) = btc_tx.decode(tx_bytes)

  assert btc_tx.validate_consensus(unvalidated_tx)
    == Error([InvalidCoinbaseScriptSigLength])
}

pub fn validate_consensus_rejects_coinbase_with_scriptsig_too_long_test() {
  let vin_count = compact_size(1)

  // Coinbase input with 101-byte (808-bit) scriptSig
  let coinbase_input =
    build_input(<<0:size(256)>>, 0xFFFFFFFF, <<0:size(808)>>, 0)

  let vout_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_len = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    vin_count:bits,
    coinbase_input:bits,
    vout_count:bits,
    value:bits,
    script_pubkey_len:bits,
    lock_time:bits,
  >>

  let assert Ok(unvalidated_tx) = btc_tx.decode(tx_bytes)

  assert btc_tx.validate_consensus(unvalidated_tx)
    == Error([InvalidCoinbaseScriptSigLength])
}

pub fn validate_consensus_accepts_coinbase_with_scriptsig_min_length_test() {
  let vin_count = compact_size(1)

  // Coinbase input with 2-byte scriptSig
  let coinbase_input =
    build_input(<<0:size(256)>>, 0xFFFFFFFF, <<0:size(16)>>, 0)

  let vout_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_len = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    vin_count:bits,
    coinbase_input:bits,
    vout_count:bits,
    value:bits,
    script_pubkey_len:bits,
    lock_time:bits,
  >>

  let assert Ok(unvalidated_tx) = btc_tx.decode(tx_bytes)
  let assert Ok(_) = btc_tx.validate_consensus(unvalidated_tx)
}

pub fn validate_consensus_accepts_coinbase_with_scriptsig_max_length_test() {
  let vin_count = compact_size(1)

  // Coinbase input with 100-byte scriptSig
  let coinbase_input =
    build_input(<<0:size(256)>>, 0xFFFFFFFF, <<0:size(800)>>, 0)

  let vout_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_len = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    vin_count:bits,
    coinbase_input:bits,
    vout_count:bits,
    value:bits,
    script_pubkey_len:bits,
    lock_time:bits,
  >>

  let assert Ok(unvalidated_tx) = btc_tx.decode(tx_bytes)
  let assert Ok(_) = btc_tx.validate_consensus(unvalidated_tx)
}

pub fn validate_consensus_returns_multiple_errors_test() {
  // Build a transaction that violates multiple consensus rules:
  // 1. Two coinbase inputs (should trigger MultipleCoinbaseInputs)
  // 2. Negative output value (should trigger NegativeOutputValue)
  let vin_count = compact_size(2)

  // Two coinbase inputs
  let coinbase_input1 = build_input(<<0:size(256)>>, 0xFFFFFFFF, <<0, 0>>, 0)
  let coinbase_input2 = build_input(<<0:size(256)>>, 0xFFFFFFFF, <<0, 0>>, 0)

  let vout_count = compact_size(1)
  // Negative value: 0xFFFFFFFFFFFFFFFF = -1 as signed int64
  let negative_value = <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>
  let script_pubkey_len = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    vin_count:bits,
    coinbase_input1:bits,
    coinbase_input2:bits,
    vout_count:bits,
    negative_value:bits,
    script_pubkey_len:bits,
    lock_time:bits,
  >>

  let assert Ok(unvalidated_tx) = btc_tx.decode(tx_bytes)

  // Validate consensus rules - should fail with multiple errors
  let assert Error(errors) = btc_tx.validate_consensus(unvalidated_tx)

  // Should contain both MultipleCoinbaseInputs and NegativeOutputValue
  assert list.contains(errors, MultipleCoinbaseInputs)
  assert list.contains(errors, NegativeOutputValue)
  assert list.length(errors) == 2
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Build an input with specific values
fn build_input(
  prev_txid: BitArray,
  vout: Int,
  script_sig: BitArray,
  sequence: Int,
) -> BitArray {
  let vout_bytes = <<vout:little-size(32)>>
  let script_len = compact_size(bit_array.byte_size(script_sig))
  let seq_bytes = <<sequence:little-size(32)>>

  <<
    prev_txid:bits,
    vout_bytes:bits,
    script_len:bits,
    script_sig:bits,
    seq_bytes:bits,
  >>
}

/// Build a minimal valid input (for use in output tests)
fn build_minimal_input() -> BitArray {
  let vin_count = compact_size(1)
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  <<vin_count:bits, input:bits>>
}

/// Build an output with specific values
fn build_output(value: BitArray, script_pubkey: BitArray) -> BitArray {
  let script_len =
    script_pubkey
    |> bit_array.byte_size
    |> compact_size

  <<
    value:bits,
    script_len:bits,
    script_pubkey:bits,
  >>
}

/// Build a minimal valid output section with vout_count, value, and empty scriptPubKey
fn build_minimal_output() -> BitArray {
  let vout_count = compact_size(1)
  let value = <<0:little-size(64)>>
  let script_pubkey_len = compact_size(0)

  <<
    vout_count:bits,
    value:bits,
    script_pubkey_len:bits,
  >>
}

/// Build a complete SegWit transaction from inputs, outputs, and witness stacks.
///
/// Constructs a valid SegWit transaction with the given components, handling
/// the marker/flag bytes and proper byte concatenation.
fn build_segwit_tx(
  inputs: List(BitArray),
  outputs: List(BitArray),
  witness_stacks: List(BitArray),
) -> BitArray {
  let marker = <<0x00>>
  let flag = <<0x01>>
  let vin_count = compact_size(list.length(inputs))
  let vout_count = compact_size(list.length(outputs))
  let lock_time = <<0:little-size(32)>>

  <<
    version1:bits,
    marker:bits,
    flag:bits,
    vin_count:bits,
    bit_array.concat(inputs):bits,
    vout_count:bits,
    bit_array.concat(outputs):bits,
    bit_array.concat(witness_stacks):bits,
    lock_time:bits,
  >>
}

/// Produce a BitArray consisting of `n` repetitions of byte `b`.
fn repeat_byte(b: Int, n: Int) -> BitArray {
  case n {
    0 -> <<>>
    _ -> <<b:little-size(8), repeat_byte(b, n - 1):bits>>
  }
}

/// Encode an integer as a CompactSize byte array.
///
/// This helper matches the Bitcoin CompactSize encoding rules:
/// - 0-252: single byte
/// - 253-65535: 0xFD followed by 2 bytes (little-endian)
/// - 65536-4294967295: 0xFE followed by 4 bytes (little-endian)
/// - 4294967296+: 0xFF followed by 8 bytes (little-endian)
fn compact_size(n: Int) -> BitArray {
  case n {
    _ if n < 0 -> panic as "compact_size: negative values not supported"
    _ if n <= 252 -> <<n:size(8)>>
    _ if n <= 65_535 -> <<0xFD, n:little-size(16)>>
    _ if n <= 4_294_967_295 -> <<0xFE, n:little-size(32)>>
    _ -> <<0xFF, n:little-size(64)>>
  }
}
