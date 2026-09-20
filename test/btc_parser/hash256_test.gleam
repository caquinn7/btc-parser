import btc_parser/hash256.{InvalidBitCount}
import gleam/string

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

pub fn to_bytes_le_returns_original_bytes_test() {
  let bytes = <<1:little-size({ 32 * 8 })>>
  let assert Ok(hash) = hash256.from_bytes_le(bytes)

  assert hash256.to_bytes_le(hash) == bytes
}

pub fn to_display_hex_reverses_wire_order_bytes_test() {
  let assert Ok(hash) = hash256.from_bytes_le(<<0x12, 0x34, 0:size(240)>>)

  let expected = string.repeat("0", 60) <> "3412"
  assert hash256.to_display_hex(hash) == expected
}

pub fn to_display_hex_uses_lowercase_hex_test() {
  let assert Ok(hash) = hash256.from_bytes_le(<<0:248, 0xAB>>)

  let expected = "ab" <> string.repeat("0", 62)
  assert hash256.to_display_hex(hash) == expected
}

pub fn to_display_hex_formats_zero_as_64_characters_test() {
  let assert Ok(hash) = hash256.from_bytes_le(<<0:256>>)
  let display = hash256.to_display_hex(hash)

  assert display == string.repeat("0", 64)
  assert string.length(display) == 64
}
