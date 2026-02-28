import internal/encode.{ValueOutOfRange}

// i32_le

pub fn i32_le_zero_test() {
  assert encode.i32_le(0) == Ok(<<0, 0, 0, 0>>)
}

pub fn i32_le_one_test() {
  assert encode.i32_le(1) == Ok(<<1, 0, 0, 0>>)
}

pub fn i32_le_negative_one_test() {
  assert encode.i32_le(-1) == Ok(<<0xFF, 0xFF, 0xFF, 0xFF>>)
}

pub fn i32_le_max_value_test() {
  assert encode.i32_le(2_147_483_647) == Ok(<<0xFF, 0xFF, 0xFF, 0x7F>>)
}

pub fn i32_le_min_value_test() {
  assert encode.i32_le(-2_147_483_648) == Ok(<<0, 0, 0, 0x80>>)
}

pub fn i32_le_positive_value_test() {
  assert encode.i32_le(12_345) == Ok(<<0x39, 0x30, 0, 0>>)
}

pub fn i32_le_negative_value_test() {
  assert encode.i32_le(-12_345) == Ok(<<0xC7, 0xCF, 0xFF, 0xFF>>)
}

pub fn i32_le_out_of_range_above_test() {
  let input = 2_147_483_648
  assert encode.i32_le(input) == Error(ValueOutOfRange(input))
}

pub fn i32_le_out_of_range_below_test() {
  let input = -2_147_483_649
  assert encode.i32_le(input) == Error(ValueOutOfRange(input))
}

// i64_le

pub fn i64_le_zero_test() {
  assert encode.i64_le(0) == Ok(<<0, 0, 0, 0, 0, 0, 0, 0>>)
}

pub fn i64_le_one_test() {
  assert encode.i64_le(1) == Ok(<<1, 0, 0, 0, 0, 0, 0, 0>>)
}

pub fn i64_le_negative_one_test() {
  assert encode.i64_le(-1)
    == Ok(<<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>)
}

pub fn i64_le_positive_value_test() {
  assert encode.i64_le(12_345) == Ok(<<0x39, 0x30, 0, 0, 0, 0, 0, 0>>)
}

pub fn i64_le_negative_value_test() {
  assert encode.i64_le(-12_345)
    == Ok(<<0xC7, 0xCF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>)
}

pub fn i64_le_larger_than_i32_test() {
  // 2^31 = 2_147_483_648, valid for i64 but not i32
  assert encode.i64_le(2_147_483_648) == Ok(<<0, 0, 0, 0x80, 0, 0, 0, 0>>)
}

pub fn i64_le_out_of_range_above_test() {
  // 2^63, out of range on both Erlang and JavaScript targets
  let input = 9_223_372_036_854_775_808
  assert encode.i64_le(input) == Error(ValueOutOfRange(input))
}

pub fn i64_le_out_of_range_below_test() {
  // -(2^63 + 1), out of range on both Erlang and JavaScript targets
  let input = -9_223_372_036_854_775_809
  assert encode.i64_le(input) == Error(ValueOutOfRange(input))
}

// On JavaScript, i64_le rejects values outside the safe integer range
// (±(2^53 - 1)) to prevent encoding integers that have already lost precision.
// These values are valid on Erlang but produce an error on JavaScript.

@target(javascript)
pub fn i64_le_js_max_safe_integer_test() {
  // 2^53 - 1 = Number.MAX_SAFE_INTEGER, valid on JavaScript
  assert encode.i64_le(9_007_199_254_740_991)
    == Ok(<<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x1F, 0>>)
}

@target(javascript)
pub fn i64_le_js_out_of_range_above_test() {
  // 2^53 = Number.MAX_SAFE_INTEGER + 1, out of range on JavaScript
  let input = 9_007_199_254_740_992
  assert encode.i64_le(input) == Error(ValueOutOfRange(input))
}

@target(javascript)
pub fn i64_le_js_min_safe_integer_test() {
  // -(2^53 - 1) = Number.MIN_SAFE_INTEGER, valid on JavaScript
  assert encode.i64_le(-9_007_199_254_740_991)
    == Ok(<<0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0xE0, 0xFF>>)
}

@target(javascript)
pub fn i64_le_js_out_of_range_below_test() {
  // -(2^53) = Number.MIN_SAFE_INTEGER - 1, out of range on JavaScript
  let input = -9_007_199_254_740_992
  assert encode.i64_le(input) == Error(ValueOutOfRange(input))
}

@target(erlang)
pub fn i64_le_erlang_above_js_safe_range_test() {
  // 2^53 is out of range on JavaScript but valid on Erlang
  assert encode.i64_le(9_007_199_254_740_992)
    == Ok(<<0, 0, 0, 0, 0, 0, 0x20, 0>>)
}

// u32_le

pub fn u32_le_zero_test() {
  assert encode.u32_le(0) == Ok(<<0, 0, 0, 0>>)
}

pub fn u32_le_one_test() {
  assert encode.u32_le(1) == Ok(<<1, 0, 0, 0>>)
}

pub fn u32_le_max_value_test() {
  assert encode.u32_le(4_294_967_295) == Ok(<<0xFF, 0xFF, 0xFF, 0xFF>>)
}

pub fn u32_le_positive_value_test() {
  assert encode.u32_le(12_345) == Ok(<<0x39, 0x30, 0, 0>>)
}

pub fn u32_le_out_of_range_above_test() {
  let input = 4_294_967_296
  assert encode.u32_le(input) == Error(ValueOutOfRange(input))
}

pub fn u32_le_out_of_range_below_test() {
  let input = -1
  assert encode.u32_le(input) == Error(ValueOutOfRange(input))
}
