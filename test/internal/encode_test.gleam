import internal/encode.{ValueOutOfRange}

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
