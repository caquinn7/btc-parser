import btc_parser/internal/hash256.{InvalidBitCount}

pub fn from_bytes_le_reports_incorrect_bit_counts_test() {
  assert Error(InvalidBitCount(actual: 0, expected: 256))
    == hash256.from_bytes_le(<<>>)

  assert Error(InvalidBitCount(actual: 248, expected: 256))
    == hash256.from_bytes_le(<<1:little-size({ 31 * 8 })>>)

  assert Error(InvalidBitCount(actual: 255, expected: 256))
    == hash256.from_bytes_le(<<0:255>>)

  assert Error(InvalidBitCount(actual: 257, expected: 256))
    == hash256.from_bytes_le(<<0:257>>)

  assert Error(InvalidBitCount(actual: 264, expected: 256))
    == hash256.from_bytes_le(<<1:little-size({ 33 * 8 })>>)
}

pub fn from_bytes_le_returns_ok_when_input_is_32_bytes_test() {
  let assert Ok(_) = hash256.from_bytes_le(<<1:little-size({ 32 * 8 })>>)
}

pub fn to_bytes_le_returns_bytes_test() {
  let bytes = <<1:little-size({ 32 * 8 })>>
  let assert Ok(x) = hash256.from_bytes_le(bytes)

  assert hash256.to_bytes_le(x) == bytes
}
