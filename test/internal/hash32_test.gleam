import internal/hash32.{InvalidByteCount}

pub fn from_bytes_le_returns_error_when_input_is_not_32_bytes_test() {
  assert Error(InvalidByteCount(0)) == hash32.from_bytes_le(<<>>)

  assert Error(InvalidByteCount(31))
    == hash32.from_bytes_le(<<1:little-size({ 31 * 8 })>>)

  assert Error(InvalidByteCount(33))
    == hash32.from_bytes_le(<<1:little-size({ 33 * 8 })>>)
}

pub fn from_bytes_le_returns_ok_when_input_is_32_bytes_test() {
  let assert Ok(_) = hash32.from_bytes_le(<<1:little-size({ 32 * 8 })>>)
}

pub fn to_bytes_le_returns_bytes_test() {
  let bytes = <<1:little-size({ 32 * 8 })>>
  let assert Ok(x) = hash32.from_bytes_le(bytes)

  assert hash32.to_bytes_le(x) == bytes
}
