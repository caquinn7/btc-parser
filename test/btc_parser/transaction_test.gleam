import btc_parser/transaction.{
  AtField, AtInput, AtOutput, AtWitnessItem, AtWitnessStack, BareMultisig,
  CoinbaseWithMultipleInputs, DuplicateInput, InInputs, InOutputs, InTransaction,
  InputCount, InsufficientBytes, InvalidCoinbaseScriptSigLength, InvalidHex,
  InvalidSegwitMarkerFlag, NoInputs, NoOutputs, NonMinimalCompactSize,
  NonStandard, NullData, OutputCount, OutputValueOutOfRange, P2PK, P2PKH, P2SH,
  P2TR, P2WPKH, P2WSH, ParseFailed, PolicyLimitExceeded, ScriptPubKeyLength,
  ScriptSigLength, SegwitMarkerAndFlag, SuperfluousWitnessRecord,
  TotalOutputValueOutOfRange, TrailingBytes, UnexpectedEof,
  UnknownWitnessProgram, Version, WitnessItemCount, WitnessItemLength,
  WitnessStackPayloadSize,
}
import gleam/bit_array
import gleam/crypto.{Sha256}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import support/target

const legacy_v1_tx = "010000000173ea7c1caa2dc6669848997864cb9f597284760654a98f67f321ae78d89dcd380a0000006a4730440220185e66bef2903df84f7eb68c4eedb17bcf59f416324e1807e41461cad39aee8202200cbe809bfbac0f33ed5a23fc70473ff64462e225b9218b568bf5e13a11832445012103c3a5d7ca9937c6f862e3454d679171e90e7ff6d8147b0725cfae909a1c94a538feffffff2122020000000000001976a9145349473a38385c482b2f6a2b6d5476534b6f394f88ac22020000000000001976a91455677a584a742b5a544a5262516a627a50716b3888ac22020000000000001976a9146e7473336b746356685451555a5177326d55373788acdd3f0000000000001976a914b02562ff4e772f0875fbb4cccbc15ef08c431f3e88ac22020000000000001976a91448324f70644f667a36764e544665474a586d776688ac22020000000000001976a9144744756e56484142754a68586e513d4f424a5c3388ac22020000000000001976a91432362f7b2275726e223a2239346637313165353088ac22020000000000001976a914346238643131633162373835613162393663613088ac22020000000000001976a914383531333039376164663361316631303834313688ac22020000000000001976a9146535656134643733623437646166652f4120736d88ac22020000000000001976a914616c6c206d6573736167652e6a7067222c226e6d88ac22020000000000001976a91465223a2266756e6b20796f75222c22637265223a88ac22020000000000001976a9145b223139434b474c61426a64707045706148537488ac22020000000000001976a91438776e727a5371487838356850643955222c223188ac22020000000000001976a91444764e5039385a664857376d53397634426a375288ac22020000000000001976a9147436477457567844344c625a37222c223136726288ac22020000000000001976a9143979413746595150545570775a4a73575a56373788ac22020000000000001976a91466575555477366477077225d2c226f776e223a7b88ac22020000000000001976a914223139434b474c61426a6470704570614853743888ac22020000000000001976a914776e727a5371487838356850643955223a397d2c88ac22020000000000001976a91422726f79223a7b22314233444c725936344c4e6988ac22020000000000001976a91467775071755356414c64704b484563774a546a4688ac22020000000000001976a9144d59223a352e307d7d232323232323232323232388ac22020000000000001976a914393466373131653530346238643131633162373888ac22020000000000001976a914a968f1d8335db1404e32b6b360952e4bdd7ab20088ac22020000000000001976a91466756e6b2323232323232323232323232323232388ac22020000000000001976a914796f75232323232323232323232323232323232388ac22020000000000001976a9147032666b2323232323232323232323232323232388ac22020000000000001976a914656d62696923232323232323232323232323232388ac22020000000000001976a9146e1c6481b500237b14c7c474ae728e670d3b757588ac22020000000000001976a9144039859aabef04c076fd641744faedb3ee240f1588ac22020000000000001976a91459e4d4073fe0680c02fffb0cfe5ad923bf5c1f6588ac22020000000000001976a9148db967691586d193770e916d8cb9475d4118094988ac3a540e00"

const segwit_v1_tx = "01000000000102abbcae618dc866eff678eb59b617add6995a9b43e18f9156d3683a32554ea0790a00000000ffffffffbc3a57d8b85c9b691169c41d1184a60041eba5a8ac1bfcbf2368b2df286e38b33300000000ffffffff0257cc010000000000160014a6eed0138c8d330892a50ace4b7170899aeccf95304200000000000016001404daa8d90ec7ec9c0a394fc28ae8dd21b1ba568002483045022100d096adfb49bbba07fe723266027739075f968acf256acb986c63e34fffff434b0220156cc75d54f3fcea9c7d0b24ed7c40a7955ce516fa55fa656018bdc0aa8c3c780121027c052450a0b9ee7116b40a2402c2c4772ea4502f6c168d251dc77b0560b6baca02483045022100ada5c1e2de004e68ef9ffb68936b7dd0cff9aaa1d3fb3cb128d8afd3dc9868e10220505adec079e5d5af4bc4a7f4a89dbde8167b18ea00d3c3e460d3e6eadf23bd110121027c052450a0b9ee7116b40a2402c2c4772ea4502f6c168d251dc77b0560b6baca00000000"

const legacy_v2_tx = "02000000019945a5a440f2d3712ff095cb1efefada1cc52e139defedb92a313daed49d5678010000006a473044022031b6a6b79c666d5568a9ac7c116cacf277e11521aebc6794e2b415ef8c87c899022001fe272499ea32e6e1f6e45eb656973fbb55252f7acc64e1e1ac70837d5b7d9f0121023dec241e4851d1ec1513a48800552bae7be155c6542629636bcaa672eee971dcffffffff01a70200000000000017a9148ce773d254dc5df886b95848880e0b40f10564328700000000"

const version1 = <<1:little-size(32)>>

const min_input_size_bytes = 41

const min_output_size_bytes = 9

// ============================================================================
// decode_hex: invalid hex input
// ============================================================================

pub fn decode_hex_errors_on_odd_length_string_test() {
  assert transaction.decode_hex("010") == Error(InvalidHex)
}

pub fn decode_hex_errors_on_invalid_hex_characters_test() {
  assert transaction.decode_hex("0102zz") == Error(InvalidHex)
}

pub fn decode_hex_errors_on_string_with_whitespace_test() {
  assert transaction.decode_hex("01 02 03 04") == Error(InvalidHex)
}

// ============================================================================
// Decode Policy Builder
// ============================================================================

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

pub fn decode_policy_builder_allows_zero_limits_test() {
  let policy =
    transaction.default_decode_policy()
    |> transaction.decode_policy_with_max_input_count(0)

  assert transaction.decode_policy_max_input_count(policy) == 0
}

pub fn default_decode_policy_uses_default_witness_limits_test() {
  let policy = transaction.default_decode_policy()

  assert transaction.decode_policy_max_witness_stack_item_count(policy) == None
  assert transaction.decode_policy_max_witness_stack_payload_size(policy)
    == None
}

// ============================================================================
// Transaction Size (max_tx_size) Policy
// ============================================================================

pub fn decode_with_policy_accepts_tx_at_max_tx_size_test() {
  // Build a minimal valid tx and confirm it decodes when max_tx_size exactly
  // equals its byte length.
  let input_count = 1
  let input_padding = <<0:little-size({ min_input_size_bytes * 8 })>>
  let lock_time = <<0:little-size(32)>>
  let tx_bytes = <<
    version1:bits,
    compact_size(input_count):bits,
    input_padding:bits,
    build_minimal_output():bits,
    lock_time:bits,
  >>
  let tx_size = bit_array.byte_size(tx_bytes)

  let assert Ok(_) =
    transaction.decode_with_policy(tx_bytes, policy_with_max_tx_size(tx_size))
}

pub fn decode_with_policy_rejects_tx_exceeding_max_tx_size_test() {
  // Build a minimal valid tx and confirm it is rejected when max_tx_size is
  // one byte less than its actual size.
  let input_count = 1
  let input_padding = <<0:little-size({ min_input_size_bytes * 8 })>>
  let lock_time = <<0:little-size(32)>>
  let tx_bytes = <<
    version1:bits,
    compact_size(input_count):bits,
    input_padding:bits,
    build_minimal_output():bits,
    lock_time:bits,
  >>
  let tx_size = bit_array.byte_size(tx_bytes)

  let assert Error(ParseFailed(parse_err)) =
    transaction.decode_with_policy(
      tx_bytes,
      policy_with_max_tx_size(tx_size - 1),
    )

  assert transaction.get_parse_error_offset(parse_err) == 0
  assert transaction.get_parse_error_kind(parse_err)
    == PolicyLimitExceeded(tx_size, tx_size - 1)
  assert transaction.get_parse_error_context(parse_err) == [InTransaction]
}

pub fn decode_with_policy_rejects_tx_well_above_max_tx_size_test() {
  // Confirm that a transaction well above max_tx_size reports the correct
  // actual size and configured limit in the error.
  let assert Error(ParseFailed(parse_err)) =
    transaction.decode_with_policy(
      <<0:size({ 100 * 8 })>>,
      policy_with_max_tx_size(10),
    )

  assert transaction.get_parse_error_offset(parse_err) == 0
  assert transaction.get_parse_error_kind(parse_err)
    == PolicyLimitExceeded(100, 10)
  assert transaction.get_parse_error_context(parse_err) == [InTransaction]
}

// ============================================================================
// Version and SegWit Detection
// ============================================================================

pub fn decode_legacy_full_tx_sets_version_and_is_segwit_false_test() {
  let assert Ok(result) = transaction.decode_hex(legacy_v1_tx)

  assert transaction.get_version(result) == 1
  assert !transaction.is_segwit(result)
}

pub fn decode_legacy_tx_parses_lock_time_test() {
  let assert Ok(result) = transaction.decode_hex(legacy_v1_tx)
  assert transaction.get_lock_time(result) == 939_066
}

pub fn decode_segwit_full_tx_sets_version_and_is_segwit_true_test() {
  let assert Ok(result) = transaction.decode_hex(segwit_v1_tx)

  assert transaction.get_version(result) == 1
  assert transaction.is_segwit(result)
}

pub fn decode_segwit_tx_parses_lock_time_test() {
  let assert Ok(result) = transaction.decode_hex(segwit_v1_tx)
  assert transaction.get_lock_time(result) == 0
}

pub fn decode_legacy_v2_parses_version_2_test() {
  let assert Ok(result) = transaction.decode_hex(legacy_v2_tx)

  assert transaction.get_version(result) == 2
  assert !transaction.is_segwit(result)
}

pub fn decode_errors_on_empty_string_test() {
  let assert Error(ParseFailed(parse_err)) = transaction.decode_hex("")

  assert transaction.get_parse_error_offset(parse_err) == 0
  assert transaction.get_parse_error_kind(parse_err)
    == UnexpectedEof(bytes_needed: 4, remaining: 0)
  assert transaction.get_parse_error_context(parse_err)
    == [InTransaction, AtField(Version)]
}

pub fn decode_errors_when_input_shorter_than_4_bytes_test() {
  let assert Error(ParseFailed(parse_err)) = transaction.decode_hex("010203")

  assert transaction.get_parse_error_offset(parse_err) == 0
  assert transaction.get_parse_error_kind(parse_err) == UnexpectedEof(4, 3)
  assert transaction.get_parse_error_context(parse_err)
    == [InTransaction, AtField(Version)]
}

pub fn decode_errors_on_non_byte_aligned_input_test() {
  // Append a single trailing bit to a complete, valid transaction.
  // byte_size rounds up (N bytes + 1 bit → N+1), so the transaction passes
  // the size check and remaining appears larger than the 4 bytes needed for
  // Version. However, the reader pattern `<<bytes:bytes-size(4), rest:bytes>>`
  // requires the remainder to be byte-aligned; the 1 trailing bit makes that
  // impossible, so the very first read fails even though remaining > bytes_needed.
  let assert Ok(valid_bytes) = bit_array.base16_decode(legacy_v1_tx)
  let unaligned = <<valid_bytes:bits, 0:1>>

  let assert Error(ParseFailed(parse_err)) = transaction.decode(unaligned)

  let expected_remaining = bit_array.byte_size(valid_bytes) + 1
  assert transaction.get_parse_error_offset(parse_err) == 0
  assert transaction.get_parse_error_kind(parse_err)
    == UnexpectedEof(bytes_needed: 4, remaining: expected_remaining)
  assert transaction.get_parse_error_context(parse_err)
    == [InTransaction, AtField(Version)]
}

pub fn decode_does_not_misclassify_segwit_when_marker_and_flag_are_missing_test() {
  let assert Error(ParseFailed(parse_err)) = transaction.decode(version1)

  assert transaction.get_parse_error_offset(parse_err) == 4
  assert transaction.get_parse_error_kind(parse_err) == UnexpectedEof(1, 0)
  assert transaction.get_parse_error_context(parse_err)
    == [InTransaction, InInputs, AtField(InputCount)]
}

pub fn decode_does_not_misclassify_segwit_when_marker_and_flag_are_truncated_test() {
  let marker = <<0:size(8)>>

  let assert Error(ParseFailed(parse_err)) =
    transaction.decode(<<version1:bits, marker:bits>>)

  assert transaction.get_parse_error_offset(parse_err) == 5
  assert transaction.get_parse_error_kind(parse_err) == UnexpectedEof(1, 0)
  assert transaction.get_parse_error_context(parse_err)
    == [InTransaction, InOutputs, AtField(OutputCount)]
}

pub fn decode_returns_invalid_segwit_marker_flag_error_test() {
  let marker = <<0:size(8)>>
  let flag = <<2:little-size(8)>>

  let assert Error(ParseFailed(parse_err)) =
    transaction.decode(<<version1:bits, marker:bits, flag:bits>>)

  assert transaction.get_parse_error_offset(parse_err) == 4
  assert transaction.get_parse_error_kind(parse_err)
    == InvalidSegwitMarkerFlag(0, 2)
  assert transaction.get_parse_error_context(parse_err)
    == [InTransaction, AtField(SegwitMarkerAndFlag)]
}

pub fn decode_treats_zero_input_and_output_counts_as_empty_legacy_tx_test() {
  let lock_time = 42
  let tx_bytes = <<
    version1:bits,
    0x00,
    0x00,
    lock_time:little-size(32),
  >>

  let assert Ok(tx) = transaction.decode(tx_bytes)

  assert !transaction.is_segwit(tx)
  assert list.is_empty(transaction.get_inputs(tx))
  assert list.is_empty(transaction.get_outputs(tx))
  assert transaction.get_lock_time(tx) == lock_time
}

// ============================================================================
// Input Count Parsing and Validation
// ============================================================================

pub fn validate_input_count_minimum_succeeds_test() {
  // version (4 bytes) + input_count (CompactSize = 0x01) + 41 bytes padding

  let input_count = 1
  let input_padding = <<0:little-size({ 1 * min_input_size_bytes * 8 })>>
  let lock_time = <<0:little-size(32)>>

  let assert Ok(_) =
    transaction.decode(<<
      version1:bits,
      compact_size(input_count):bits,
      input_padding:bits,
      build_minimal_output():bits,
      lock_time:bits,
    >>)
}

pub fn validate_input_count_within_limits_succeeds_test() {
  // version (4 bytes) + input_count (CompactSize = 0x02) + padding for >= 2 inputs
  // padding: 2 * 41 = 82 bytes -> 82 * 8 = 656 bits
  // enforce a policy that permits at least 2 inputs

  let input_count = 2
  let input_padding = <<0:little-size({ 2 * min_input_size_bytes * 8 })>>
  let lock_time = <<0:little-size(32)>>

  let assert Ok(_) =
    transaction.decode_with_policy(
      <<
        version1:bits,
        compact_size(input_count):bits,
        input_padding:bits,
        build_minimal_output():bits,
        lock_time:bits,
      >>,
      policy_with_max_input_count(10),
    )
}

pub fn validate_input_count_equals_policy_succeeds_test() {
  // Pick a small policy (3). Create input_count == 3 and supply >= 3 * 41 bytes padding
  // so that max_inputs_by_bytes >= policy and the policy is the active cap.
  // should succeed when enforcing a policy that allows exactly 3 inputs

  let input_count = 3
  let input_padding = <<0:little-size({ 3 * min_input_size_bytes * 8 })>>
  let lock_time = <<0:little-size(32)>>

  let assert Ok(_) =
    transaction.decode_with_policy(
      <<
        version1:bits,
        compact_size(input_count):bits,
        input_padding:bits,
        build_minimal_output():bits,
        lock_time:bits,
      >>,
      policy_with_max_input_count(3),
    )
}

pub fn validate_input_count_exceeds_policy_error_test() {
  // Use a small policy (2). Set input_count == 3 and provide padding for
  // 3 inputs (3 * 41 = 123 bytes) so max_inputs_by_bytes == 3 (not the limiting factor).
  // With policy == 2, the policy limit is stricter, so validator should reject
  // input_count == 3 with PolicyLimitExceeded.

  let input_count = 3
  let input_padding = <<0:little-size({ 3 * min_input_size_bytes * 8 })>>

  let assert Error(ParseFailed(parse_err)) =
    transaction.decode_with_policy(
      <<version1:bits, input_count:size(8), input_padding:bits>>,
      policy_with_max_input_count(2),
    )

  assert transaction.get_parse_error_offset(parse_err) == 4

  assert transaction.get_parse_error_kind(parse_err)
    == PolicyLimitExceeded(input_count, 2)

  assert transaction.get_parse_error_context(parse_err)
    == [InTransaction, InInputs, AtField(InputCount)]
}

pub fn validate_input_count_exceeds_structural_error_test() {
  // Provide padding for exactly 2 inputs (2 * 41 = 82 bytes) so
  // max_inputs_by_bytes == 2. Use a large policy so the structural
  // limit is the active cap, then assert input_count == 3 is rejected.

  let input_count = 3
  let input_padding = <<0:little-size({ 2 * min_input_size_bytes * 8 })>>

  let assert Error(ParseFailed(parse_err)) =
    transaction.decode_with_policy(
      <<version1:bits, compact_size(input_count):bits, input_padding:bits>>,
      policy_with_max_input_count(100),
    )

  assert transaction.get_parse_error_offset(parse_err) == 4

  assert transaction.get_parse_error_kind(parse_err)
    == InsufficientBytes(
      claimed: 2 * min_input_size_bytes + 1,
      remaining: 2 * min_input_size_bytes,
    )

  assert transaction.get_parse_error_context(parse_err)
    == [InTransaction, InInputs, AtField(InputCount)]
}

pub fn validate_input_count_structural_boundary_succeeds_test() {
  // Provide padding for exactly 2 inputs (2 * 41 = 82 bytes) so
  // max_inputs_by_bytes == 2. Use a large policy so the structural
  // limit is the active cap, then assert input_count == 2 succeeds.

  let input_count = 2
  let input_padding = <<
    0:little-size({ input_count * min_input_size_bytes * 8 }),
  >>
  let lock_time = <<0:little-size(32)>>

  let assert Ok(_) =
    transaction.decode_with_policy(
      <<
        version1:bits,
        compact_size(input_count):bits,
        input_padding:bits,
        build_minimal_output():bits,
        lock_time:bits,
      >>,
      policy_with_max_input_count(100),
    )
}

pub fn validate_input_count_insufficient_bytes_for_inputs_test() {
  // Construct: version (4 bytes) + input_count (CompactSize = 0x01) + 40 bytes
  // of padding so that `remaining < min_input_size` and the validator
  // produces a LengthTooLarge error.

  let input_count = 1
  let input_padding = <<
    0:little-size({ 1 * { min_input_size_bytes - 1 } * 8 }),
  >>

  let assert Error(ParseFailed(parse_err)) =
    transaction.decode(<<
      version1:bits,
      compact_size(input_count):bits,
      input_padding:bits,
    >>)

  assert transaction.get_parse_error_offset(parse_err) == 4

  assert transaction.get_parse_error_kind(parse_err)
    == InsufficientBytes(
      remaining: min_input_size_bytes - 1,
      claimed: min_input_size_bytes,
    )

  assert transaction.get_parse_error_context(parse_err)
    == [InTransaction, InInputs, AtField(InputCount)]
}

pub fn decode_rejects_segwit_tx_with_zero_inputs_test() {
  let marker = <<0x00>>
  let flag = <<0x01>>
  let input_count = compact_size(0)
  let output_count = compact_size(1)
  let output = build_output(<<0:little-size(64)>>, <<>>)
  let lock_time = <<0:little-size(32)>>
  let expected_witness_offset = 4 + 2 + 1 + 1 + bit_array.byte_size(output)

  let tx_bytes = <<
    version1:bits,
    marker:bits,
    flag:bits,
    input_count:bits,
    output_count:bits,
    output:bits,
    lock_time:bits,
  >>

  let assert Error(ParseFailed(parse_err)) = transaction.decode(tx_bytes)

  assert transaction.get_parse_error_offset(parse_err)
    == expected_witness_offset
  assert transaction.get_parse_error_kind(parse_err) == SuperfluousWitnessRecord
  assert transaction.get_parse_error_context(parse_err) == [InTransaction]
}

// ============================================================================
// Input Structure Parsing
// ============================================================================

pub fn decode_parses_single_input_test() {
  let input_count = compact_size(1)

  // Create a transaction with a single input with specific outpoint values
  let prev_txid_bytes = repeat_byte(1, 32)
  let vout = 5
  let script_sig_bytes = <<0x48, 0x30, 0x45, 0x02, 0x21>>
  let sequence = 0xFFFFFFFE

  let input_bytes =
    build_input(prev_txid_bytes, vout, script_sig_bytes, sequence)

  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    transaction.decode(<<
      version1:bits,
      input_count:bits,
      input_bytes:bits,
      build_minimal_output():bits,
      lock_time:bits,
    >>)

  // Verify we parsed exactly one input
  let inputs = transaction.get_inputs(tx)
  let assert [first_input] = inputs

  // Verify outpoint properties
  let outpoint = transaction.get_input_outpoint(first_input)

  assert transaction.get_outpoint_txid(outpoint) == prev_txid_bytes
  assert transaction.get_outpoint_vout(outpoint) == vout

  // Verify sequence
  assert transaction.get_input_sequence(first_input) == sequence

  // Verify scriptSig
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

pub fn decode_parses_coinbase_marker_input_test() {
  let input_count = compact_size(1)

  let prev_txid_bytes = <<0:size(256)>>
  let vout = 0xFFFFFFFF
  let script_sig_bytes = <<>>
  let sequence = 0xFFFFFFFE

  let input_bytes =
    build_input(prev_txid_bytes, vout, script_sig_bytes, sequence)

  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    transaction.decode(<<
      version1:bits,
      input_count:bits,
      input_bytes:bits,
      build_minimal_output():bits,
      lock_time:bits,
    >>)

  let assert [input] = transaction.get_inputs(tx)
  assert input
    |> transaction.get_input_outpoint
    |> transaction.outpoint_is_null
}

pub fn outpoint_is_null_returns_true_for_coinbase_marker_test() {
  let outpoint = decode_single_input_outpoint(<<0:size(256)>>, 0xFFFFFFFF)
  assert transaction.outpoint_is_null(outpoint)
}

pub fn outpoint_is_null_returns_false_for_regular_outpoint_test() {
  let outpoint = decode_single_input_outpoint(repeat_byte(1, 32), 0)
  assert !transaction.outpoint_is_null(outpoint)
}

pub fn outpoint_is_null_requires_null_hash_and_max_vout_test() {
  let zero_hash_regular_vout = decode_single_input_outpoint(<<0:size(256)>>, 0)
  let nonzero_hash_max_vout =
    decode_single_input_outpoint(repeat_byte(1, 32), 0xFFFFFFFF)

  assert !transaction.outpoint_is_null(zero_hash_regular_vout)
  assert !transaction.outpoint_is_null(nonzero_hash_max_vout)
}

pub fn decode_parses_empty_scriptsig_test() {
  let input_count = compact_size(1)

  let prev_txid_bytes = <<0:size(256)>>
  let vout = 0xFFFFFFFF
  let script_sig_bytes = <<>>
  let sequence = 0xFFFFFFFE

  let input_bytes =
    build_input(prev_txid_bytes, vout, script_sig_bytes, sequence)

  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    transaction.decode(<<
      version1:bits,
      input_count:bits,
      input_bytes:bits,
      build_minimal_output():bits,
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

pub fn decode_parses_multiple_inputs_test() {
  let input_count = compact_size(3)

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
    transaction.decode(<<
      version1:bits,
      input_count:bits,
      in1_bytes:bits,
      in2_bytes:bits,
      in3_bytes:bits,
      build_minimal_output():bits,
      lock_time:bits,
    >>)

  let inputs = transaction.get_inputs(tx)
  let assert [i1, i2, i3] = inputs

  // input 1
  let outpoint1 = transaction.get_input_outpoint(i1)

  assert transaction.get_outpoint_txid(outpoint1) == prev1_txid_bytes
  assert transaction.get_outpoint_vout(outpoint1) == vout1
  assert transaction.get_input_sequence(i1) == seq1
  assert transaction.get_raw_script_bytes(transaction.get_input_script_sig(i1))
    == sig1_bytes

  // input 2
  let outpoint2 = transaction.get_input_outpoint(i2)

  assert transaction.get_outpoint_txid(outpoint2) == prev2_txid_bytes
  assert transaction.get_outpoint_vout(outpoint2) == vout2
  assert transaction.get_input_sequence(i2) == seq2
  assert transaction.get_raw_script_bytes(transaction.get_input_script_sig(i2))
    == sig2_bytes

  // input 3
  let outpoint3 = transaction.get_input_outpoint(i3)

  assert transaction.get_outpoint_txid(outpoint3) == prev3_txid_bytes
  assert transaction.get_outpoint_vout(outpoint3) == vout3
  assert transaction.get_input_sequence(i3) == seq3
  assert transaction.get_raw_script_bytes(transaction.get_input_script_sig(i3))
    == sig3_bytes
}

// ============================================================================
// ScriptSig Validation
// ============================================================================

pub fn decode_rejects_scriptsig_exceeding_max_size_test() {
  // Build a transaction with scriptSig length 10,001,
  // exceeding the 10,000-byte limit.

  let input_count = compact_size(1)

  let prev_txid = <<0:size(256)>>
  let vout = 0
  let script_sig = <<0:size({ 10_001 * 8 })>>
  let sequence = 0

  let input_bytes = build_input(prev_txid, vout, script_sig, sequence)

  let assert Error(ParseFailed(parse_err)) =
    transaction.decode(<<
      version1:bits,
      input_count:bits,
      input_bytes:bits,
    >>)

  assert transaction.get_parse_error_offset(parse_err) == 41

  assert transaction.get_parse_error_kind(parse_err)
    == PolicyLimitExceeded(10_001, 10_000)

  assert transaction.get_parse_error_context(parse_err)
    == [InTransaction, InInputs, AtInput(0), AtField(ScriptSigLength)]
}

pub fn decode_rejects_scriptsig_length_exceeds_remaining_bytes_test() {
  // Build a transaction where the scriptSig length claims 100 bytes
  // but only 10 remain.

  let input_count = compact_size(1)

  let prev_txid = <<0:size(256)>>
  let vout = <<0:little-size(32)>>

  let script_sig_length = compact_size(100)

  // Only provide 10 bytes of actual data (not enough for the claimed 100)
  let partial_script_sig = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>

  let input_bytes = <<
    prev_txid:bits,
    vout:bits,
    script_sig_length:bits,
    partial_script_sig:bits,
  >>

  let assert Error(ParseFailed(parse_err)) =
    transaction.decode(<<
      version1:bits,
      input_count:bits,
      input_bytes:bits,
    >>)

  assert transaction.get_parse_error_offset(parse_err) == 41

  assert transaction.get_parse_error_kind(parse_err)
    == InsufficientBytes(claimed: 100, remaining: 10)

  assert transaction.get_parse_error_context(parse_err)
    == [InTransaction, InInputs, AtInput(0), AtField(ScriptSigLength)]
}

pub fn decode_returns_error_with_current_input_index_test() {
  // Build a transaction with 2 inputs where the first parses successfully
  // but the second one has an error, verifying that Input(1) appears in the error context.

  let input_count = compact_size(2)

  // First input: valid and complete (41 bytes)
  let input1_bytes = build_input(<<0:size(256)>>, 0, <<>>, 0)

  // Second input: claims 100 bytes for scriptSig but we only provide 4 more bytes
  let input2_prev_txid = <<0:size(256)>>
  let input2_vout = <<0:little-size(32)>>
  let input2_script_sig_length = compact_size(100)
  let input2_partial = <<
    input2_prev_txid:bits,
    input2_vout:bits,
    input2_script_sig_length:bits,
  >>
  // Only provide 4 more bytes (for sequence) instead of 100 + 4
  let remaining_bytes = <<0:little-size(32)>>

  let assert Error(ParseFailed(parse_err)) =
    transaction.decode(<<
      version1:bits,
      input_count:bits,
      input1_bytes:bits,
      input2_partial:bits,
      remaining_bytes:bits,
    >>)

  // Verify the error occurred in the second input (index 1)
  assert transaction.get_parse_error_kind(parse_err)
    == InsufficientBytes(claimed: 100, remaining: 4)

  assert transaction.get_parse_error_context(parse_err)
    == [InTransaction, InInputs, AtInput(1), AtField(ScriptSigLength)]
}

// ============================================================================
// Output Count Parsing and Validation
// ============================================================================

pub fn validate_output_count_minimum_succeeds_test() {
  let lock_time = <<0:little-size(32)>>

  let assert Ok(_) =
    transaction.decode(<<
      version1:bits,
      build_minimal_input():bits,
      build_minimal_output():bits,
      lock_time:bits,
    >>)
}

pub fn validate_output_count_within_limits_succeeds_test() {
  // enforce a policy that permits at least 2 outputs

  let output_count = 2
  let output1 = build_output(<<0:little-size(64)>>, <<>>)
  let output2 = build_output(<<0:little-size(64)>>, <<>>)
  let lock_time = <<0:little-size(32)>>

  let assert Ok(_) =
    transaction.decode_with_policy(
      <<
        version1:bits,
        build_minimal_input():bits,
        compact_size(output_count):bits,
        output1:bits,
        output2:bits,
        lock_time:bits,
      >>,
      policy_with_max_output_count(10),
    )
}

pub fn validate_output_count_equals_policy_succeeds_test() {
  // Pick a small policy (3). Create output_count == 3 and supply 3 minimal outputs
  // so that max_outputs_by_bytes >= policy and the policy is the active cap.
  // should succeed when enforcing a policy that allows exactly 3 outputs

  let output_count = 3
  let output1 = build_output(<<0:little-size(64)>>, <<>>)
  let output2 = build_output(<<0:little-size(64)>>, <<>>)
  let output3 = build_output(<<0:little-size(64)>>, <<>>)
  let lock_time = <<0:little-size(32)>>

  let assert Ok(_) =
    transaction.decode_with_policy(
      <<
        version1:bits,
        build_minimal_input():bits,
        compact_size(output_count):bits,
        output1:bits,
        output2:bits,
        output3:bits,
        lock_time:bits,
      >>,
      policy_with_max_output_count(3),
    )
}

pub fn validate_output_count_exceeds_policy_error_test() {
  // Use a small policy (2). Set output_count == 3 and provide 3 outputs
  // (3 * 9 = 27 bytes) so max_outputs_by_bytes == 3 (not the limiting factor).
  // With policy == 2, the policy limit is stricter, so validator should reject
  // output_count == 3 with PolicyLimitExceeded.

  let output_count = 3
  let output1 = build_output(<<0:little-size(64)>>, <<>>)
  let output2 = build_output(<<0:little-size(64)>>, <<>>)
  let output3 = build_output(<<0:little-size(64)>>, <<>>)
  let lock_time = <<0:little-size(32)>>

  let assert Error(ParseFailed(parse_err)) =
    transaction.decode_with_policy(
      <<
        version1:bits,
        build_minimal_input():bits,
        compact_size(output_count):bits,
        output1:bits,
        output2:bits,
        output3:bits,
        lock_time:bits,
      >>,
      policy_with_max_output_count(2),
    )

  assert transaction.get_parse_error_kind(parse_err)
    == PolicyLimitExceeded(output_count, 2)

  assert transaction.get_parse_error_context(parse_err)
    == [InTransaction, InOutputs, AtField(OutputCount)]
}

pub fn validate_output_count_exceeds_structural_error_test() {
  // Provide exactly 2 outputs (2 * 9 = 18 bytes) so max_outputs_by_bytes == 2.
  // Use a large policy (100) so the structural limit is the active cap,
  // then assert output_count == 3 is rejected.

  let output_count = 3
  let output1 = build_output(<<0:little-size(64)>>, <<>>)
  let output2 = build_output(<<0:little-size(64)>>, <<>>)

  let assert Error(ParseFailed(parse_err)) =
    transaction.decode_with_policy(
      <<
        version1:bits,
        build_minimal_input():bits,
        compact_size(output_count):bits,
        output1:bits,
        output2:bits,
      >>,
      policy_with_max_output_count(100),
    )

  assert transaction.get_parse_error_offset(parse_err) == 46

  assert transaction.get_parse_error_kind(parse_err)
    == InsufficientBytes(
      claimed: 2 * min_output_size_bytes + 1,
      remaining: 2 * min_output_size_bytes,
    )

  assert transaction.get_parse_error_context(parse_err)
    == [InTransaction, InOutputs, AtField(OutputCount)]
}

pub fn validate_output_count_structural_boundary_succeeds_test() {
  // Provide exactly 2 outputs (2 * 9 = 18 bytes) so max_outputs_by_bytes == 2.
  // Use a large policy (100) so the structural limit is the active cap,
  // then assert output_count == 2 succeeds.

  let output_count = 2
  let output1 = build_output(<<0:little-size(64)>>, <<>>)
  let output2 = build_output(<<0:little-size(64)>>, <<>>)
  let lock_time = <<0:little-size(32)>>

  let assert Ok(_) =
    transaction.decode_with_policy(
      <<
        version1:bits,
        build_minimal_input():bits,
        compact_size(output_count):bits,
        output1:bits,
        output2:bits,
        lock_time:bits,
      >>,
      policy_with_max_output_count(100),
    )
}

pub fn validate_output_count_insufficient_bytes_for_outputs_test() {
  // Construct: version (4 bytes) + input_count (1) + input (41 bytes) + output_count (1) + 8 bytes
  // of padding so that `remaining < min_output_size` and the validator
  // produces a InsufficientBytes error.

  let output_count = 1
  let output_padding = <<
    0:little-size({ 1 * { min_output_size_bytes - 1 } * 8 }),
  >>

  let assert Error(ParseFailed(parse_err)) =
    transaction.decode(<<
      version1:bits,
      build_minimal_input():bits,
      compact_size(output_count):bits,
      output_padding:bits,
    >>)

  assert transaction.get_parse_error_kind(parse_err)
    == InsufficientBytes(
      remaining: min_output_size_bytes - 1,
      claimed: min_output_size_bytes,
    )

  assert transaction.get_parse_error_context(parse_err)
    == [InTransaction, InOutputs, AtField(OutputCount)]
}

pub fn decode_accepts_legacy_tx_with_zero_outputs_test() {
  // Demonstrate that a legacy transaction with 0 outputs can be represented
  // in bytes and successfully decoded (though it would fail context-free
  // consensus validation).
  let output_count = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    build_minimal_input():bits,
    output_count:bits,
    lock_time:bits,
  >>

  let assert Ok(tx) = transaction.decode(tx_bytes)
  assert !transaction.is_segwit(tx)
  assert list.is_empty(transaction.get_outputs(tx))
}

pub fn decode_accepts_segwit_tx_with_zero_outputs_test() {
  // Demonstrate that a SegWit transaction with 0 outputs can be represented
  // in bytes and successfully decoded (though it would fail context-free
  // consensus validation).
  let marker = <<0x00>>
  let flag = <<0x01>>
  let input_count = compact_size(1)
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let output_count = compact_size(0)
  // One zero-length item counts as witness data.
  let witness_stack = <<compact_size(1):bits, compact_size(0):bits>>
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    marker:bits,
    flag:bits,
    input_count:bits,
    input:bits,
    output_count:bits,
    witness_stack:bits,
    lock_time:bits,
  >>

  let assert Ok(tx) = transaction.decode(tx_bytes)
  assert transaction.is_segwit(tx)
  assert list.is_empty(transaction.get_outputs(tx))
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
    transaction.decode(<<
      version1:bits,
      build_minimal_input():bits,
      compact_size(1):bits,
      output:bits,
      lock_time:bits,
    >>)

  // Verify we parsed exactly one output
  let outputs = transaction.get_outputs(tx)
  let assert [first_output] = outputs

  // Verify output properties
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

pub fn decode_parses_multiple_outputs_test() {
  let output_count = compact_size(3)

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
    transaction.decode(<<
      version1:bits,
      build_minimal_input():bits,
      output_count:bits,
      out1_bytes:bits,
      out2_bytes:bits,
      out3_bytes:bits,
      lock_time:bits,
    >>)

  let outputs = transaction.get_outputs(tx)
  let assert [o1, o2, o3] = outputs

  // output 1
  let actual_value1 =
    o1
    |> transaction.get_output_value

  assert actual_value1 == 0

  let actual_script1_bytes =
    o1
    |> transaction.get_output_script_pubkey
    |> transaction.get_raw_script_bytes

  assert actual_script1_bytes == script1_bytes

  // output 2
  let actual_value2 =
    o2
    |> transaction.get_output_value

  assert actual_value2 == 100_000_000

  let actual_script2_bytes =
    o2
    |> transaction.get_output_script_pubkey
    |> transaction.get_raw_script_bytes

  assert actual_script2_bytes == script2_bytes

  // output 3
  let actual_value3 =
    o3
    |> transaction.get_output_value

  assert actual_value3 == 50_000_000

  let actual_script3_bytes =
    o3
    |> transaction.get_output_script_pubkey
    |> transaction.get_raw_script_bytes

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
    transaction.decode(<<
      version1:bits,
      build_minimal_input():bits,
      compact_size(1):bits,
      output:bits,
      lock_time:bits,
    >>)

  // Verify we parsed exactly one output
  let outputs = transaction.get_outputs(tx)
  let assert [first_output] = outputs

  // Verify output properties
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

// ============================================================================
// Output Value Validation
// ============================================================================

pub fn decode_handles_output_value_min_i64_for_target_test() {
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
    version1:bits,
    build_minimal_input():bits,
    output_count:bits,
    output_bytes:bits,
    lock_time:bits,
  >>

  case target.is_javascript() {
    True -> {
      let assert Error(ParseFailed(parse_err)) = transaction.decode(tx_bytes)

      assert transaction.get_parse_error_kind(parse_err)
        == transaction.IntegerOutOfRange("-9223372036854775808")

      assert transaction.get_parse_error_context(parse_err)
        == [InTransaction, InOutputs, AtOutput(0), AtField(transaction.Value)]
    }

    False -> {
      let min_i64_output_value = {
        // Compute from smaller literals to avoid JavaScript truncation warning
        let two_to_31 = 2_147_483_648
        let two_to_32 = 4_294_967_296
        0 - two_to_31 * two_to_32
      }

      let assert Ok(tx) = transaction.decode(tx_bytes)
      let assert [output] = transaction.get_outputs(tx)
      assert transaction.get_output_value(output) == min_i64_output_value
    }
  }
}

pub fn decode_accepts_outputs_total_value_exactly_at_max_money_test() {
  // Create a transaction with outputs totaling exactly max_satoshis (should succeed)
  // max_satoshis = 2_100_000_000_000_000
  // output1 = 1_050_000_000_000_000
  // output2 = 1_050_000_000_000_000
  // total = 2_100_000_000_000_000 (exactly at limit)

  let output_count = compact_size(2)
  let value1 = 1_050_000_000_000_000
  let value2 = 1_050_000_000_000_000
  let script_pubkey = <<>>

  let output1 = build_output(<<value1:little-size(64)>>, script_pubkey)
  let output2 = build_output(<<value2:little-size(64)>>, script_pubkey)
  let lock_time = <<0:little-size(32)>>

  let assert Ok(_) =
    transaction.decode(<<
      version1:bits,
      build_minimal_input():bits,
      output_count:bits,
      output1:bits,
      output2:bits,
      lock_time:bits,
    >>)
}

// ============================================================================
// ScriptPubKey Validation
// ============================================================================

pub fn decode_rejects_scriptpubkey_exceeding_max_size_test() {
  // Build an output with scriptPubKey length 10,001,
  // exceeding the 10,000-byte limit.

  let output_count = compact_size(1)

  let value = <<0:little-size(64)>>
  let script_pubkey = <<0:size({ 10_001 * 8 })>>

  let output_bytes = build_output(value, script_pubkey)

  let assert Error(ParseFailed(parse_err)) =
    transaction.decode(<<
      version1:bits,
      build_minimal_input():bits,
      output_count:bits,
      output_bytes:bits,
    >>)

  assert transaction.get_parse_error_offset(parse_err) == 55

  assert transaction.get_parse_error_kind(parse_err)
    == PolicyLimitExceeded(10_001, 10_000)

  assert transaction.get_parse_error_context(parse_err)
    == [InTransaction, InOutputs, AtOutput(0), AtField(ScriptPubKeyLength)]
}

pub fn decode_parses_scriptpubkey_at_max_size_test() {
  // Create a transaction with an output that has a scriptPubKey of exactly 10,000 bytes (MAX_SCRIPT_SIZE)
  let value_satoshis = 75_000_000
  let script_pubkey_bytes = <<0:size({ 10_000 * 8 })>>
  let output =
    build_output(<<value_satoshis:little-size(64)>>, script_pubkey_bytes)
  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    transaction.decode(<<
      version1:bits,
      build_minimal_input():bits,
      compact_size(1):bits,
      output:bits,
      lock_time:bits,
    >>)

  // Verify we parsed exactly one output
  let outputs = transaction.get_outputs(tx)
  let assert [first_output] = outputs

  // Verify output properties
  let actual_value =
    first_output
    |> transaction.get_output_value

  assert actual_value == value_satoshis

  let actual_script_pubkey_bytes =
    first_output
    |> transaction.get_output_script_pubkey
    |> transaction.get_raw_script_bytes

  assert bit_array.byte_size(actual_script_pubkey_bytes) == 10_000
}

pub fn validate_scriptpubkey_insufficient_bytes_error_test() {
  // Build an output where the scriptPubKey length claims 100 bytes
  // but only 10 remain.

  let output_count = compact_size(1)

  let value = <<0:little-size(64)>>
  let script_pubkey_length = compact_size(100)

  // Only provide 10 bytes of actual data (not enough for the claimed 100)
  let partial_script_pubkey = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>

  let output_bytes = <<
    value:bits,
    script_pubkey_length:bits,
    partial_script_pubkey:bits,
  >>

  let assert Error(ParseFailed(parse_err)) =
    transaction.decode(<<
      version1:bits,
      build_minimal_input():bits,
      output_count:bits,
      output_bytes:bits,
    >>)

  assert transaction.get_parse_error_kind(parse_err)
    == InsufficientBytes(claimed: 100, remaining: 10)

  assert transaction.get_parse_error_context(parse_err)
    == [InTransaction, InOutputs, AtOutput(0), AtField(ScriptPubKeyLength)]
}

// ============================================================================
// Witness Data Parsing
// ============================================================================

pub fn decode_segwit_tx_parses_witness_data_test() {
  // Use the real SegWit transaction constant
  let assert Ok(tx) = transaction.decode_hex(segwit_v1_tx)

  // Verify it's identified as a SegWit transaction
  assert transaction.is_segwit(tx)

  // Verify basic transaction properties
  assert transaction.get_version(tx) == 1

  // Verify inputs were parsed correctly
  let inputs = transaction.get_inputs(tx)
  let assert [_, ..] = inputs

  // Verify outputs were parsed correctly
  let outputs = transaction.get_outputs(tx)
  let assert [_, ..] = outputs

  // Verify witness data was parsed
  let assert Ok(witnesses) = transaction.get_witnesses(tx)
  let assert [witness_stack, ..] = witnesses

  // Verify the witness stack has 2 items (likely signature and pubkey for P2WPKH)
  let witness_items = transaction.get_witness_items(witness_stack)
  let assert [item1, item2] = witness_items

  // Verify the items are non-empty (actual signature and pubkey data)
  assert bit_array.byte_size(transaction.get_witness_item_bytes(item1)) > 0
  assert bit_array.byte_size(transaction.get_witness_item_bytes(item2)) > 0
}

pub fn decode_rejects_segwit_tx_with_all_empty_witness_stacks_test() {
  // Build inputs
  let input1 = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let input2 = build_input(repeat_byte(1, 32), 1, <<0x01, 0x02>>, 0xFFFFFFFF)

  // Build output
  let output = build_output(<<1000:little-size(64)>>, <<0x76, 0xa9>>)

  // Empty witness stacks: each input gets a witness stack with 0 items
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
    build_segwit_tx([input1, input2], [output], [witness_stack1, witness_stack2])

  let assert Error(ParseFailed(parse_err)) = transaction.decode(tx_bytes)

  assert transaction.get_parse_error_offset(parse_err)
    == expected_witness_offset
  assert transaction.get_parse_error_kind(parse_err) == SuperfluousWitnessRecord
  assert transaction.get_parse_error_context(parse_err) == [InTransaction]
}

pub fn decode_segwit_tx_allows_empty_stack_when_another_stack_has_item_test() {
  let input1 = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let input2 = build_input(repeat_byte(1, 32), 1, <<0x01, 0x02>>, 0xFFFFFFFF)
  let output = build_output(<<1000:little-size(64)>>, <<0x76, 0xa9>>)

  let empty_stack = compact_size(0)
  let stack_with_empty_item = <<compact_size(1):bits, compact_size(0):bits>>

  let tx_bytes =
    build_segwit_tx([input1, input2], [output], [
      empty_stack,
      stack_with_empty_item,
    ])

  let assert Ok(tx) = transaction.decode(tx_bytes)

  let assert Ok(witnesses) = transaction.get_witnesses(tx)
  let assert [stack1, stack2] = witnesses

  let items1 = transaction.get_witness_items(stack1)
  let items2 = transaction.get_witness_items(stack2)

  assert items1 == []
  let assert [empty_item] = items2
  assert transaction.get_witness_item_bytes(empty_item) == <<>>
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

  let assert Ok(tx) = transaction.decode(tx_bytes)

  // Verify it's SegWit
  assert transaction.is_segwit(tx)

  // Get the witness stack
  let assert Ok(witnesses) = transaction.get_witnesses(tx)
  let assert [stack] = witnesses

  // Verify it has 3 items
  let items = transaction.get_witness_items(stack)
  let assert [item1, item2, item3] = items

  // Verify each item has the correct data
  let data1 = transaction.get_witness_item_bytes(item1)
  let data2 = transaction.get_witness_item_bytes(item2)
  let data3 = transaction.get_witness_item_bytes(item3)

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

  let assert Ok(tx) = transaction.decode(tx_bytes)

  // Verify it's SegWit
  assert transaction.is_segwit(tx)

  // Get the witness stack
  let assert Ok(witnesses) = transaction.get_witnesses(tx)
  let assert [stack] = witnesses

  // Verify it has 1 item
  let items = transaction.get_witness_items(stack)
  let assert [item] = items

  // Verify the item is zero-length
  let data = transaction.get_witness_item_bytes(item)
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

  let assert Error(ParseFailed(parse_err)) = transaction.decode(tx_bytes)

  // The compact_size encoding of 100 takes 3 bytes (0xFD + 2 bytes),
  // so remaining = 10 data bytes + 4 bytes overhead = 14
  assert transaction.get_parse_error_kind(parse_err)
    == InsufficientBytes(claimed: 100, remaining: 14)

  // Verify the error context indicates we're in witness item length parsing
  assert transaction.get_parse_error_context(parse_err)
    == [
      InTransaction,
      AtWitnessStack(0),
      AtWitnessItem(0),
      AtField(WitnessItemLength),
    ]
}

pub fn decode_witness_invalid_compact_size_in_item_count_test() {
  // Build input and output normally
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output(<<1000:little-size(64)>>, <<>>)

  // Manually construct transaction with invalid CompactSize witness item count
  // CompactSize 0xFD requires 2 bytes following, but provide only 1 (truncated)
  let marker = <<0x00>>
  let flag = <<0x01>>
  let input_count = compact_size(1)
  let output_count = compact_size(1)
  let lock_time = <<0:little-size(32)>>

  // Invalid witness stack: 0xFD followed by only 1 byte (truncated CompactSize)
  let invalid_witness_stack = <<0xFD, 0x01>>

  let tx_bytes = <<
    version1:bits,
    marker:bits,
    flag:bits,
    input_count:bits,
    input:bits,
    output_count:bits,
    output:bits,
    invalid_witness_stack:bits,
    lock_time:bits,
  >>

  let assert Error(ParseFailed(parse_err)) = transaction.decode(tx_bytes)

  assert transaction.get_parse_error_kind(parse_err)
    == NonMinimalCompactSize(3, 1)

  // Verify the error context indicates we're in witness item count parsing
  assert transaction.get_parse_error_context(parse_err)
    == [InTransaction, AtWitnessStack(0), AtField(WitnessItemCount)]
}

pub fn decode_witness_invalid_compact_size_in_item_length_test() {
  // Build input and output normally
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output(<<1000:little-size(64)>>, <<>>)

  // Manually construct transaction with invalid CompactSize in witness item length
  let marker = <<0x00>>
  let flag = <<0x01>>
  let input_count = compact_size(1)
  let output_count = compact_size(1)
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
    input_count:bits,
    input:bits,
    output_count:bits,
    output:bits,
    invalid_witness_stack:bits,
    lock_time:bits,
  >>

  let assert Error(ParseFailed(parse_err)) = transaction.decode(tx_bytes)

  assert transaction.get_parse_error_kind(parse_err)
    == NonMinimalCompactSize(3, 1)
  assert transaction.get_parse_error_context(parse_err)
    == [
      InTransaction,
      AtWitnessStack(0),
      AtWitnessItem(0),
      AtField(WitnessItemLength),
    ]
}

// ============================================================================
// Witness Stack Item Count Policy Enforcement
// ============================================================================

pub fn decode_witness_stack_at_max_item_count_succeeds_test() {
  let max_witness_stack_item_count = 3

  // Build input and output
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output(<<1000:little-size(64)>>, <<>>)

  // Build witness stack with exactly max_witness_stack_item_count items
  let witness_items =
    int.range(0, max_witness_stack_item_count, with: <<>>, run: fn(acc, _) {
      <<acc:bits, compact_size(5):bits, 1, 2, 3, 4, 5>>
    })

  let witness_stack = <<
    compact_size(max_witness_stack_item_count):bits,
    witness_items:bits,
  >>

  let tx_bytes = build_segwit_tx([input], [output], [witness_stack])

  let policy =
    policy_with_max_witness_stack_item_count(max_witness_stack_item_count)

  let assert Ok(tx) = transaction.decode_with_policy(tx_bytes, policy)

  // Verify the witness stack has the correct number of items
  let assert Ok(witnesses) = transaction.get_witnesses(tx)
  let assert [stack] = witnesses

  let items = transaction.get_witness_items(stack)
  assert list.length(items) == max_witness_stack_item_count
}

pub fn decode_witness_stack_exceeds_max_item_count_fails_test() {
  let max_witness_stack_item_count = 2

  // Build input and output
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output(<<1000:little-size(64)>>, <<>>)

  // Build witness stack with max_witness_stack_item_count + 1 items
  let witness_items =
    int.range(0, max_witness_stack_item_count + 1, with: <<>>, run: fn(acc, _) {
      <<acc:bits, compact_size(5):bits, 1, 2, 3, 4, 5>>
    })

  let witness_stack = <<
    compact_size(max_witness_stack_item_count + 1):bits,
    witness_items:bits,
  >>

  let tx_bytes = build_segwit_tx([input], [output], [witness_stack])

  let policy =
    policy_with_max_witness_stack_item_count(max_witness_stack_item_count)

  let assert Error(ParseFailed(parse_err)) =
    transaction.decode_with_policy(tx_bytes, policy)

  assert transaction.get_parse_error_offset(parse_err) == 58

  // Verify the error kind indicates the count exceeded max_witness_stack_item_count
  assert transaction.get_parse_error_kind(parse_err)
    == PolicyLimitExceeded(
      max_witness_stack_item_count + 1,
      max_witness_stack_item_count,
    )

  // Verify the error context indicates witness item count validation
  assert transaction.get_parse_error_context(parse_err)
    == [InTransaction, AtWitnessStack(0), AtField(WitnessItemCount)]
}

// ============================================================================
// Witness Stack Payload Size Policy Enforcement
// ============================================================================

pub fn decode_witness_stack_at_max_payload_size_succeeds_test() {
  let max_witness_stack_payload_size = 50

  // Build input and output
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output(<<1000:little-size(64)>>, <<>>)

  // Build witness stack with items totaling exactly max_witness_stack_payload_size
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
    policy_with_max_witness_stack_payload_size(max_witness_stack_payload_size)

  let assert Ok(tx) = transaction.decode_with_policy(tx_bytes, policy)

  // Verify the witness stack was parsed correctly
  let assert Ok(witnesses) = transaction.get_witnesses(tx)
  let assert [stack] = witnesses

  let items = transaction.get_witness_items(stack)
  assert list.length(items) == 3

  // Verify total payload size
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

pub fn decode_witness_stack_exceeds_max_payload_size_fails_test() {
  let max_witness_stack_payload_size = 50

  // Build input and output
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output(<<1000:little-size(64)>>, <<>>)

  // Build witness stack exceeding max_witness_stack_payload_size
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
    policy_with_max_witness_stack_payload_size(max_witness_stack_payload_size)

  let assert Error(ParseFailed(parse_err)) =
    transaction.decode_with_policy(tx_bytes, policy)

  // Verify the error kind indicates policy limit was exceeded
  assert transaction.get_parse_error_kind(parse_err)
    == PolicyLimitExceeded(51, max_witness_stack_payload_size)

  // Verify the error context indicates witness stack validation
  assert transaction.get_parse_error_context(parse_err)
    == [
      InTransaction,
      AtWitnessStack(0),
      AtWitnessItem(2),
      AtField(WitnessStackPayloadSize),
    ]
}

pub fn decode_witness_stack_error_offset_points_to_third_item_test() {
  // Verify that when witnessStack_total_payload_bytes limit is exceeded at the
  // third witness item, the error offset points to the start of the third item's
  // length field

  let max_witness_stack_payload_size = 50

  // Build input and output
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output(<<1000:little-size(64)>>, <<>>)

  // Build witness stack exceeding max_witness_stack_payload_size
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
    policy_with_max_witness_stack_payload_size(max_witness_stack_payload_size)

  let assert Error(ParseFailed(parse_err)) =
    transaction.decode_with_policy(tx_bytes, policy)

  // Calculate expected offset to start of third witness item's length field:
  // version (4) + marker (1) + flag (1) + input_count (1) + input (41) +
  // output_count (1) + output (9) + witness item count (1) +
  // item1 length (1) + item1 bytes (20) + item2 length (1) + item2 bytes (15)
  let expected_offset = 4 + 1 + 1 + 1 + 41 + 1 + 9 + 1 + 1 + 20 + 1 + 15

  assert transaction.get_parse_error_offset(parse_err) == expected_offset
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
    transaction.decode(<<valid_tx:bits, 0x42:size(8)>>)

  assert transaction.get_parse_error_kind(parse_err) == TrailingBytes(1)
  assert transaction.get_parse_error_context(parse_err) == [InTransaction]

  let expected_offset = bit_array.byte_size(valid_tx)
  assert transaction.get_parse_error_offset(parse_err) == expected_offset
}

pub fn decode_rejects_segwit_tx_with_trailing_byte_test() {
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output(<<0:little-size(64)>>, <<>>)
  let witness_stack = <<compact_size(1):bits, compact_size(0):bits>>

  let valid_tx = build_segwit_tx([input], [output], [witness_stack])

  let assert Error(ParseFailed(parse_err)) =
    transaction.decode(<<valid_tx:bits, 0xFF:size(8)>>)

  assert transaction.get_parse_error_kind(parse_err) == TrailingBytes(1)
  assert transaction.get_parse_error_context(parse_err) == [InTransaction]

  let expected_offset = bit_array.byte_size(valid_tx)
  assert transaction.get_parse_error_offset(parse_err) == expected_offset
}

// ============================================================================
// classify_output_script
// ============================================================================

pub fn classify_output_script_p2pkh_test() {
  let hash = repeat_byte(0xAA, 20)
  let script_bytes = <<0x76, 0xA9, 0x14, hash:bits, 0x88, 0xAC>>
  assert transaction.classify_output_script(decode_script_pubkey(script_bytes))
    == P2PKH
}

pub fn classify_output_script_p2sh_test() {
  let hash = repeat_byte(0xBB, 20)
  let script_bytes = <<0xA9, 0x14, hash:bits, 0x87>>
  assert transaction.classify_output_script(decode_script_pubkey(script_bytes))
    == P2SH
}

pub fn classify_output_script_p2wpkh_test() {
  let hash = repeat_byte(0xCC, 20)
  let script_bytes = <<0x00, 0x14, hash:bits>>
  assert transaction.classify_output_script(decode_script_pubkey(script_bytes))
    == P2WPKH
}

pub fn classify_output_script_p2wsh_test() {
  let hash = repeat_byte(0xDD, 32)
  let script_bytes = <<0x00, 0x20, hash:bits>>
  assert transaction.classify_output_script(decode_script_pubkey(script_bytes))
    == P2WSH
}

pub fn classify_output_script_p2tr_test() {
  let pubkey = repeat_byte(0xEE, 32)
  let script_bytes = <<0x51, 0x20, pubkey:bits>>
  assert transaction.classify_output_script(decode_script_pubkey(script_bytes))
    == P2TR
}

pub fn classify_output_script_p2pk_compressed_test() {
  let pubkey = repeat_byte(0x02, 33)
  let script_bytes = <<0x21, pubkey:bits, 0xAC>>
  assert transaction.classify_output_script(decode_script_pubkey(script_bytes))
    == P2PK
}

pub fn classify_output_script_p2pk_uncompressed_test() {
  let pubkey = repeat_byte(0x04, 65)
  let script_bytes = <<0x41, pubkey:bits, 0xAC>>
  assert transaction.classify_output_script(decode_script_pubkey(script_bytes))
    == P2PK
}

pub fn classify_output_script_nulldata_with_data_test() {
  let script_bytes = <<0x6A, 0x04, 0xDE, 0xAD, 0xBE, 0xEF>>
  assert transaction.classify_output_script(decode_script_pubkey(script_bytes))
    == NullData
}

pub fn classify_output_script_nulldata_empty_test() {
  let script_bytes = <<0x6A>>
  assert transaction.classify_output_script(decode_script_pubkey(script_bytes))
    == NullData
}

pub fn classify_output_script_nulldata_non_push_is_non_standard_test() {
  // OP_RETURN OP_ADD — non-push opcode after OP_RETURN is not a standard null-data script
  let script_bytes = <<0x6A, 0x93>>
  assert transaction.classify_output_script(decode_script_pubkey(script_bytes))
    == NonStandard
}

pub fn classify_output_script_multisig_1of1_test() {
  let pubkey = repeat_byte(0xAA, 33)
  let script_bytes = <<0x51, 0x21, pubkey:bits, 0x51, 0xAE>>
  assert transaction.classify_output_script(decode_script_pubkey(script_bytes))
    == BareMultisig
}

pub fn classify_output_script_multisig_2of3_test() {
  let pubkey1 = repeat_byte(0xAA, 33)
  let pubkey2 = repeat_byte(0xBB, 33)
  let pubkey3 = repeat_byte(0xCC, 33)
  let script_bytes = <<
    0x52, 0x21, pubkey1:bits, 0x21, pubkey2:bits, 0x21, pubkey3:bits, 0x53, 0xAE,
  >>
  assert transaction.classify_output_script(decode_script_pubkey(script_bytes))
    == BareMultisig
}

pub fn classify_output_script_unknown_witness_v1_non_taproot_test() {
  // OP_1 with a 20-byte program — valid witness v1 but not Taproot (which requires 32 bytes)
  let program = repeat_byte(0xFF, 20)
  let script_bytes = <<0x51, 0x14, program:bits>>
  assert transaction.classify_output_script(decode_script_pubkey(script_bytes))
    == UnknownWitnessProgram(version: 1)
}

pub fn classify_output_script_unknown_witness_v2_test() {
  let program = repeat_byte(0xFF, 32)
  let script_bytes = <<0x52, 0x20, program:bits>>
  assert transaction.classify_output_script(decode_script_pubkey(script_bytes))
    == UnknownWitnessProgram(version: 2)
}

pub fn classify_output_script_unknown_witness_v16_test() {
  let program = repeat_byte(0xFF, 20)
  let script_bytes = <<0x60, 0x14, program:bits>>
  assert transaction.classify_output_script(decode_script_pubkey(script_bytes))
    == UnknownWitnessProgram(version: 16)
}

pub fn classify_output_script_non_standard_test() {
  let script_bytes = <<0x00, 0x01, 0xAA>>
  assert transaction.classify_output_script(decode_script_pubkey(script_bytes))
    == NonStandard
}

pub fn classify_output_script_empty_test() {
  // Zero-length script — no pattern matches → NonStandard
  let script_bytes = <<>>
  assert transaction.classify_output_script(decode_script_pubkey(script_bytes))
    == NonStandard
}

pub fn classify_output_script_nulldata_at_max_size_test() {
  // OP_RETURN (1) + OP_PUSHDATA1 (1) + length byte (1) + 80 bytes = 83 bytes total → NullData
  let data = repeat_byte(0xAB, 80)
  let script_bytes = <<0x6A, 0x4C, 80, data:bits>>

  assert transaction.classify_output_script(decode_script_pubkey(script_bytes))
    == NullData
}

pub fn classify_output_script_nulldata_over_max_size_test() {
  // OP_RETURN (1) + OP_PUSHDATA1 (1) + length byte (1) + 81 bytes = 84 bytes total → NonStandard
  let data = repeat_byte(0xAB, 81)
  let script_bytes = <<0x6A, 0x4C, 81, data:bits>>

  assert transaction.classify_output_script(decode_script_pubkey(script_bytes))
    == NonStandard
}

pub fn classify_output_script_multisig_3of3_test() {
  let pubkey1 = repeat_byte(0xAA, 33)
  let pubkey2 = repeat_byte(0xBB, 33)
  let pubkey3 = repeat_byte(0xCC, 33)
  let script_bytes = <<
    0x53, 0x21, pubkey1:bits, 0x21, pubkey2:bits, 0x21, pubkey3:bits, 0x53, 0xAE,
  >>
  assert transaction.classify_output_script(decode_script_pubkey(script_bytes))
    == BareMultisig
}

pub fn classify_output_script_multisig_invalid_m_gt_n_test() {
  // OP_3 <2 pubkeys> OP_2 OP_CHECKMULTISIG — m(3) > n(2), invalid
  let pubkey1 = repeat_byte(0xAA, 33)
  let pubkey2 = repeat_byte(0xBB, 33)
  let script_bytes = <<
    0x53, 0x21, pubkey1:bits, 0x21, pubkey2:bits, 0x52, 0xAE,
  >>
  assert transaction.classify_output_script(decode_script_pubkey(script_bytes))
    == NonStandard
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
  assert transaction.classify_output_script(decode_script_pubkey(script_bytes))
    == NonStandard
}

pub fn classify_output_script_unknown_witness_v1_min_program_test() {
  // OP_1 + OP_DATA_2 + 2-byte program — minimum valid witness program length
  let program = repeat_byte(0xFF, 2)
  let script_bytes = <<0x51, 0x02, program:bits>>
  assert transaction.classify_output_script(decode_script_pubkey(script_bytes))
    == UnknownWitnessProgram(version: 1)
}

pub fn classify_output_script_unknown_witness_v1_max_program_test() {
  // OP_1 + OP_DATA_40 + 40-byte program — maximum valid witness program length
  let program = repeat_byte(0xFF, 40)
  let script_bytes = <<0x51, 0x28, program:bits>>
  assert transaction.classify_output_script(decode_script_pubkey(script_bytes))
    == UnknownWitnessProgram(version: 1)
}

// ============================================================================
// Context-Free Consensus Validation
// ============================================================================

pub fn validate_context_free_consensus_accepts_valid_legacy_tx_test() {
  // Use a real legacy transaction that has 1 input and 1 output
  let assert Ok(parsed_tx) = transaction.decode_hex(legacy_v1_tx)

  assert !transaction.is_segwit(parsed_tx)

  let assert Ok(validated_tx) =
    transaction.validate_context_free_consensus(parsed_tx)

  // Verify the context-free-validated transaction maintains the same properties
  assert !transaction.is_segwit(validated_tx)
  assert transaction.get_version(validated_tx)
    == transaction.get_version(parsed_tx)
  assert list.length(transaction.get_inputs(validated_tx))
    == list.length(transaction.get_inputs(parsed_tx))
  assert list.length(transaction.get_outputs(validated_tx))
    == list.length(transaction.get_outputs(parsed_tx))
  assert transaction.get_lock_time(validated_tx)
    == transaction.get_lock_time(parsed_tx)
}

pub fn validate_context_free_consensus_accepts_valid_segwit_tx_test() {
  let assert Ok(parsed_tx) = transaction.decode_hex(segwit_v1_tx)

  assert transaction.is_segwit(parsed_tx)

  let assert Ok(validated_tx) =
    transaction.validate_context_free_consensus(parsed_tx)

  // Verify the context-free-validated transaction maintains the same properties
  assert transaction.is_segwit(validated_tx)
  assert transaction.get_version(validated_tx)
    == transaction.get_version(parsed_tx)
  assert list.length(transaction.get_inputs(validated_tx))
    == list.length(transaction.get_inputs(parsed_tx))
  assert list.length(transaction.get_outputs(validated_tx))
    == list.length(transaction.get_outputs(parsed_tx))
  assert transaction.get_lock_time(validated_tx)
    == transaction.get_lock_time(parsed_tx)
  assert transaction.get_witnesses(validated_tx)
    == transaction.get_witnesses(parsed_tx)
}

pub fn validate_context_free_consensus_collects_no_inputs_and_no_outputs_test() {
  let tx_bytes = <<
    version1:bits,
    0x00,
    0x00,
    0:little-size(32),
  >>

  let assert Ok(parsed_tx) = transaction.decode(tx_bytes)

  assert transaction.validate_context_free_consensus(parsed_tx)
    == Error([NoInputs, NoOutputs])
}

pub fn validate_context_free_consensus_rejects_tx_with_no_outputs_test() {
  // Build a legacy transaction with 1 input and 0 outputs
  let input_count = compact_size(1)
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let output_count = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    input_count:bits,
    input:bits,
    output_count:bits,
    lock_time:bits,
  >>

  let assert Ok(parsed_tx) = transaction.decode(tx_bytes)

  assert transaction.validate_context_free_consensus(parsed_tx)
    == Error([NoOutputs])
}

pub fn validate_context_free_consensus_rejects_tx_with_negative_output_value_test() {
  let input_count = compact_size(1)
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let output_count = compact_size(1)
  // -1 as signed int64
  let negative_value = <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    input_count:bits,
    input:bits,
    output_count:bits,
    negative_value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(parsed_tx) = transaction.decode(tx_bytes)

  assert transaction.validate_context_free_consensus(parsed_tx)
    == Error([OutputValueOutOfRange(0, -1)])
}

pub fn validate_context_free_consensus_rejects_tx_with_output_exceeding_supply_test() {
  // Build a transaction with single output > max_satoshis (2_100_000_000_000_000)
  // Use 2_100_000_000_000_001 which exceeds the max supply
  let input_count = compact_size(1)
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let output_count = compact_size(1)
  let excessive_value = <<2_100_000_000_000_001:little-size(64)>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    input_count:bits,
    input:bits,
    output_count:bits,
    excessive_value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(parsed_tx) = transaction.decode(tx_bytes)

  assert transaction.validate_context_free_consensus(parsed_tx)
    == Error([OutputValueOutOfRange(0, 2_100_000_000_000_001)])
}

pub fn validate_context_free_consensus_rejects_tx_with_total_outputs_exceeding_supply_test() {
  // Build a transaction with two outputs that individually are valid but total exceeds max_satoshis
  // Each output: 1_100_000_000_000_000, Total: 2_200_000_000_000_000 > 2_100_000_000_000_000
  let input_count = compact_size(1)
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  let output_count = compact_size(2)
  let value1 = <<1_100_000_000_000_000:little-size(64)>>
  let value2 = <<1_100_000_000_000_000:little-size(64)>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    input_count:bits,
    input:bits,
    output_count:bits,
    value1:bits,
    script_pubkey_length:bits,
    value2:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(parsed_tx) = transaction.decode(tx_bytes)

  assert transaction.validate_context_free_consensus(parsed_tx)
    == Error([TotalOutputValueOutOfRange(1, 2_200_000_000_000_000)])
}

pub fn validate_context_free_consensus_rejects_coinbase_with_multiple_inputs_test() {
  // Build a transaction with 1 coinbase input and 1 regular input
  // Coinbase transactions must have exactly 1 input, so this should fail
  let input_count = compact_size(2)

  // Coinbase input (prev_txid=all zeros, vout=0xFFFFFFFF)
  let coinbase_input = build_input(<<0:size(256)>>, 0xFFFFFFFF, <<0, 0>>, 0)

  // Regular input (non-zero prev_txid)
  let regular_input = build_input(<<1:size(256)>>, 0, <<>>, 0)

  let output_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    input_count:bits,
    coinbase_input:bits,
    regular_input:bits,
    output_count:bits,
    value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(parsed_tx) = transaction.decode(tx_bytes)

  assert transaction.validate_context_free_consensus(parsed_tx)
    == Error([CoinbaseWithMultipleInputs])
}

pub fn validate_context_free_consensus_rejects_multiple_coinbase_inputs_test() {
  // Build a transaction with 2 coinbase inputs
  // This should be rejected as coinbase transactions must have exactly 1 input
  let input_count = compact_size(2)

  // Two coinbase inputs (both have prev_txid=all zeros, vout=0xFFFFFFFF)
  let coinbase_input1 = build_input(<<0:size(256)>>, 0xFFFFFFFF, <<0, 0>>, 0)
  let coinbase_input2 = build_input(<<0:size(256)>>, 0xFFFFFFFF, <<0, 0>>, 0)

  let output_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    input_count:bits,
    coinbase_input1:bits,
    coinbase_input2:bits,
    output_count:bits,
    value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(parsed_tx) = transaction.decode(tx_bytes)

  assert transaction.validate_context_free_consensus(parsed_tx)
    == Error([CoinbaseWithMultipleInputs])
}

pub fn validate_context_free_consensus_rejects_coinbase_with_scriptsig_too_short_test() {
  // Build a coinbase transaction with scriptSig of 1 byte (minimum is 2 bytes)
  let input_count = compact_size(1)
  // Coinbase input with 1-byte scriptSig (too short)
  let coinbase_input = build_input(<<0:size(256)>>, 0xFFFFFFFF, <<0x01>>, 0)
  let output_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    input_count:bits,
    coinbase_input:bits,
    output_count:bits,
    value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(parsed_tx) = transaction.decode(tx_bytes)

  assert transaction.validate_context_free_consensus(parsed_tx)
    == Error([InvalidCoinbaseScriptSigLength])
}

pub fn validate_context_free_consensus_rejects_coinbase_with_scriptsig_too_long_test() {
  let input_count = compact_size(1)

  // Coinbase input with 101-byte (808-bit) scriptSig
  let coinbase_input =
    build_input(<<0:size(256)>>, 0xFFFFFFFF, <<0:size(808)>>, 0)

  let output_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    input_count:bits,
    coinbase_input:bits,
    output_count:bits,
    value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(parsed_tx) = transaction.decode(tx_bytes)

  assert transaction.validate_context_free_consensus(parsed_tx)
    == Error([InvalidCoinbaseScriptSigLength])
}

pub fn validate_context_free_consensus_accepts_coinbase_with_scriptsig_min_length_test() {
  let input_count = compact_size(1)

  // Coinbase input with 2-byte scriptSig
  let coinbase_input =
    build_input(<<0:size(256)>>, 0xFFFFFFFF, <<0:size(16)>>, 0)

  let output_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    input_count:bits,
    coinbase_input:bits,
    output_count:bits,
    value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(parsed_tx) = transaction.decode(tx_bytes)
  let assert Ok(_) = transaction.validate_context_free_consensus(parsed_tx)
}

pub fn validate_context_free_consensus_accepts_coinbase_with_scriptsig_max_length_test() {
  let input_count = compact_size(1)

  // Coinbase input with 100-byte scriptSig
  let coinbase_input =
    build_input(<<0:size(256)>>, 0xFFFFFFFF, <<0:size(800)>>, 0)

  let output_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    input_count:bits,
    coinbase_input:bits,
    output_count:bits,
    value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(parsed_tx) = transaction.decode(tx_bytes)
  let assert Ok(_) = transaction.validate_context_free_consensus(parsed_tx)
}

pub fn validate_context_free_consensus_returns_multiple_errors_test() {
  // Build a transaction that violates multiple consensus rules:
  // 1. Coinbase with multiple inputs (should trigger CoinbaseWithMultipleInputs)
  // 2. Negative output value (should trigger OutputValueOutOfRange)
  let input_count = compact_size(2)

  // Coinbase input + regular input (violates "exactly one input" rule)
  let coinbase_input1 = build_input(<<0:size(256)>>, 0xFFFFFFFF, <<0, 0>>, 0)
  let regular_input = build_input(<<1:size(256)>>, 0, <<0, 0>>, 0)

  let output_count = compact_size(1)
  // Negative value: 0xFFFFFFFFFFFFFFFF = -1 as signed int64
  let negative_value = <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    input_count:bits,
    coinbase_input1:bits,
    regular_input:bits,
    output_count:bits,
    negative_value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(parsed_tx) = transaction.decode(tx_bytes)

  // Validate consensus rules - should fail with multiple errors
  let assert Error(errors) =
    transaction.validate_context_free_consensus(parsed_tx)

  // Should contain both CoinbaseWithMultipleInputs and OutputValueOutOfRange
  assert list.contains(errors, CoinbaseWithMultipleInputs)
  assert list.contains(errors, OutputValueOutOfRange(0, -1))
  assert list.length(errors) == 2
}

pub fn validate_context_free_consensus_rejects_tx_with_duplicate_inputs_test() {
  // Two inputs referencing the same previous output (txid + vout)
  let input_count = compact_size(2)
  let shared_txid = repeat_byte(0xAB, 32)
  let input0 = build_input(shared_txid, 0, <<>>, 0xFFFFFFFF)
  let input1 = build_input(shared_txid, 0, <<>>, 0xFFFFFFFF)
  let output_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    input_count:bits,
    input0:bits,
    input1:bits,
    output_count:bits,
    value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(parsed_tx) = transaction.decode(tx_bytes)
  let assert [in0, ..] = transaction.get_inputs(parsed_tx)
  let duplicate_outpoint = transaction.get_input_outpoint(in0)

  assert transaction.validate_context_free_consensus(parsed_tx)
    == Error([DuplicateInput(duplicate_outpoint, 0, 1)])
}

pub fn validate_context_free_consensus_rejects_duplicate_input_at_non_adjacent_indices_test() {
  // Inputs at index 0 and 2 share the same previous output; input 1 is distinct
  let input_count = compact_size(3)
  let shared_txid = repeat_byte(0xAB, 32)
  let other_txid = repeat_byte(0xCD, 32)
  let input0 = build_input(shared_txid, 0, <<>>, 0xFFFFFFFF)
  let input1 = build_input(other_txid, 1, <<>>, 0xFFFFFFFF)
  let input2 = build_input(shared_txid, 0, <<>>, 0xFFFFFFFF)
  let output_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    input_count:bits,
    input0:bits,
    input1:bits,
    input2:bits,
    output_count:bits,
    value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(parsed_tx) = transaction.decode(tx_bytes)
  let assert [in0, ..] = transaction.get_inputs(parsed_tx)
  let duplicate_outpoint = transaction.get_input_outpoint(in0)

  assert transaction.validate_context_free_consensus(parsed_tx)
    == Error([DuplicateInput(duplicate_outpoint, 0, 2)])
}

pub fn validate_context_free_consensus_accepts_inputs_with_same_txid_but_different_vout_test() {
  // Same txid but different output indices are distinct outpoints — not a duplicate
  let input_count = compact_size(2)
  let txid = repeat_byte(0xAB, 32)
  let input0 = build_input(txid, 0, <<>>, 0xFFFFFFFF)
  let input1 = build_input(txid, 1, <<>>, 0xFFFFFFFF)
  let output_count = compact_size(1)
  let value = <<1000:little-size(64)>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    input_count:bits,
    input0:bits,
    input1:bits,
    output_count:bits,
    value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(parsed_tx) = transaction.decode(tx_bytes)
  let assert Ok(_) = transaction.validate_context_free_consensus(parsed_tx)
}

pub fn validate_context_free_consensus_duplicate_input_reported_alongside_other_errors_test() {
  // Duplicate inputs combined with a negative output value: both errors reported
  let input_count = compact_size(2)
  let shared_txid = repeat_byte(0xAB, 32)
  let input0 = build_input(shared_txid, 0, <<>>, 0xFFFFFFFF)
  let input1 = build_input(shared_txid, 0, <<>>, 0xFFFFFFFF)
  let output_count = compact_size(1)
  // -1 as signed int64
  let negative_value = <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>
  let script_pubkey_length = compact_size(0)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    input_count:bits,
    input0:bits,
    input1:bits,
    output_count:bits,
    negative_value:bits,
    script_pubkey_length:bits,
    lock_time:bits,
  >>

  let assert Ok(parsed_tx) = transaction.decode(tx_bytes)
  let assert [in0, ..] = transaction.get_inputs(parsed_tx)
  let duplicate_outpoint = transaction.get_input_outpoint(in0)

  let assert Error(errors) =
    transaction.validate_context_free_consensus(parsed_tx)
  assert list.contains(errors, OutputValueOutOfRange(0, -1))
  assert list.contains(errors, DuplicateInput(duplicate_outpoint, 0, 1))
  assert list.length(errors) == 2
}

// ============================================================================
// decode -> serialization
// ============================================================================

pub fn round_trip_legacy_tx_wire_bytes_match_original_hex_test() {
  // The bytes produced by to_wire_bytes must exactly match the original
  // hex encoding — no byte dropped or added.
  let assert Ok(original_bytes) = bit_array.base16_decode(legacy_v1_tx)
  let assert Ok(parsed_tx) = transaction.decode(original_bytes)

  assert transaction.to_stripped_bytes(parsed_tx) == original_bytes
  assert transaction.to_wire_bytes(parsed_tx) == original_bytes
}

pub fn round_trip_segwit_tx_wire_bytes_match_original_hex_test() {
  let assert Ok(original_bytes) = bit_array.base16_decode(segwit_v1_tx)
  let assert Ok(parsed_tx) = transaction.decode(original_bytes)

  assert transaction.to_wire_bytes(parsed_tx) == original_bytes
}

pub fn hashing_and_serialization_accept_context_free_invalid_segwit_tx_test() {
  let input = build_input(repeat_byte(1, 32), 0, <<>>, 0xFFFFFFFF)
  let witness_item = <<0x42>>
  let witness_stack = <<
    compact_size(1):bits,
    compact_size(bit_array.byte_size(witness_item)):bits,
    witness_item:bits,
  >>
  let wire_bytes = build_segwit_tx([input], [], [witness_stack])
  let stripped_bytes = <<
    version1:bits,
    compact_size(1):bits,
    input:bits,
    compact_size(0):bits,
    0:little-size(32),
  >>

  let assert Ok(parsed_tx) = transaction.decode(wire_bytes)
  assert transaction.validate_context_free_consensus(parsed_tx)
    == Error([NoOutputs])

  assert transaction.to_stripped_bytes(parsed_tx) == stripped_bytes
  assert transaction.to_wire_bytes(parsed_tx) == wire_bytes

  let expected_txid =
    stripped_bytes
    |> crypto.hash(Sha256, _)
    |> crypto.hash(Sha256, _)

  let expected_wtxid =
    wire_bytes
    |> crypto.hash(Sha256, _)
    |> crypto.hash(Sha256, _)

  assert transaction.compute_txid(parsed_tx) == expected_txid
  assert transaction.compute_wtxid(parsed_tx) == expected_wtxid
}

// ============================================================================
// has_coinbase_shape
// ============================================================================

pub fn has_coinbase_shape_regular_transaction_returns_false_test() {
  // Regular (non-coinbase) transaction with valid inputs and outputs
  let input_count = compact_size(1)
  let regular_input =
    build_input(repeat_byte(1, 32), 42, <<0, 1, 2>>, 0xFFFFFFFE)
  let output_count = compact_size(1)
  let output = build_output(<<50_000_000:little-size(64)>>, <<>>)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    input_count:bits,
    regular_input:bits,
    output_count:bits,
    output:bits,
    lock_time:bits,
  >>

  let assert Ok(parsed_tx) = transaction.decode(tx_bytes)
  let assert Ok(validated_tx) =
    transaction.validate_context_free_consensus(parsed_tx)
  assert !transaction.has_coinbase_shape(validated_tx)
}

pub fn has_coinbase_shape_coinbase_transaction_test() {
  // Valid coinbase: exactly 1 input with coinbase marker and 50-byte scriptSig
  let input_count = compact_size(1)
  let coinbase_input =
    build_input(<<0:size(256)>>, 0xFFFFFFFF, <<0:size(400)>>, 0)
  let output_count = compact_size(1)
  let output = build_output(<<5_000_000_000:little-size(64)>>, <<>>)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
    input_count:bits,
    coinbase_input:bits,
    output_count:bits,
    output:bits,
    lock_time:bits,
  >>

  let assert Ok(parsed_tx) = transaction.decode(tx_bytes)
  let assert Ok(validated_tx) =
    transaction.validate_context_free_consensus(parsed_tx)
  assert transaction.has_coinbase_shape(validated_tx)
}

// ============================================================================
// compute_txid, compute_wtxid
// ============================================================================

pub fn compute_txid_legacy_v1_tx_known_vector_test() {
  compare_compute_txid_against_known_vector(
    legacy_v1_tx,
    "619122b4146f5edbf49f2e0aaa1380f2b7668cf9e9fc66fd788e791bf954d6da",
  )
}

pub fn compute_txid_legacy_v2_tx_known_vector_test() {
  compare_compute_txid_against_known_vector(
    legacy_v2_tx,
    "05d350c8a65010bbe9d220b2accd7601b4c6541b7c6d7f5ad451efbcc07f8d66",
  )
}

pub fn compute_txid_segwit_v1_tx_known_vector_test() {
  compare_compute_txid_against_known_vector(
    segwit_v1_tx,
    "632ac65a62740afbb69fdaee8da8cf12ed53e999b76f2713820937fe2ca2a7ff",
  )
}

fn compare_compute_txid_against_known_vector(
  tx_hex: String,
  known_txid: String,
) -> Nil {
  let assert Ok(tx) = transaction.decode_hex(tx_hex)

  let wire_txid = transaction.compute_txid(tx)
  assert get_display_hex(wire_txid) == known_txid
}

pub fn compute_txid_matches_manual_dsha256_test() {
  // Construct a known minimal legacy transaction from scratch
  let input_count = compact_size(1)
  let input = build_input(repeat_byte(1, 32), 0, <<>>, 0xFFFFFFFF)
  let output_count = compact_size(1)
  let output = build_output(<<1000:little-size(64)>>, <<>>)
  let lock_time = <<0:little-size(32)>>

  let tx_bytes = <<
    version1:bits,
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

  let assert Ok(tx) = transaction.decode(tx_bytes)
  let txid = transaction.compute_txid(tx)

  assert txid == expected_txid
}

pub fn compute_wtxid_matches_manual_dsha256_test() {
  // Construct a known minimal SegWit transaction from scratch
  let input = build_input(repeat_byte(1, 32), 0, <<>>, 0xFFFFFFFF)
  let output = build_output(<<1000:little-size(64)>>, <<>>)

  // Single-item witness stack with one byte of data
  let witness_item = <<0x42>>
  let witness_item_length = bit_array.byte_size(witness_item)
  let witness_stack = <<
    compact_size(1):bits,
    compact_size(witness_item_length):bits,
    witness_item:bits,
  >>

  let tx_bytes = build_segwit_tx([input], [output], [witness_stack])

  // wtxid is dsha256 of the full serialized bytes (including marker, flag, witness)
  let expected_wtxid =
    tx_bytes
    |> crypto.hash(Sha256, _)
    |> crypto.hash(Sha256, _)

  let assert Ok(tx) = transaction.decode(tx_bytes)
  let wtxid = transaction.compute_wtxid(tx)

  assert wtxid == expected_wtxid
}

pub fn compute_wtxid_tx_known_vector_test() {
  let tx_hex =
    "01000000000101438afdb24e414d54cc4a17a95f3d40be90d23dfeeb07a48e9e782178efddd8890100000000fdffffff020db9a60000000000160014b549d227c9edd758288112fe3573c1f85240166880a81201000000001976a914ae28f233464e6da03c052155119a413d13f3380188ac024730440220200254b765f25126334b8de16ee4badf57315c047243942340c16cffd9b11196022074a9476633f093f229456ad904a9d97e26c271fc4f01d0501dec008e4aae71c2012102c37a3c5b21a5991d3d7b1e203be195be07104a1a19e5c2ed82329a56b431213000000000"

  compare_compute_wtxid_against_known_vector(
    tx_hex,
    "f12d56f2234e809129dbf59392961bbe7a89b6250651f6aea7852cc00ced63ff",
  )
}

fn compare_compute_wtxid_against_known_vector(
  tx_hex: String,
  known_txid: String,
) -> Nil {
  let assert Ok(tx) = transaction.decode_hex(tx_hex)

  let wire_txid = transaction.compute_wtxid(tx)
  assert get_display_hex(wire_txid) == known_txid
}

fn get_display_hex(bytes: BitArray) -> String {
  bytes
  |> reverse_bytes
  |> bit_array.base16_encode
  |> string.lowercase
}

pub fn compute_txid_differs_from_wtxid_for_segwit_test() {
  let assert Ok(tx) = transaction.decode_hex(segwit_v1_tx)

  let txid = transaction.compute_txid(tx)
  let wtxid = transaction.compute_wtxid(tx)

  assert txid != wtxid
}

pub fn compute_txid_equals_compute_wtxid_for_legacy_tx_test() {
  let assert Ok(tx) = transaction.decode_hex(legacy_v1_tx)

  let txid = transaction.compute_txid(tx)
  let wtxid = transaction.compute_wtxid(tx)

  assert txid == wtxid
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
  let script_length = compact_size(bit_array.byte_size(script_sig))
  let seq_bytes = <<sequence:little-size(32)>>

  <<
    prev_txid:bits,
    vout_bytes:bits,
    script_length:bits,
    script_sig:bits,
    seq_bytes:bits,
  >>
}

/// Build a minimal valid input (for use in output tests)
fn build_minimal_input() -> BitArray {
  let input_count = compact_size(1)
  let input = build_input(<<0:size(256)>>, 0, <<>>, 0)
  <<input_count:bits, input:bits>>
}

fn decode_single_input_outpoint(prev_txid: BitArray, vout: Int) {
  let input = build_input(prev_txid, vout, <<>>, 0)
  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    transaction.decode(<<
      version1:bits,
      compact_size(1):bits,
      input:bits,
      build_minimal_output():bits,
      lock_time:bits,
    >>)

  let assert [first_input] = transaction.get_inputs(tx)
  transaction.get_input_outpoint(first_input)
}

/// Build an output with specific values
fn build_output(value: BitArray, script_pubkey: BitArray) -> BitArray {
  let script_length =
    script_pubkey
    |> bit_array.byte_size
    |> compact_size

  <<
    value:bits,
    script_length:bits,
    script_pubkey:bits,
  >>
}

/// Build a minimal valid output section with output_count, value, and empty scriptPubKey
fn build_minimal_output() -> BitArray {
  let output_count = compact_size(1)
  let value = <<0:little-size(64)>>
  let script_pubkey_length = compact_size(0)

  <<
    output_count:bits,
    value:bits,
    script_pubkey_length:bits,
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
  let input_count = compact_size(list.length(inputs))
  let output_count = compact_size(list.length(outputs))
  let lock_time = <<0:little-size(32)>>

  <<
    version1:bits,
    marker:bits,
    flag:bits,
    input_count:bits,
    bit_array.concat(inputs):bits,
    output_count:bits,
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

fn reverse_bytes(bits: BitArray) -> BitArray {
  do_reverse_bytes(bits, <<>>)
}

fn do_reverse_bytes(bits: BitArray, acc: BitArray) -> BitArray {
  case bits {
    <<>> -> acc
    <<byte, rest:bits>> -> do_reverse_bytes(rest, <<byte, acc:bits>>)
    _ -> panic as "input is not byte-aligned"
  }
}

/// Build and decode a minimal transaction containing only the given
/// `script_pubkey_bytes`, returning a `ScriptBytes(OutputScript)` value
/// ready to pass to `classify_output_script`.
fn decode_script_pubkey(
  script_pubkey_bytes: BitArray,
) -> transaction.ScriptBytes(transaction.OutputScript) {
  let output = build_output(<<0:little-size(64)>>, script_pubkey_bytes)
  let lock_time = <<0:little-size(32)>>
  let assert Ok(tx) =
    transaction.decode(<<
      version1:bits,
      build_minimal_input():bits,
      compact_size(1):bits,
      output:bits,
      lock_time:bits,
    >>)
  let assert [first_output] = transaction.get_outputs(tx)
  transaction.get_output_script_pubkey(first_output)
}

// ============================================================================
// Policy Builder Helper Functions
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
