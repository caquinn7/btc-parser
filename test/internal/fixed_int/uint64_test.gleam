import internal/fixed_int/uint64.{InvalidByteCount}

const max_u64_bytes = <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>

// from_bytes_le

pub fn from_bytes_le_returns_error_when_input_not_8_bytes_test() {
  assert Error(InvalidByteCount(0)) == uint64.from_bytes_le(<<>>)

  assert Error(InvalidByteCount(7))
    == uint64.from_bytes_le(<<1, 0, 0, 0, 0, 0, 0>>)

  assert Error(InvalidByteCount(9))
    == uint64.from_bytes_le(<<1, 0, 0, 0, 0, 0, 0, 0, 0>>)
}

pub fn from_bytes_le_returns_ok_when_input_is_8_bytes_test() {
  let assert Ok(_) = uint64.from_bytes_le(<<1, 0, 0, 0, 0, 0, 0, 0>>)
}

// to_bytes_le

pub fn to_bytes_le_returns_bytes_test() {
  let bytes = <<1, 0, 0, 0, 0, 0, 0, 0>>
  let assert Ok(x) = uint64.from_bytes_le(bytes)

  assert uint64.to_bytes_le(x) == bytes
}

// to_int

@target(javascript)
pub fn to_int_js_returns_error_when_greater_than_max_safe_integer_test() {
  let assert Ok(x) = uint64.from_bytes_le(max_u64_bytes)
  assert uint64.to_int(x) == Error(Nil)
}

@target(erlang)
pub fn to_int_erlang_returns_ok_when_max_value_test() {
  let assert Ok(x) = uint64.from_bytes_le(max_u64_bytes)
  assert uint64.to_int(x) == Ok(18_446_744_073_709_551_615)
}

pub fn to_int_max_safe_js_int_test() {
  // 2^53 - 1 = 9007199254740991
  let max_safe_js_int = <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x1F, 0x00>>
  let assert Ok(x) = uint64.from_bytes_le(max_safe_js_int)

  assert uint64.to_int(x) == Ok(9_007_199_254_740_991)
}

pub fn to_int_zero_test() {
  let assert Ok(x) = uint64.from_bytes_le(<<0, 0, 0, 0, 0, 0, 0, 0>>)
  assert uint64.to_int(x) == Ok(0)
}

pub fn to_int_one_test() {
  let assert Ok(x) = uint64.from_bytes_le(<<1, 0, 0, 0, 0, 0, 0, 0>>)
  assert uint64.to_int(x) == Ok(1)
}

pub fn to_int_power_of_two_test() {
  // 2^32 = 4294967296
  let assert Ok(x) = uint64.from_bytes_le(<<0, 0, 0, 0, 1, 0, 0, 0>>)
  assert uint64.to_int(x) == Ok(4_294_967_296)
}

// to_string

pub fn to_string_zero_test() {
  let assert Ok(x) = uint64.from_bytes_le(<<0, 0, 0, 0, 0, 0, 0, 0>>)
  assert uint64.to_string(x) == "0"
}

pub fn to_string_one_test() {
  let assert Ok(x) = uint64.from_bytes_le(<<1, 0, 0, 0, 0, 0, 0, 0>>)
  assert uint64.to_string(x) == "1"
}

pub fn to_string_power_of_two_test() {
  // 2^32 = 4294967296
  let assert Ok(x) = uint64.from_bytes_le(<<0, 0, 0, 0, 1, 0, 0, 0>>)
  assert uint64.to_string(x) == "4294967296"
}

pub fn to_string_max_value_test() {
  let assert Ok(x) = uint64.from_bytes_le(max_u64_bytes)
  assert uint64.to_string(x) == "18446744073709551615"
}
