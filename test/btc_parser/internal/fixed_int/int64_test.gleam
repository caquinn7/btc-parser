import btc_parser/internal/fixed_int/int64.{InvalidBitCount}
import btc_parser/internal/fixed_int/shared_inputs
import support/target

/// 2^63 - 1
const max_i64_bytes = <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F>>

/// -2^63
const min_i64_bytes = <<0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80>>

/// -(2^53 - 1)
const min_safe_js_int = -9_007_199_254_740_991

/// -(2^53 - 1)
const min_safe_js_int_bytes = <<0x01, 0, 0, 0, 0, 0, 0xE0, 0xFF>>

// from_bytes_le

pub fn from_bytes_le_reports_incorrect_bit_counts_test() {
  assert Error(InvalidBitCount(actual: 0, expected: 64))
    == int64.from_bytes_le(<<>>)

  assert Error(InvalidBitCount(actual: 56, expected: 64))
    == int64.from_bytes_le(<<1, 0, 0, 0, 0, 0, 0>>)

  assert Error(InvalidBitCount(actual: 63, expected: 64))
    == int64.from_bytes_le(<<0:63>>)

  assert Error(InvalidBitCount(actual: 65, expected: 64))
    == int64.from_bytes_le(<<0:65>>)

  assert Error(InvalidBitCount(actual: 72, expected: 64))
    == int64.from_bytes_le(<<1, 0, 0, 0, 0, 0, 0, 0, 0>>)
}

pub fn from_bytes_le_returns_ok_when_input_is_8_bytes_test() {
  let assert Ok(_) = int64.from_bytes_le(shared_inputs.one_bytes)
}

// to_int

pub fn to_int_max_i64_test() {
  let expected = case target.is_javascript() {
    True -> Error(Nil)
    False -> Ok(max_i64())
  }

  let assert Ok(x) = int64.from_bytes_le(max_i64_bytes)

  assert int64.to_int(x) == expected
}

pub fn to_int_min_i64_test() {
  let expected = case target.is_javascript() {
    True -> Error(Nil)
    False -> Ok(min_i64())
  }

  let assert Ok(x) = int64.from_bytes_le(min_i64_bytes)

  assert int64.to_int(x) == expected
}

pub fn to_int_max_safe_js_int_test() {
  let assert Ok(x) = int64.from_bytes_le(shared_inputs.max_safe_js_int_bytes)
  assert int64.to_int(x) == Ok(shared_inputs.max_safe_js_int)
}

pub fn to_int_min_safe_js_int_test() {
  let assert Ok(x) = int64.from_bytes_le(min_safe_js_int_bytes)
  assert int64.to_int(x) == Ok(min_safe_js_int)
}

pub fn to_int_zero_test() {
  let assert Ok(x) = int64.from_bytes_le(shared_inputs.zero_bytes)
  assert int64.to_int(x) == Ok(0)
}

pub fn to_int_one_test() {
  let assert Ok(x) = int64.from_bytes_le(shared_inputs.one_bytes)
  assert int64.to_int(x) == Ok(1)
}

pub fn to_int_negative_one_test() {
  let assert Ok(x) =
    int64.from_bytes_le(<<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>)
  assert int64.to_int(x) == Ok(-1)
}

pub fn to_int_power_of_two_test() {
  let assert Ok(x) = int64.from_bytes_le(shared_inputs.two_to_32_bytes)
  assert int64.to_int(x) == Ok(shared_inputs.two_to_32)
}

pub fn to_int_negative_power_of_two_test() {
  let assert Ok(x) = int64.from_bytes_le(<<0, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF>>)
  assert int64.to_int(x) == Ok(0 - shared_inputs.two_to_32)
}

// to_string

pub fn to_string_zero_test() {
  let assert Ok(x) = int64.from_bytes_le(shared_inputs.zero_bytes)
  assert int64.to_string(x) == "0"
}

pub fn to_string_one_test() {
  let assert Ok(x) = int64.from_bytes_le(shared_inputs.one_bytes)
  assert int64.to_string(x) == "1"
}

pub fn to_string_negative_one_test() {
  let assert Ok(x) =
    int64.from_bytes_le(<<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>)
  assert int64.to_string(x) == "-1"
}

pub fn to_string_power_of_two_test() {
  let assert Ok(x) = int64.from_bytes_le(shared_inputs.two_to_32_bytes)
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

// Compute from smaller literals to avoid JavaScript truncation warnings.
// Callers keep this helper in Erlang-only branches when exact 64-bit boundaries matter.

fn max_i64() -> Int {
  let two_to_31 = 2_147_483_648
  two_to_31 * shared_inputs.two_to_32 - 1
}

fn min_i64() -> Int {
  let two_to_31 = 2_147_483_648
  0 - two_to_31 * shared_inputs.two_to_32
}
