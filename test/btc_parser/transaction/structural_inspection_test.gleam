import btc_parser/transaction.{
  type Input, type OutPoint, type OutputScript, type OutputScriptType,
  type ScriptBytes, BareMultisig, NonStandard, NullData, P2PK, P2PKH, P2SH, P2TR,
  P2WPKH, P2WSH, UnknownWitnessProgram,
}
import support/bitcoin_wire.{compact_size}
import support/transaction_wire.{
  build_input_bytes, build_minimal_input_section_bytes,
  build_minimal_output_section_bytes, build_output_bytes, repeat_byte,
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

// ============================================================================
// classify_output_script
// ============================================================================

pub fn classify_output_script_p2pkh_test() {
  let hash = repeat_byte(0xAA, 20)
  let script_bytes = <<0x76, 0xA9, 0x14, hash:bits, 0x88, 0xAC>>
  check_output_script_classification(script_bytes, P2PKH)
}

pub fn classify_output_script_p2sh_test() {
  let hash = repeat_byte(0xBB, 20)
  let script_bytes = <<0xA9, 0x14, hash:bits, 0x87>>
  check_output_script_classification(script_bytes, P2SH)
}

pub fn classify_output_script_p2wpkh_test() {
  let hash = repeat_byte(0xCC, 20)
  let script_bytes = <<0x00, 0x14, hash:bits>>
  check_output_script_classification(script_bytes, P2WPKH)
}

pub fn classify_output_script_p2wsh_test() {
  let hash = repeat_byte(0xDD, 32)
  let script_bytes = <<0x00, 0x20, hash:bits>>
  check_output_script_classification(script_bytes, P2WSH)
}

pub fn classify_output_script_p2tr_test() {
  let pubkey = repeat_byte(0xEE, 32)
  let script_bytes = <<0x51, 0x20, pubkey:bits>>
  check_output_script_classification(script_bytes, P2TR)
}

pub fn classify_output_script_p2pk_compressed_test() {
  let pubkey = repeat_byte(0x02, 33)
  let script_bytes = <<0x21, pubkey:bits, 0xAC>>
  check_output_script_classification(script_bytes, P2PK)
}

pub fn classify_output_script_p2pk_uncompressed_test() {
  let pubkey = repeat_byte(0x04, 65)
  let script_bytes = <<0x41, pubkey:bits, 0xAC>>
  check_output_script_classification(script_bytes, P2PK)
}

pub fn classify_output_script_nulldata_with_data_test() {
  let script_bytes = <<0x6A, 0x04, 0xDE, 0xAD, 0xBE, 0xEF>>
  check_output_script_classification(script_bytes, NullData)
}

pub fn classify_output_script_nulldata_empty_test() {
  let script_bytes = <<0x6A>>
  check_output_script_classification(script_bytes, NullData)
}

pub fn classify_output_script_nulldata_non_push_is_non_standard_test() {
  // OP_RETURN OP_ADD — non-push opcode after OP_RETURN is not a standard null-data script
  let script_bytes = <<0x6A, 0x93>>
  check_output_script_classification(script_bytes, NonStandard)
}

pub fn classify_output_script_bare_multisig_1of1_test() {
  let pubkey = repeat_byte(0xAA, 33)
  let script_bytes = <<0x51, 0x21, pubkey:bits, 0x51, 0xAE>>
  check_output_script_classification(script_bytes, BareMultisig)
}

pub fn classify_output_script_bare_multisig_2of3_test() {
  let pubkey1 = repeat_byte(0xAA, 33)
  let pubkey2 = repeat_byte(0xBB, 33)
  let pubkey3 = repeat_byte(0xCC, 33)
  let script_bytes = <<
    0x52, 0x21, pubkey1:bits, 0x21, pubkey2:bits, 0x21, pubkey3:bits, 0x53, 0xAE,
  >>
  check_output_script_classification(script_bytes, BareMultisig)
}

pub fn classify_output_script_bare_multisig_3of3_test() {
  let pubkey1 = repeat_byte(0xAA, 33)
  let pubkey2 = repeat_byte(0xBB, 33)
  let pubkey3 = repeat_byte(0xCC, 33)
  let script_bytes = <<
    0x53, 0x21, pubkey1:bits, 0x21, pubkey2:bits, 0x21, pubkey3:bits, 0x53, 0xAE,
  >>
  check_output_script_classification(script_bytes, BareMultisig)
}

pub fn classify_output_script_unknown_witness_v1_non_taproot_test() {
  // OP_1 with a 20-byte program — valid witness v1 but not Taproot (which requires 32 bytes)
  let program = repeat_byte(0xFF, 20)
  let script_bytes = <<0x51, 0x14, program:bits>>
  check_output_script_classification(
    script_bytes,
    UnknownWitnessProgram(version: 1),
  )
}

pub fn classify_output_script_unknown_witness_v2_test() {
  let program = repeat_byte(0xFF, 32)
  let script_bytes = <<0x52, 0x20, program:bits>>
  check_output_script_classification(
    script_bytes,
    UnknownWitnessProgram(version: 2),
  )
}

pub fn classify_output_script_unknown_witness_v16_test() {
  let program = repeat_byte(0xFF, 20)
  let script_bytes = <<0x60, 0x14, program:bits>>
  check_output_script_classification(
    script_bytes,
    UnknownWitnessProgram(version: 16),
  )
}

pub fn classify_output_script_non_standard_test() {
  let script_bytes = <<0x00, 0x01, 0xAA>>
  check_output_script_classification(script_bytes, NonStandard)
}

pub fn classify_output_script_empty_test() {
  let script_bytes = <<>>
  check_output_script_classification(script_bytes, NonStandard)
}

pub fn classify_output_script_nulldata_at_max_size_test() {
  // The 80-byte payload keeps the full script at the 83-byte policy limit.
  let data = repeat_byte(0xAB, 80)
  let script_bytes = <<0x6A, 0x4C, 80, data:bits>>

  check_output_script_classification(script_bytes, NullData)
}

pub fn classify_output_script_nulldata_over_max_size_test() {
  // One more payload byte pushes the full script over the 83-byte policy limit.
  let data = repeat_byte(0xAB, 81)
  let script_bytes = <<0x6A, 0x4C, 81, data:bits>>

  check_output_script_classification(script_bytes, NonStandard)
}

pub fn classify_output_script_multisig_invalid_m_gt_n_test() {
  // OP_3 <2 pubkeys> OP_2 OP_CHECKMULTISIG — m(3) > n(2), invalid
  let pubkey1 = repeat_byte(0xAA, 33)
  let pubkey2 = repeat_byte(0xBB, 33)
  let script_bytes = <<
    0x53, 0x21, pubkey1:bits, 0x21, pubkey2:bits, 0x52, 0xAE,
  >>
  check_output_script_classification(script_bytes, NonStandard)
}

pub fn classify_output_script_multisig_too_many_keys_test() {
  // OP_1 <4 pubkeys> OP_4 OP_CHECKMULTISIG — n(4) > 3, non-standard
  let pubkey1 = repeat_byte(0xAA, 33)
  let pubkey2 = repeat_byte(0xBB, 33)
  let pubkey3 = repeat_byte(0xCC, 33)
  let pubkey4 = repeat_byte(0xDD, 33)
  let script_bytes = <<
    0x51, 0x21, pubkey1:bits, 0x21, pubkey2:bits, 0x21, pubkey3:bits, 0x21,
    pubkey4:bits, 0x54, 0xAE,
  >>
  check_output_script_classification(script_bytes, NonStandard)
}

pub fn classify_output_script_unknown_witness_v1_min_program_test() {
  let program = repeat_byte(0xFF, 2)
  let script_bytes = <<0x51, 0x02, program:bits>>
  check_output_script_classification(
    script_bytes,
    UnknownWitnessProgram(version: 1),
  )
}

pub fn classify_output_script_unknown_witness_v1_max_program_test() {
  let program = repeat_byte(0xFF, 40)
  let script_bytes = <<0x51, 0x28, program:bits>>
  check_output_script_classification(
    script_bytes,
    UnknownWitnessProgram(version: 1),
  )
}

/// Build and deserialize a minimal transaction containing only the given
/// `script_pubkey_bytes`, returning a `ScriptBytes(OutputScript)` value
/// ready to pass to `classify_output_script`.
fn output_script_from_bytes(
  script_pubkey_bytes: BitArray,
) -> ScriptBytes(OutputScript) {
  let output = build_output_bytes(<<0:little-size(64)>>, script_pubkey_bytes)
  let lock_time = <<0:little-size(32)>>
  let assert Ok(tx) =
    transaction.deserialize(<<
      transaction_version_1_bytes:bits,
      build_minimal_input_section_bytes():bits,
      compact_size(1):bits,
      output:bits,
      lock_time:bits,
    >>)
  let assert [first_output] = transaction.get_outputs(tx)
  transaction.get_output_script_pubkey(first_output)
}

fn check_output_script_classification(
  script_bytes: BitArray,
  expected: OutputScriptType,
) -> Nil {
  assert script_bytes
    |> output_script_from_bytes
    |> transaction.classify_output_script
    == expected
}
