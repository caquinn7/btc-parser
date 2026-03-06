import internal/fixed_int/int64.{InvalidByteCount}

const max_i64_bytes = <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F>>

const min_i64_bytes = <<0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80>>

// from_bytes_le

pub fn from_bytes_le_returns_error_when_input_not_8_bytes_test() {
  assert Error(InvalidByteCount(0)) == int64.from_bytes_le(<<>>)

  assert Error(InvalidByteCount(7))
    == int64.from_bytes_le(<<1, 0, 0, 0, 0, 0, 0>>)

  assert Error(InvalidByteCount(9))
    == int64.from_bytes_le(<<1, 0, 0, 0, 0, 0, 0, 0, 0>>)
}

pub fn from_bytes_le_returns_ok_when_input_is_8_bytes_test() {
  let assert Ok(_) = int64.from_bytes_le(<<1, 0, 0, 0, 0, 0, 0, 0>>)
}

// to_bytes_le

pub fn to_bytes_le_returns_bytes_test() {
  let bytes = <<1, 0, 0, 0, 0, 0, 0, 0>>
  let assert Ok(x) = int64.from_bytes_le(bytes)

  assert int64.to_bytes_le(x) == bytes
}

// to_int

@target(javascript)
pub fn to_int_js_returns_error_when_greater_than_max_safe_integer_test() {
  let assert Ok(x) = int64.from_bytes_le(max_i64_bytes)
  assert int64.to_int(x) == Error(Nil)
}

@target(javascript)
pub fn to_int_js_returns_error_when_less_than_min_safe_integer_test() {
  let assert Ok(x) = int64.from_bytes_le(min_i64_bytes)
  assert int64.to_int(x) == Error(Nil)
}

@target(erlang)
pub fn to_int_erlang_returns_ok_when_max_value_test() {
  let assert Ok(x) = int64.from_bytes_le(max_i64_bytes)
  assert int64.to_int(x) == Ok(9_223_372_036_854_775_807)
}

@target(erlang)
pub fn to_int_erlang_returns_ok_when_min_value_test() {
  let assert Ok(x) = int64.from_bytes_le(min_i64_bytes)
  assert int64.to_int(x) == Ok(-9_223_372_036_854_775_808)
}

pub fn to_int_max_safe_js_int_test() {
  let max_safe_js_int = <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x1F, 0x00>>
  let assert Ok(x) = int64.from_bytes_le(max_safe_js_int)

  assert int64.to_int(x) == Ok(9_007_199_254_740_991)
}

pub fn to_int_min_safe_js_int_test() {
  let min_safe_js_int = <<0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0xE0, 0xFF>>
  let assert Ok(x) = int64.from_bytes_le(min_safe_js_int)

  assert int64.to_int(x) == Ok(-9_007_199_254_740_991)
}

pub fn to_int_zero_test() {
  let assert Ok(x) = int64.from_bytes_le(<<0, 0, 0, 0, 0, 0, 0, 0>>)
  assert int64.to_int(x) == Ok(0)
}

pub fn to_int_one_test() {
  let assert Ok(x) = int64.from_bytes_le(<<1, 0, 0, 0, 0, 0, 0, 0>>)
  assert int64.to_int(x) == Ok(1)
}

pub fn to_int_negative_one_test() {
  let assert Ok(x) =
    int64.from_bytes_le(<<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>)
  assert int64.to_int(x) == Ok(-1)
}

pub fn to_int_power_of_two_test() {
  let assert Ok(x) = int64.from_bytes_le(<<0, 0, 0, 0, 1, 0, 0, 0>>)
  assert int64.to_int(x) == Ok(4_294_967_296)
}

pub fn to_int_negative_power_of_two_test() {
  let assert Ok(x) = int64.from_bytes_le(<<0, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF>>)
  assert int64.to_int(x) == Ok(-4_294_967_296)
}

// to_string

pub fn to_string_zero_test() {
  let assert Ok(x) = int64.from_bytes_le(<<0, 0, 0, 0, 0, 0, 0, 0>>)
  assert int64.to_string(x) == "0"
}

pub fn to_string_one_test() {
  let assert Ok(x) = int64.from_bytes_le(<<1, 0, 0, 0, 0, 0, 0, 0>>)
  assert int64.to_string(x) == "1"
}

pub fn to_string_negative_one_test() {
  let assert Ok(x) =
    int64.from_bytes_le(<<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>)
  assert int64.to_string(x) == "-1"
}

pub fn to_string_power_of_two_test() {
  let assert Ok(x) = int64.from_bytes_le(<<0, 0, 0, 0, 1, 0, 0, 0>>)
  assert int64.to_string(x) == "4294967296"
}

pub fn to_string_negative_power_of_two_test() {
  let assert Ok(x) = int64.from_bytes_le(<<0, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF>>)
  assert int64.to_string(x) == "-4294967296"
}

pub fn to_string_max_value_test() {
  let assert Ok(x) = int64.from_bytes_le(max_i64_bytes)
  assert int64.to_string(x) == "9223372036854775807"
}

pub fn to_string_min_value_test() {
  let assert Ok(x) = int64.from_bytes_le(min_i64_bytes)
  assert int64.to_string(x) == "-9223372036854775808"
}

// from_int

pub fn from_int_zero_test() {
  let assert Ok(x) = int64.from_int(0)
  assert int64.to_bytes_le(x) == <<0, 0, 0, 0, 0, 0, 0, 0>>
}

pub fn from_int_one_test() {
  let assert Ok(x) = int64.from_int(1)
  assert int64.to_bytes_le(x) == <<1, 0, 0, 0, 0, 0, 0, 0>>
}

pub fn from_int_negative_one_test() {
  let assert Ok(x) = int64.from_int(-1)
  assert int64.to_bytes_le(x)
    == <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>
}

pub fn from_int_positive_large_test() {
  let assert Ok(x) = int64.from_int(4_294_967_296)
  assert int64.to_bytes_le(x) == <<0, 0, 0, 0, 1, 0, 0, 0>>
}

pub fn from_int_negative_large_test() {
  let assert Ok(x) = int64.from_int(-4_294_967_296)
  assert int64.to_bytes_le(x) == <<0, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF>>
}

pub fn from_int_max_safe_js_int_test() {
  let assert Ok(x) = int64.from_int(9_007_199_254_740_991)
  assert int64.to_bytes_le(x)
    == <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x1F, 0x00>>
}

pub fn from_int_min_safe_js_int_test() {
  let assert Ok(x) = int64.from_int(-9_007_199_254_740_991)
  assert int64.to_bytes_le(x)
    == <<0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0xE0, 0xFF>>
}

pub fn from_int_round_trip_test() {
  let original = 42
  let assert Ok(x) = int64.from_int(original)
  assert int64.to_int(x) == Ok(original)
}

pub fn from_int_round_trip_negative_test() {
  let original = -12_345
  let assert Ok(x) = int64.from_int(original)
  assert int64.to_int(x) == Ok(original)
}

@target(javascript)
pub fn from_int_js_out_of_range_above_test() {
  // 2^53 = MAX_SAFE_INTEGER + 1
  assert int64.from_int(9_007_199_254_740_992)
    == Error(int64.ValueOutOfRange(9_007_199_254_740_992))
}

@target(javascript)
pub fn from_int_js_out_of_range_below_test() {
  // -(2^53) = MIN_SAFE_INTEGER - 1
  assert int64.from_int(-9_007_199_254_740_992)
    == Error(int64.ValueOutOfRange(-9_007_199_254_740_992))
}

@target(erlang)
pub fn from_int_erlang_max_value_test() {
  let assert Ok(x) = int64.from_int(9_223_372_036_854_775_807)
  assert int64.to_bytes_le(x) == max_i64_bytes
}

@target(erlang)
pub fn from_int_erlang_min_value_test() {
  let assert Ok(x) = int64.from_int(-9_223_372_036_854_775_808)
  assert int64.to_bytes_le(x) == min_i64_bytes
}

@target(erlang)
pub fn from_int_erlang_out_of_range_above_test() {
  assert int64.from_int(9_223_372_036_854_775_808)
    == Error(int64.ValueOutOfRange(9_223_372_036_854_775_808))
}

@target(erlang)
pub fn from_int_erlang_out_of_range_below_test() {
  assert int64.from_int(-9_223_372_036_854_775_809)
    == Error(int64.ValueOutOfRange(-9_223_372_036_854_775_809))
}
