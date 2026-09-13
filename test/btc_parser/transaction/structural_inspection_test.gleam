import btc_parser/transaction.{
  type Input, type OutPoint, type OutputScript, type OutputScriptType,
  type ScriptBytes, BareMultisig, NonStandard, NullData, OtherWitnessProgram,
  P2A, P2PK, P2PKH, P2SH, P2TR, P2WPKH, P2WSH,
}
import gleam/bit_array
import gleam/list
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

pub fn classify_output_script_p2a_test() {
  let script_bytes = <<0x51, 0x02, 0x4E, 0x73>>
  check_output_script_classification(script_bytes, P2A)
}

pub fn classify_output_script_truncated_p2a_is_non_standard_test() {
  let script_bytes = <<0x51, 0x02, 0x4E>>
  check_output_script_classification(script_bytes, NonStandard)
}

pub fn classify_output_script_length_mismatched_p2a_is_non_standard_test() {
  let script_bytes = <<0x51, 0x03, 0x4E, 0x73>>
  check_output_script_classification(script_bytes, NonStandard)
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
  // OP_RETURN OP_ADD — non-push opcode after OP_RETURN is not NullData.
  let script_bytes = <<0x6A, 0x93>>
  check_output_script_classification(script_bytes, NonStandard)
}

pub fn classify_output_script_nulldata_truncated_pushdata_is_non_standard_test() {
  // OP_RETURN OP_PUSHDATA1 2 <one byte> — the push payload is truncated.
  let script_bytes = <<0x6A, 0x4C, 0x02, 0xAA>>
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

pub fn classify_output_script_bare_multisig_op_16_boundary_test() {
  let key = key_push(1, 33, 0xAA)
  let script_bytes = build_multisig_script(16, list.repeat(key, 16), 16)

  check_output_script_classification(script_bytes, BareMultisig)
}

pub fn classify_output_script_bare_multisig_minimally_pushed_counts_17_through_20_test() {
  let key = key_push(1, 33, 0xAA)

  let script_17 = build_multisig_script(17, list.repeat(key, 17), 17)
  let script_18 = build_multisig_script(18, list.repeat(key, 18), 18)
  let script_19 = build_multisig_script(19, list.repeat(key, 19), 19)
  let script_20 = build_multisig_script(20, list.repeat(key, 20), 20)

  check_output_script_classification(script_17, BareMultisig)
  check_output_script_classification(script_18, BareMultisig)
  check_output_script_classification(script_19, BareMultisig)
  check_output_script_classification(script_20, BareMultisig)
}

pub fn classify_output_script_bare_multisig_20_key_maximum_test() {
  let key = key_push(1, 65, 0xAA)
  let script_bytes = build_multisig_script(1, list.repeat(key, 20), 20)

  check_output_script_classification(script_bytes, BareMultisig)
}

pub fn classify_output_script_bare_multisig_accepts_all_key_push_encodings_test() {
  let keys = [
    key_push(1, 33, 0x00),
    key_push(2, 65, 0x11),
    key_push(3, 33, 0x22),
    key_push(4, 65, 0x33),
  ]
  let script_bytes = build_multisig_script(2, keys, 4)

  check_output_script_classification(script_bytes, BareMultisig)
}

pub fn classify_output_script_bare_multisig_does_not_validate_key_contents_test() {
  let keys = [
    key_push(1, 33, 0x00),
    key_push(1, 65, 0xFF),
  ]
  let script_bytes = build_multisig_script(1, keys, 2)

  check_output_script_classification(script_bytes, BareMultisig)
}

pub fn classify_output_script_other_witness_program_v1_non_taproot_test() {
  // OP_1 with a 20-byte program — valid witness v1 but not Taproot (which requires 32 bytes)
  let program = repeat_byte(0xFF, 20)
  let script_bytes = <<0x51, 0x14, program:bits>>
  check_output_script_classification(
    script_bytes,
    OtherWitnessProgram(version: 1),
  )
}

pub fn classify_output_script_other_witness_program_v2_test() {
  let program = repeat_byte(0xFF, 32)
  let script_bytes = <<0x52, 0x20, program:bits>>
  check_output_script_classification(
    script_bytes,
    OtherWitnessProgram(version: 2),
  )
}

pub fn classify_output_script_other_witness_program_v16_test() {
  let program = repeat_byte(0xFF, 20)
  let script_bytes = <<0x60, 0x14, program:bits>>
  check_output_script_classification(
    script_bytes,
    OtherWitnessProgram(version: 16),
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

pub fn classify_output_script_nulldata_ignores_legacy_relay_size_limit_test() {
  let data = repeat_byte(0xAB, 81)
  let script_bytes = <<0x6A, 0x4C, 81, data:bits>>

  check_output_script_classification(script_bytes, NullData)
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

pub fn classify_output_script_bare_multisig_4of4_ignores_relay_policy_test() {
  // A 4-of-4 script is structurally recognised even though Core's relay
  // policy separately limits bare multisig standardness to at most 3 keys.
  let pubkey1 = repeat_byte(0xAA, 33)
  let pubkey2 = repeat_byte(0xBB, 33)
  let pubkey3 = repeat_byte(0xCC, 33)
  let pubkey4 = repeat_byte(0xDD, 33)
  let script_bytes = <<
    0x51, 0x21, pubkey1:bits, 0x21, pubkey2:bits, 0x21, pubkey3:bits, 0x21,
    pubkey4:bits, 0x54, 0xAE,
  >>
  check_output_script_classification(script_bytes, BareMultisig)
}

pub fn classify_output_script_multisig_count_21_is_non_standard_test() {
  let key = key_push(1, 33, 0xAA)
  let script_with_n_21 =
    build_multisig_script_with_encodings(<<0x51>>, [key], <<0x01, 0x15>>, <<
      0xAE,
    >>)
  let script_with_m_21 =
    build_multisig_script_with_encodings(<<0x01, 0x15>>, [key], <<0x51>>, <<
      0xAE,
    >>)

  check_output_script_classification(script_with_n_21, NonStandard)
  check_output_script_classification(script_with_m_21, NonStandard)
}

pub fn classify_output_script_multisig_rejects_nonminimal_count_pushes_test() {
  let key = key_push(1, 33, 0xAA)
  let nonminimal_push = <<0x4C, 0x01, 0x11>>
  let nonminimal_small_number_push = <<0x01, 0x01>>

  let script_with_nonminimal_push =
    build_multisig_script_with_encodings(nonminimal_push, [key], <<0x51>>, <<
      0xAE,
    >>)
  let script_with_nonminimal_small_number =
    build_multisig_script_with_encodings(
      nonminimal_small_number_push,
      [key],
      <<0x51>>,
      <<0xAE>>,
    )

  check_output_script_classification(script_with_nonminimal_push, NonStandard)
  check_output_script_classification(
    script_with_nonminimal_small_number,
    NonStandard,
  )
}

pub fn classify_output_script_multisig_rejects_nonminimal_script_number_test() {
  let key = key_push(1, 33, 0xAA)
  // 17 encoded as the non-minimal two-byte script number 0x11 0x00.
  let nonminimal_script_number = <<0x02, 0x11, 0x00>>
  let script_bytes =
    build_multisig_script_with_encodings(
      nonminimal_script_number,
      [key],
      <<0x51>>,
      <<0xAE>>,
    )

  check_output_script_classification(script_bytes, NonStandard)
}

pub fn classify_output_script_multisig_incorrect_key_payload_size_is_non_standard_test() {
  let script_bytes = <<
    0x51,
    0x20,
    repeat_byte(0xAA, 32):bits,
    0x51,
    0xAE,
  >>

  check_output_script_classification(script_bytes, NonStandard)
}

pub fn classify_output_script_multisig_truncated_key_push_is_non_standard_test() {
  let script_bytes = <<0x51, 0x21, repeat_byte(0xAA, 32):bits>>

  check_output_script_classification(script_bytes, NonStandard)
}

pub fn classify_output_script_multisig_key_count_mismatch_is_non_standard_test() {
  let key = key_push(1, 33, 0xAA)
  let script_bytes = build_multisig_script(1, [key], 2)

  check_output_script_classification(script_bytes, NonStandard)
}

pub fn classify_output_script_multisig_trailing_opcode_is_non_standard_test() {
  let key = key_push(1, 33, 0xAA)
  let script_bytes =
    build_multisig_script_with_encodings(<<0x51>>, [key], <<0x51>>, <<
      0xAE,
      0x00,
    >>)

  check_output_script_classification(script_bytes, NonStandard)
}

pub fn classify_output_script_other_witness_program_v1_different_two_byte_program_test() {
  // The shortest valid version-1 program remains the generic fallback unless
  // its two bytes are the exact P2A `4E 73` program.
  let program = repeat_byte(0xFF, 2)
  let script_bytes = <<0x51, 0x02, program:bits>>
  check_output_script_classification(
    script_bytes,
    OtherWitnessProgram(version: 1),
  )
}

pub fn classify_output_script_other_witness_program_v1_max_program_test() {
  let program = repeat_byte(0xFF, 40)
  let script_bytes = <<0x51, 0x28, program:bits>>
  check_output_script_classification(
    script_bytes,
    OtherWitnessProgram(version: 1),
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

/// Build a minimally encoded bare multisig script ending in
/// `OP_CHECKMULTISIG`.
fn build_multisig_script(
  min_sigs: Int,
  key_pushes: List(BitArray),
  pubkey_count: Int,
) -> BitArray {
  build_multisig_script_with_encodings(
    encode_multisig_count(min_sigs),
    key_pushes,
    encode_multisig_count(pubkey_count),
    <<0xAE>>,
  )
}

/// Assemble a bare multisig script from pre-encoded count fields, key pushes,
/// and a caller-supplied suffix.
fn build_multisig_script_with_encodings(
  min_sigs: BitArray,
  key_pushes: List(BitArray),
  pubkey_count: BitArray,
  suffix: BitArray,
) -> BitArray {
  let key_bytes = bit_array.concat(key_pushes)
  <<
    min_sigs:bits,
    key_bytes:bits,
    pubkey_count:bits,
    suffix:bits,
  >>
}

/// Encode a multisig count using `OP_1`–`OP_16` or a minimal direct one-byte
/// script-number push for values 17–20.
fn encode_multisig_count(value: Int) -> BitArray {
  case value {
    value if 1 <= value && value <= 16 -> {
      let opcode = value + 0x50
      <<opcode:little-size(8)>>
    }
    value if 17 <= value && value <= 20 -> <<0x01, value:little-size(8)>>
    _ -> panic as "multisig count must be in the range 1 through 20"
  }
}

/// Build a key payload push using direct, `OP_PUSHDATA1`, `OP_PUSHDATA2`, or
/// `OP_PUSHDATA4` encoding, filled with a repeated byte.
fn key_push(encoding: Int, payload_size: Int, fill: Int) -> BitArray {
  let payload = repeat_byte(fill, payload_size)

  case encoding {
    1 -> <<payload_size:little-size(8), payload:bits>>
    2 -> <<0x4C, payload_size:little-size(8), payload:bits>>
    3 -> <<0x4D, payload_size:little-size(16), payload:bits>>
    4 -> <<0x4E, payload_size:little-size(32), payload:bits>>
    _ -> panic as "unknown multisig key push encoding"
  }
}
