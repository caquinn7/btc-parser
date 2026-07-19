import btc_parser/block.{
  DecodeFailed, InsufficientBytes, IntegerOutOfRange, InvalidHex, MaxBlockSize,
  MaxTransactionCount, NonMinimalCompactSize, PolicyLimitExceeded, TrailingBytes,
  TransactionDecodeFailed, UnexpectedEof,
}
import btc_parser/transaction
import gleam/bit_array
import gleam/crypto.{Sha256}
import gleam/list
import support/bitcoin_wire.{compact_size}
import support/target
import support/transaction_wire.{
  assemble_segwit_transaction_bytes, build_input_bytes,
  build_minimal_legacy_transaction_bytes, build_minimal_segwit_transaction_bytes,
  build_output_bytes,
}

// ============================================================================
// Header and empty-block deserialization success
// ============================================================================

pub fn deserialize_accepts_header_only_block_with_zero_transactions_test() {
  let bytes =
    build_header_only_block(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      1_234_567_890,
      0x1D00FFFF,
      2_083_236_893,
    )

  let assert Ok(block) = block.deserialize(bytes)
  assert block.get_transaction_count(block) == 0
  assert block.get_transactions(block) == []
}

pub fn deserialize_preserves_signed_header_version_test() {
  let bytes =
    build_header_only_block(-1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)

  let assert Ok(block) = block.deserialize(bytes)

  assert block
    |> block.get_header
    |> block.get_header_version
    == -1
}

pub fn deserialize_preserves_header_hashes_in_wire_order_test() {
  let previous_block_hash = <<0x01, 0:size(240), 0x02>>
  let merkle_root = <<0x03, 0:size(240), 0x04>>
  let bytes =
    build_header_only_block(1, previous_block_hash, merkle_root, 0, 0, 0)

  let assert Ok(block) = block.deserialize(bytes)
  let header = block.get_header(block)

  assert block.get_header_previous_block_hash(header) == previous_block_hash
  assert block.get_header_merkle_root(header) == merkle_root
}

pub fn deserialize_preserves_unsigned_header_timestamp_target_and_nonce_test() {
  let timestamp = 2_147_483_648
  let target = 4_294_967_295
  let nonce = 4_026_531_840
  let bytes =
    build_header_only_block(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      timestamp,
      target,
      nonce,
    )

  let assert Ok(block) = block.deserialize(bytes)
  let header = block.get_header(block)

  assert block.get_header_timestamp(header) == timestamp
  assert block.get_header_target(header) == target
  assert block.get_header_nonce(header) == nonce
}

// ============================================================================
// Transaction deserialization success
// ============================================================================

pub fn deserialize_accepts_block_with_one_legacy_transaction_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  let bytes = build_block(header, [build_minimal_legacy_transaction_bytes(1)])

  let assert Ok(block) = block.deserialize(bytes)
  let assert [tx] = block.get_transactions(block)

  assert block.get_transaction_count(block) == 1
  assert !transaction.is_segwit(tx)
}

pub fn deserialize_accepts_block_with_one_segwit_transaction_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  let bytes = build_block(header, [build_minimal_segwit_transaction_bytes()])

  let assert Ok(block) = block.deserialize(bytes)
  let assert [tx] = block.get_transactions(block)

  assert block.get_transaction_count(block) == 1
  assert transaction.is_segwit(tx)
}

pub fn deserialize_preserves_multiple_transactions_in_wire_order_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  let bytes =
    build_block(header, [
      build_minimal_legacy_transaction_bytes(1),
      build_minimal_legacy_transaction_bytes(2),
    ])

  let assert Ok(block) = block.deserialize(bytes)
  let assert [first_tx, second_tx] = block.get_transactions(block)

  assert block.get_transaction_count(block) == 2
  assert transaction.get_version(first_tx) == 1
  assert transaction.get_version(second_tx) == 2
}

pub fn deserialize_preserves_multibyte_compact_size_transaction_count_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  let tx_count = 253
  let txs = list.repeat(build_minimal_legacy_transaction_bytes(1), tx_count)
  let bytes = build_block(header, txs)

  let assert Ok(block) = block.deserialize(bytes)

  assert block.get_transaction_count(block) == tx_count
  assert list.length(block.get_transactions(block)) == tx_count
}

// ============================================================================
// Decode policy configuration
// ============================================================================

pub fn default_decode_policy_returns_expected_values_test() {
  let policy = block.default_decode_policy()

  assert block.decode_policy_max_block_size(policy) == 4_000_000
  assert block.decode_policy_max_tx_count(policy) == 20_000
}

pub fn decode_policy_builder_overrides_default_limits_test() {
  let policy =
    block.default_decode_policy()
    |> block.decode_policy_with_max_block_size(8_000_000)
    |> block.decode_policy_with_max_tx_count(40_000)

  assert block.decode_policy_max_block_size(policy) == 8_000_000
  assert block.decode_policy_max_tx_count(policy) == 40_000
}

// ============================================================================
// Decode policy enforcement
// ============================================================================

pub fn deserialize_with_policy_rejects_bytes_exceeding_max_block_size_test() {
  let bytes =
    build_header_only_block(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  let block_size = bit_array.byte_size(bytes)

  let assert Error(error) =
    block.deserialize_with_policy(
      bytes,
      policy_with_max_block_size(block_size - 1),
    )

  assert check_block_decode_error(error, 0, "block")
    == PolicyLimitExceeded(MaxBlockSize, block_size, block_size - 1)
}

pub fn deserialize_with_policy_accepts_bytes_at_max_block_size_test() {
  let bytes =
    build_header_only_block(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)

  let policy = policy_with_max_block_size(bit_array.byte_size(bytes))
  let assert Ok(block) = block.deserialize_with_policy(bytes, policy)

  assert block.get_transactions(block) == []
}

pub fn deserialize_with_policy_rejects_tx_count_exceeding_max_tx_count_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  let bytes =
    build_block(header, [
      build_minimal_legacy_transaction_bytes(1),
      build_minimal_legacy_transaction_bytes(2),
    ])

  let assert Error(error) =
    block.deserialize_with_policy(bytes, policy_with_max_tx_count(1))

  assert check_block_decode_error(error, 80, "block.transactions.count")
    == PolicyLimitExceeded(MaxTransactionCount, 2, 1)
}

pub fn deserialize_with_policy_prioritizes_structural_tx_count_error_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)

  // The count exceeds the policy, but no transaction bytes remain, so the
  // structural impossibility must be reported before the policy violation.
  let assert Error(error) =
    block.deserialize_with_policy(
      <<header:bits, 2>>,
      policy_with_max_tx_count(1),
    )

  assert check_block_decode_error(error, 80, "block.transactions.count")
    == InsufficientBytes(claimed: 1, remaining: 0)
}

pub fn deserialize_with_policy_accepts_tx_count_at_max_tx_count_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  let bytes =
    build_block(header, [
      build_minimal_legacy_transaction_bytes(1),
      build_minimal_legacy_transaction_bytes(2),
    ])

  let assert Ok(block) =
    block.deserialize_with_policy(bytes, policy_with_max_tx_count(2))

  assert list.length(block.get_transactions(block)) == 2
}

pub fn deserialize_accepts_default_max_tx_count_without_stack_overflow_test() {
  let policy = block.default_decode_policy()
  let tx_count = block.decode_policy_max_tx_count(policy)
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  let tx = build_smallest_structurally_decodable_transaction()
  let bytes = build_block(header, list.repeat(tx, tx_count))

  let tx_size = bit_array.byte_size(tx)
  let expected_block_size =
    bit_array.byte_size(header)
    + bit_array.byte_size(compact_size(tx_count))
    + tx_count
    * tx_size

  assert tx_size == 10
  assert bit_array.byte_size(bytes) == expected_block_size
  assert expected_block_size <= block.decode_policy_max_block_size(policy)

  let assert Ok(block) = block.deserialize(bytes)

  assert block.get_transaction_count(block) == tx_count
  assert list.length(block.get_transactions(block)) == tx_count
}

// ============================================================================
// Input shape errors
// ============================================================================

pub fn deserialize_rejects_non_byte_aligned_input_test() {
  let aligned =
    build_header_only_block(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  let unaligned = <<aligned:bits, 1:size(1)>>

  let assert Error(error) = block.deserialize(unaligned)

  assert check_block_decode_error(error, 0, "block.header.version")
    == UnexpectedEof(
      bytes_needed: 4,
      remaining: bit_array.byte_size(aligned) + 1,
    )
}

// ============================================================================
// Header errors
// ============================================================================

pub fn deserialize_errors_when_header_version_is_truncated_test() {
  let assert Error(error) = block.deserialize(<<0x01, 0x02, 0x03>>)

  assert check_block_decode_error(error, 0, "block.header.version")
    == UnexpectedEof(bytes_needed: 4, remaining: 3)
}

pub fn deserialize_errors_when_previous_block_hash_is_truncated_test() {
  let assert Error(error) = block.deserialize(<<1:32-little, 0:size(248)>>)

  assert check_block_decode_error(error, 4, "block.header.previous_block_hash")
    == UnexpectedEof(bytes_needed: 32, remaining: 31)
}

pub fn deserialize_errors_when_merkle_root_is_truncated_test() {
  let assert Error(error) =
    block.deserialize(<<1:32-little, 0:size(256), 0:size(248)>>)

  assert check_block_decode_error(error, 36, "block.header.merkle_root")
    == UnexpectedEof(bytes_needed: 32, remaining: 31)
}

pub fn deserialize_errors_when_header_timestamp_is_truncated_test() {
  let assert Error(error) =
    block.deserialize(<<1:32-little, 0:size(256), 0:size(256), 0:size(24)>>)

  assert check_block_decode_error(error, 68, "block.header.timestamp")
    == UnexpectedEof(bytes_needed: 4, remaining: 3)
}

pub fn deserialize_errors_when_header_target_is_truncated_test() {
  let assert Error(error) =
    block.deserialize(<<
      1:32-little,
      0:size(256),
      0:size(256),
      0:32-little,
      0:size(24),
    >>)

  assert check_block_decode_error(error, 72, "block.header.target")
    == UnexpectedEof(bytes_needed: 4, remaining: 3)
}

pub fn deserialize_errors_when_header_nonce_is_truncated_test() {
  let assert Error(error) =
    block.deserialize(<<
      1:32-little,
      0:size(256),
      0:size(256),
      0:32-little,
      0:32-little,
      0:size(24),
    >>)

  assert check_block_decode_error(error, 76, "block.header.nonce")
    == UnexpectedEof(bytes_needed: 4, remaining: 3)
}

// ============================================================================
// Transaction-count errors
// ============================================================================

pub fn deserialize_errors_when_transaction_count_is_missing_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)

  let assert Error(error) = block.deserialize(header)

  assert check_block_decode_error(error, 80, "block.transactions.count")
    == UnexpectedEof(bytes_needed: 1, remaining: 0)
}

pub fn deserialize_errors_when_compact_size_transaction_count_is_truncated_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)

  let assert Error(error) = block.deserialize(<<header:bits, 0xFD>>)

  assert check_block_decode_error(error, 80, "block.transactions.count")
    == UnexpectedEof(bytes_needed: 2, remaining: 0)
}

pub fn deserialize_rejects_non_minimal_compact_size_transaction_count_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)

  let assert Error(error) = block.deserialize(<<header:bits, 0xFD, 0x01, 0x00>>)

  assert check_block_decode_error(error, 80, "block.transactions.count")
    == NonMinimalCompactSize(encoded_size: 3, value: 1)
}

pub fn deserialize_rejects_transaction_count_outside_the_runtime_int_range_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  // 2^53, one greater than JavaScript's largest exactly representable Int.
  let count_above_max_safe_js_int = <<0, 0, 0, 0, 0, 0, 0x20, 0>>
  let bytes = <<header:bits, 0xFF, count_above_max_safe_js_int:bits>>

  case target.is_javascript() {
    True -> {
      let assert Error(decode_err) = block.deserialize(bytes)

      assert check_block_decode_error(
          decode_err,
          80,
          "block.transactions.count",
        )
        == IntegerOutOfRange("9007199254740992")
    }

    False -> Nil
  }
}

pub fn deserialize_rejects_transaction_count_that_cannot_fit_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  let tx_count = 1

  let assert Error(error) = block.deserialize(<<header:bits, tx_count>>)

  assert check_block_decode_error(error, 80, "block.transactions.count")
    == InsufficientBytes(claimed: 1, remaining: 0)
}

// ============================================================================
// Contained transaction errors
// ============================================================================

pub fn deserialize_offsets_contained_transaction_errors_from_the_block_start_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  let tx_count = 1
  let incomplete_tx = <<1:32-little, 1, 0:size(40)>>

  let assert Error(error) =
    block.deserialize(<<header:bits, tx_count, incomplete_tx:bits>>)

  // `85` is block-relative (80-byte header + one-byte count + four-byte
  // transaction version); `4` remains relative to the transaction start.
  let assert TransactionDecodeFailed(tx_decode_err) =
    check_block_decode_error(error, 85, "block.transactions[0]")

  assert check_transaction_decode_error(
      tx_decode_err,
      4,
      "transaction.inputs.count",
    )
    == transaction.InsufficientBytes(claimed: 6, remaining: 5)
}

pub fn deserialize_reports_error_in_second_transaction_with_transaction_index_in_path_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  let incomplete_second_tx = <<1:32-little>>
  let bytes =
    build_block(header, [
      build_minimal_legacy_transaction_bytes(1),
      incomplete_second_tx,
    ])

  let assert Error(error) = block.deserialize(bytes)

  let assert TransactionDecodeFailed(tx_decode_err) =
    check_block_decode_error(error, 145, "block.transactions[1]")

  assert check_transaction_decode_error(
      tx_decode_err,
      4,
      "transaction.inputs.count",
    )
    == transaction.UnexpectedEof(bytes_needed: 1, remaining: 0)
}

pub fn deserialize_wraps_contained_transaction_policy_error_with_block_offset_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  let oversized_script_sig = <<0:size({ 10_001 * 8 })>>
  let oversized_tx = <<
    1:32-little,
    1,
    0:size(256),
    0:32-little,
    compact_size(10_001):bits,
    oversized_script_sig:bits,
    0:32-little,
    0,
    0:32-little,
  >>

  let assert Error(error) =
    block.deserialize(build_block(header, [oversized_tx]))

  let assert TransactionDecodeFailed(tx_decode_err) =
    check_block_decode_error(error, 122, "block.transactions[0]")

  assert check_transaction_decode_error(
      tx_decode_err,
      41,
      "transaction.inputs[0].script_sig.length",
    )
    == transaction.PolicyLimitExceeded(
      transaction.MaxScriptSize,
      10_001,
      10_000,
    )
}

// ============================================================================
// Block boundary
// ============================================================================

pub fn deserialize_rejects_trailing_bytes_after_a_complete_block_test() {
  let complete_block =
    build_header_only_block(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)

  let assert Error(error) = block.deserialize(<<complete_block:bits, 0x42>>)

  assert check_block_decode_error(error, 81, "block") == TrailingBytes(1)
}

// ============================================================================
// deserialize_hex
// ============================================================================

pub fn deserialize_hex_accepts_block_with_one_legacy_transaction_test() {
  let header =
    build_block_header(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      1_234_567_890,
      0x1D00FFFF,
      2_083_236_893,
    )
  let bytes = build_block(header, [build_minimal_legacy_transaction_bytes(1)])

  let assert Ok(block) =
    bytes
    |> bit_array.base16_encode
    |> block.deserialize_hex

  assert block
    |> block.get_header
    |> block.get_header_timestamp
    == 1_234_567_890

  let assert [tx] = block.get_transactions(block)
  assert transaction.get_version(tx) == 1
  assert !transaction.is_segwit(tx)
}

pub fn deserialize_hex_errors_on_odd_length_string_test() {
  assert block.deserialize_hex("0") == Error(InvalidHex)
}

pub fn deserialize_hex_errors_on_invalid_hex_characters_test() {
  assert block.deserialize_hex("0000zz") == Error(InvalidHex)
}

pub fn deserialize_hex_errors_on_string_with_whitespace_test() {
  assert block.deserialize_hex("00 00") == Error(InvalidHex)
}

pub fn deserialize_hex_wraps_block_decode_error_test() {
  let assert Error(DecodeFailed(error)) = block.deserialize_hex("")

  assert check_block_decode_error(error, 0, "block.header.version")
    == UnexpectedEof(bytes_needed: 4, remaining: 0)
}

// ============================================================================
// deserialize_hex_with_policy
// ============================================================================

pub fn deserialize_hex_with_policy_accepts_block_at_max_block_size_test() {
  let bytes =
    build_header_only_block(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)

  let policy = policy_with_max_block_size(bit_array.byte_size(bytes))
  let assert Ok(block) =
    bytes
    |> bit_array.base16_encode
    |> block.deserialize_hex_with_policy(policy)

  assert block.get_transactions(block) == []
}

pub fn deserialize_hex_with_policy_wraps_policy_limit_error_test() {
  let bytes =
    build_header_only_block(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  let block_size = bit_array.byte_size(bytes)

  let policy = policy_with_max_block_size(block_size - 1)
  let assert Error(DecodeFailed(error)) =
    bytes
    |> bit_array.base16_encode
    |> block.deserialize_hex_with_policy(policy)

  assert check_block_decode_error(error, 0, "block")
    == PolicyLimitExceeded(MaxBlockSize, block_size, block_size - 1)
}

// ============================================================================
// serialize_header
// ============================================================================

pub fn serialize_header_round_trips_parsed_header_bytes_test() {
  // The serializer must reproduce the exact 80-byte header accepted by the
  // deserializer.
  let header_bytes =
    build_block_header(
      2,
      <<0x01, 0:size(240), 0x02>>,
      <<0x03, 0:size(240), 0x04>>,
      1_234_567_890,
      0x1D00FFFF,
      2_083_236_893,
    )

  let assert Ok(block) = block.deserialize(build_block(header_bytes, []))

  assert block
    |> block.get_header
    |> block.serialize_header
    == header_bytes
}

pub fn serialize_header_encodes_signed_version_bit_pattern_test() {
  // Negative versions must retain their original signed 32-bit wire encoding.
  let block_bytes =
    build_header_only_block(-1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)

  let assert Ok(block) = block.deserialize(block_bytes)

  let serialized_header =
    block
    |> block.get_header
    |> block.serialize_header

  let assert <<0xFF, 0xFF, 0xFF, 0xFF, _:bytes>> = serialized_header
}

pub fn serialize_header_encodes_unsigned_u32_values_from_int_test() {
  // Unsigned values above the signed 32-bit range must encode as four little-endian bytes.
  let block_bytes =
    build_header_only_block(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0x80000000,
      0xFEDCBA98,
      0xFFFFFFFF,
    )
  let assert Ok(block) = block.deserialize(block_bytes)

  let serialized_header =
    block
    |> block.get_header
    |> block.serialize_header

  let assert <<
    _:bytes-size(68),
    0x00,
    0x00,
    0x00,
    0x80,
    0x98,
    0xBA,
    0xDC,
    0xFE,
    0xFF,
    0xFF,
    0xFF,
    0xFF,
  >> = serialized_header
}

// ============================================================================
// serialize
// ============================================================================

pub fn serialize_encodes_zero_transaction_count_without_payload_test() {
  // An empty transaction list must add only a CompactSize zero after the header.
  let block_bytes =
    build_header_only_block(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)

  let assert Ok(block) = block.deserialize(block_bytes)

  let assert <<_:bytes-size(80), 0>> = block.serialize(block)
}

pub fn serialize_preserves_transaction_wire_order_test() {
  // Block serialization must concatenate contained transactions without reordering them.
  let first_tx = build_minimal_legacy_transaction_bytes(1)
  let second_tx = build_minimal_legacy_transaction_bytes(2)
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  let assert Ok(block) =
    block.deserialize(build_block(header, [first_tx, second_tx]))

  let assert <<_:bytes-size(80), serialized_payload:bytes>> =
    block.serialize(block)

  assert serialized_payload == <<2, first_tx:bits, second_tx:bits>>
}

pub fn serialize_includes_segwit_witness_data_test() {
  // SegWit transactions must use their full wire form rather than stripped bytes.
  let input = build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)
  let output = build_output_bytes(<<0:little-size(64)>>, <<>>)
  let witness_stack = <<
    compact_size(1):bits,
    compact_size(3):bits,
    0xAA,
    0xBB,
    0xCC,
  >>
  let segwit_tx =
    assemble_segwit_transaction_bytes([input], [output], [witness_stack])
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  let assert Ok(block) = block.deserialize(build_block(header, [segwit_tx]))

  let assert <<_:bytes-size(80), 1, serialized_tx:bytes>> =
    block.serialize(block)

  assert serialized_tx == segwit_tx
}

pub fn serialize_encodes_multibyte_compact_size_transaction_count_test() {
  // The transaction count must use minimal CompactSize at the first multibyte boundary.
  let tx_count = 253
  let txs = list.repeat(build_minimal_legacy_transaction_bytes(1), tx_count)
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  let assert Ok(block) = block.deserialize(build_block(header, txs))

  let assert <<_:bytes-size(80), 0xFD, 0xFD, 0x00, _:bytes>> =
    block.serialize(block)
}

// ============================================================================
// compute_block_hash
// ============================================================================

pub fn compute_block_hash_matches_manual_dsha256_test() {
  // A block hash covers exactly the 80-byte header, excluding all transaction data.
  let header_bytes =
    build_block_header(
      2,
      <<0x01, 0:size(240), 0x02>>,
      <<0x03, 0:size(240), 0x04>>,
      1_234_567_890,
      0x1D00FFFF,
      2_083_236_893,
    )
  let tx = build_minimal_legacy_transaction_bytes(1)
  let assert Ok(block) = block.deserialize(build_block(header_bytes, [tx]))

  let expected_hash =
    header_bytes
    |> crypto.hash(Sha256, _)
    |> crypto.hash(Sha256, _)

  assert block.compute_block_hash(block) == expected_hash
}

// ============================================================================
// Helpers
// ============================================================================

fn build_header_only_block(
  version: Int,
  previous_block_hash: BitArray,
  merkle_root: BitArray,
  timestamp: Int,
  target: Int,
  nonce: Int,
) -> BitArray {
  build_block(
    build_block_header(
      version,
      previous_block_hash,
      merkle_root,
      timestamp,
      target,
      nonce,
    ),
    [],
  )
}

fn build_block_header(
  version: Int,
  previous_block_hash: BitArray,
  merkle_root: BitArray,
  timestamp: Int,
  target: Int,
  nonce: Int,
) -> BitArray {
  <<
    version:32-little,
    previous_block_hash:bits,
    merkle_root:bits,
    timestamp:32-little,
    target:32-little,
    nonce:32-little,
  >>
}

fn build_block(header: BitArray, txs: List(BitArray)) -> BitArray {
  <<
    header:bits,
    compact_size(list.length(txs)):bits,
    bit_array.concat(txs):bits,
  >>
}

fn build_smallest_structurally_decodable_transaction() -> BitArray {
  <<1:32-little, 0, 0, 0:32-little>>
}

fn check_block_decode_error(
  error: block.DecodeError,
  expected_offset: Int,
  expected_path: String,
) -> block.DecodeErrorKind {
  assert block.get_decode_error_offset(error) == expected_offset
  assert block.get_decode_error_path(error) == expected_path
  block.get_decode_error_kind(error)
}

fn check_transaction_decode_error(
  error: transaction.DecodeError,
  expected_offset: Int,
  expected_path: String,
) -> transaction.DecodeErrorKind {
  assert transaction.get_decode_error_offset(error) == expected_offset
  assert transaction.get_decode_error_path(error) == expected_path
  transaction.get_decode_error_kind(error)
}

fn policy_with_max_block_size(max_block_size: Int) {
  block.default_decode_policy()
  |> block.decode_policy_with_max_block_size(max_block_size)
}

fn policy_with_max_tx_count(max_tx_count: Int) {
  block.default_decode_policy()
  |> block.decode_policy_with_max_tx_count(max_tx_count)
}
