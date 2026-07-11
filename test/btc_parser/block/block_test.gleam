import btc_parser/block.{
  DecodeFailed, IntegerOutOfRange, InvalidHex, NonMinimalCompactSize,
  TrailingBytes, TransactionDecodeFailed, UnexpectedEof,
}
import btc_parser/transaction
import btc_parser/transaction_test.{check_transaction_decode_error}
import gleam/bit_array
import gleam/list
import support/bitcoin_wire.{compact_size}
import support/target

// ============================================================================
// Successful decoding
// ============================================================================

pub fn decode_accepts_header_only_block_with_zero_transactions_test() {
  let bytes =
    build_header_only_block(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      1_234_567_890,
      0x1D00FFFF,
      2_083_236_893,
    )

  let assert Ok(decoded_block) = block.decode(bytes)
  assert block.get_transactions(decoded_block) == []
}

pub fn decode_preserves_signed_header_version_test() {
  let bytes =
    build_header_only_block(-1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)

  let assert Ok(decoded_block) = block.decode(bytes)

  assert decoded_block
    |> block.get_header
    |> block.get_header_version
    == -1
}

pub fn decode_preserves_header_hashes_in_wire_order_test() {
  let previous_block_hash = <<0x01, 0:size(240), 0x02>>
  let merkle_root = <<0x03, 0:size(240), 0x04>>
  let bytes =
    build_header_only_block(1, previous_block_hash, merkle_root, 0, 0, 0)

  let assert Ok(decoded_block) = block.decode(bytes)
  let header = block.get_header(decoded_block)

  assert block.get_header_previous_block_hash(header) == previous_block_hash
  assert block.get_header_merkle_root(header) == merkle_root
}

pub fn decode_preserves_unsigned_header_timestamp_target_and_nonce_test() {
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

  let assert Ok(decoded_block) = block.decode(bytes)
  let header = block.get_header(decoded_block)

  assert block.get_header_timestamp(header) == timestamp
  assert block.get_header_target(header) == target
  assert block.get_header_nonce(header) == nonce
}

pub fn decode_accepts_block_with_one_legacy_transaction_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  let bytes = build_block(header, [build_minimal_legacy_transaction(1)])

  let assert Ok(decoded_block) = block.decode(bytes)
  let assert [decoded_tx] = block.get_transactions(decoded_block)

  assert !transaction.is_segwit(decoded_tx)
}

pub fn decode_accepts_block_with_one_segwit_transaction_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  let bytes = build_block(header, [build_minimal_segwit_transaction()])

  let assert Ok(decoded_block) = block.decode(bytes)
  let assert [decoded_tx] = block.get_transactions(decoded_block)

  assert transaction.is_segwit(decoded_tx)
}

pub fn decode_preserves_multiple_transactions_in_wire_order_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  let bytes =
    build_block(header, [
      build_minimal_legacy_transaction(1),
      build_minimal_legacy_transaction(2),
    ])

  let assert Ok(decoded_block) = block.decode(bytes)
  let assert [first_tx, second_tx] = block.get_transactions(decoded_block)

  assert transaction.get_version(first_tx) == 1
  assert transaction.get_version(second_tx) == 2
}

// ============================================================================
// Input and header errors
// ============================================================================

pub fn decode_rejects_non_byte_aligned_input_test() {
  let aligned =
    build_header_only_block(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  let unaligned = <<aligned:bits, 1:size(1)>>

  let assert Error(error) = block.decode(unaligned)

  assert check_block_decode_error(error, 0, "block.header.version")
    == UnexpectedEof(
      bytes_needed: 4,
      remaining: bit_array.byte_size(aligned) + 1,
    )
}

pub fn decode_errors_when_header_version_is_truncated_test() {
  let assert Error(error) = block.decode(<<0x01, 0x02, 0x03>>)

  assert check_block_decode_error(error, 0, "block.header.version")
    == UnexpectedEof(bytes_needed: 4, remaining: 3)
}

pub fn decode_errors_when_previous_block_hash_is_truncated_test() {
  let assert Error(error) = block.decode(<<1:32-little, 0:size(248)>>)

  assert check_block_decode_error(error, 4, "block.header.previous_block_hash")
    == UnexpectedEof(bytes_needed: 32, remaining: 31)
}

pub fn decode_errors_when_merkle_root_is_truncated_test() {
  let assert Error(error) =
    block.decode(<<1:32-little, 0:size(256), 0:size(248)>>)

  assert check_block_decode_error(error, 36, "block.header.merkle_root")
    == UnexpectedEof(bytes_needed: 32, remaining: 31)
}

pub fn decode_errors_when_header_timestamp_is_truncated_test() {
  let assert Error(error) =
    block.decode(<<1:32-little, 0:size(256), 0:size(256), 0:size(24)>>)

  assert check_block_decode_error(error, 68, "block.header.timestamp")
    == UnexpectedEof(bytes_needed: 4, remaining: 3)
}

pub fn decode_errors_when_header_target_is_truncated_test() {
  let assert Error(error) =
    block.decode(<<
      1:32-little,
      0:size(256),
      0:size(256),
      0:32-little,
      0:size(24),
    >>)

  assert check_block_decode_error(error, 72, "block.header.target")
    == UnexpectedEof(bytes_needed: 4, remaining: 3)
}

pub fn decode_errors_when_header_nonce_is_truncated_test() {
  let assert Error(error) =
    block.decode(<<
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

pub fn decode_errors_when_transaction_count_is_missing_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)

  let assert Error(error) = block.decode(header)

  assert check_block_decode_error(error, 80, "block.transactions.count")
    == UnexpectedEof(bytes_needed: 1, remaining: 0)
}

pub fn decode_errors_when_compact_size_transaction_count_is_truncated_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)

  let assert Error(error) = block.decode(<<header:bits, 0xFD>>)

  assert check_block_decode_error(error, 80, "block.transactions.count")
    == UnexpectedEof(bytes_needed: 2, remaining: 0)
}

pub fn decode_rejects_non_minimal_compact_size_transaction_count_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)

  let assert Error(error) = block.decode(<<header:bits, 0xFD, 0x01, 0x00>>)

  assert check_block_decode_error(error, 80, "block.transactions.count")
    == NonMinimalCompactSize(encoded_size: 3, value: 1)
}

pub fn decode_rejects_transaction_count_outside_the_runtime_int_range_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  // 2^53, one greater than JavaScript's largest exactly representable Int.
  let count_above_max_safe_js_int = <<0, 0, 0, 0, 0, 0, 0x20, 0>>
  let bytes = <<header:bits, 0xFF, count_above_max_safe_js_int:bits>>

  case target.is_javascript() {
    True -> {
      let assert Error(decode_err) = block.decode(bytes)

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

// ============================================================================
// Contained transaction errors
// ============================================================================

pub fn decode_errors_when_first_declared_transaction_is_missing_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)

  let assert Error(error) = block.decode(<<header:bits, 1>>)

  let assert TransactionDecodeFailed(tx_decode_err) =
    check_block_decode_error(error, 81, "block.transactions[0]")

  assert check_transaction_decode_error(tx_decode_err, 0, "transaction.version")
    == transaction.UnexpectedEof(bytes_needed: 4, remaining: 0)
}

pub fn decode_offsets_contained_transaction_errors_from_the_block_start_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  let incomplete_tx = <<1:32-little>>

  let assert Error(error) = block.decode(<<header:bits, 1, incomplete_tx:bits>>)

  let assert TransactionDecodeFailed(tx_decode_err) =
    check_block_decode_error(error, 85, "block.transactions[0]")

  assert check_transaction_decode_error(
      tx_decode_err,
      4,
      "transaction.inputs.count",
    )
    == transaction.UnexpectedEof(bytes_needed: 1, remaining: 0)
}

pub fn decode_reports_error_in_second_transaction_with_transaction_index_in_path_test() {
  let header = build_block_header(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)
  let incomplete_second_tx = <<1:32-little>>
  let bytes =
    build_block(header, [
      build_minimal_legacy_transaction(1),
      incomplete_second_tx,
    ])

  let assert Error(error) = block.decode(bytes)

  let assert TransactionDecodeFailed(tx_decode_err) =
    check_block_decode_error(error, 145, "block.transactions[1]")

  assert check_transaction_decode_error(
      tx_decode_err,
      4,
      "transaction.inputs.count",
    )
    == transaction.UnexpectedEof(bytes_needed: 1, remaining: 0)
}

// ============================================================================
// Block boundary
// ============================================================================

pub fn decode_rejects_trailing_bytes_after_a_complete_block_test() {
  let complete_block =
    build_header_only_block(1, <<0:size(256)>>, <<0:size(256)>>, 0, 0, 0)

  let assert Error(error) = block.decode(<<complete_block:bits, 0x42>>)

  assert check_block_decode_error(error, 81, "block") == TrailingBytes(1)
}

// ============================================================================
// decode_hex
// ============================================================================

pub fn decode_hex_decodes_block_with_one_legacy_transaction_test() {
  let header =
    build_block_header(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      1_234_567_890,
      0x1D00FFFF,
      2_083_236_893,
    )
  let bytes = build_block(header, [build_minimal_legacy_transaction(1)])

  let assert Ok(decoded_block) =
    bytes
    |> bit_array.base16_encode
    |> block.decode_hex

  assert decoded_block
    |> block.get_header
    |> block.get_header_timestamp
    == 1_234_567_890

  let assert [decoded_tx] = block.get_transactions(decoded_block)
  assert transaction.get_version(decoded_tx) == 1
  assert !transaction.is_segwit(decoded_tx)
}

pub fn decode_hex_errors_on_odd_length_string_test() {
  assert block.decode_hex("0") == Error(InvalidHex)
}

pub fn decode_hex_errors_on_invalid_hex_characters_test() {
  assert block.decode_hex("0000zz") == Error(InvalidHex)
}

pub fn decode_hex_errors_on_string_with_whitespace_test() {
  assert block.decode_hex("00 00") == Error(InvalidHex)
}

pub fn decode_hex_wraps_block_decode_error_test() {
  let assert Error(DecodeFailed(error)) = block.decode_hex("")

  assert check_block_decode_error(error, 0, "block.header.version")
    == UnexpectedEof(bytes_needed: 4, remaining: 0)
}

// ============================================================================
// Helper Functions
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

fn build_minimal_legacy_transaction(version: Int) -> BitArray {
  <<
    version:32-little,
    build_minimal_transaction_body():bits,
    0:32-little,
  >>
}

fn build_minimal_segwit_transaction() -> BitArray {
  <<
    1:32-little,
    0,
    1,
    build_minimal_transaction_body():bits,
    1,
    0,
    0:32-little,
  >>
}

fn build_minimal_transaction_body() -> BitArray {
  <<
    1,
    0:size(256),
    0:32-little,
    0,
    0:32-little,
    1,
    0:64-little,
    0,
  >>
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
