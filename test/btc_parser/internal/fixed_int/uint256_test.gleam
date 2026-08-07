import btc_parser/internal/fixed_int/uint256.{InvalidBitCount}

pub fn from_bytes_le_reports_incorrect_bit_counts_test() {
  assert Error(InvalidBitCount(actual: 0, expected: 256))
    == uint256.from_bytes_le(<<>>)

  assert Error(InvalidBitCount(actual: 248, expected: 256))
    == uint256.from_bytes_le(<<1:little-size({ 31 * 8 })>>)

  assert Error(InvalidBitCount(actual: 255, expected: 256))
    == uint256.from_bytes_le(<<0:255>>)

  assert Error(InvalidBitCount(actual: 257, expected: 256))
    == uint256.from_bytes_le(<<0:257>>)

  assert Error(InvalidBitCount(actual: 264, expected: 256))
    == uint256.from_bytes_le(<<1:little-size({ 33 * 8 })>>)
}

pub fn from_bytes_le_returns_ok_when_input_is_32_bytes_test() {
  let assert Ok(_) = uint256.from_bytes_le(<<1:little-size({ 32 * 8 })>>)
}

pub fn to_bytes_le_returns_wrapped_little_endian_bytes_test() {
  let bytes = <<
    0x00,
    0x01,
    0x02,
    0x03,
    0x04,
    0x05,
    0x06,
    0x07,
    0x08,
    0x09,
    0x0A,
    0x0B,
    0x0C,
    0x0D,
    0x0E,
    0x0F,
    0x10,
    0x11,
    0x12,
    0x13,
    0x14,
    0x15,
    0x16,
    0x17,
    0x18,
    0x19,
    0x1A,
    0x1B,
    0x1C,
    0x1D,
    0x1E,
    0x1F,
  >>
  let assert Ok(value) = uint256.from_bytes_le(bytes)

  assert uint256.to_bytes_le(value) == bytes
}

pub fn is_zero_returns_true_when_all_bits_are_unset_test() {
  let assert Ok(value) = uint256.from_bytes_le(<<0:256>>)
  assert uint256.is_zero(value)
}

pub fn is_zero_returns_false_when_any_bit_is_set_test() {
  let assert Ok(value) = uint256.from_bytes_le(<<1:1, 0:255>>)
  assert !uint256.is_zero(value)

  let assert Ok(value) = uint256.from_bytes_le(<<0:255, 1:1>>)
  assert !uint256.is_zero(value)

  let assert Ok(value) = uint256.from_bytes_le(<<0:128, 0x80, 0:120>>)
  assert !uint256.is_zero(value)
}
