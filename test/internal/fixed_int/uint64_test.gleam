import internal/fixed_int/constants
import internal/fixed_int/uint64.{InvalidByteCount}
import support/target

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

pub fn to_int_max_u64_test() {
  let expected = case target.is_javascript() {
    True -> Error(Nil)
    False -> Ok(max_u64())
  }

  let assert Ok(x) = uint64.from_bytes_le(max_u64_bytes)

  assert uint64.to_int(x) == expected
}

pub fn to_int_max_safe_js_int_test() {
  let assert Ok(x) = uint64.from_bytes_le(constants.max_safe_js_int_bytes)
  assert uint64.to_int(x) == Ok(constants.max_safe_js_int)
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

// from_int

pub fn from_int_zero_test() {
  let assert Ok(x) = uint64.from_int(0)
  assert uint64.to_bytes_le(x) == <<0, 0, 0, 0, 0, 0, 0, 0>>
}

pub fn from_int_one_test() {
  let assert Ok(x) = uint64.from_int(1)
  assert uint64.to_bytes_le(x) == <<1, 0, 0, 0, 0, 0, 0, 0>>
}

pub fn from_int_large_test() {
  // 2^32 = 4_294_967_296
  let assert Ok(x) = uint64.from_int(4_294_967_296)
  assert uint64.to_bytes_le(x) == <<0, 0, 0, 0, 1, 0, 0, 0>>
}

pub fn from_int_max_safe_js_int_test() {
  let assert Ok(x) = uint64.from_int(constants.max_safe_js_int)
  assert uint64.to_bytes_le(x) == constants.max_safe_js_int_bytes
}

pub fn from_int_negative_returns_error_test() {
  assert uint64.from_int(-1) == Error(uint64.ValueOutOfRange(-1))
}

pub fn from_int_round_trip_test() {
  let original = 42
  let assert Ok(x) = uint64.from_int(original)
  assert uint64.to_int(x) == Ok(original)
}

pub fn from_int_above_max_safe_js_int_test() {
  let n = constants.max_safe_js_int + 1

  case target.is_javascript() {
    True -> {
      let assert Error(uint64.ValueOutOfRange(_)) = uint64.from_int(n)
      Nil
    }
    False -> {
      let assert Ok(x) = uint64.from_int(n)
      assert uint64.to_bytes_le(x) == constants.max_safe_js_int_plus_one_bytes
    }
  }
}

pub fn from_int_max_u64_test() {
  let n = max_u64()

  case target.is_javascript() {
    True -> {
      let assert Error(uint64.ValueOutOfRange(_)) = uint64.from_int(n)
      Nil
    }
    False -> {
      let assert Ok(x) = uint64.from_int(n)
      assert uint64.to_bytes_le(x) == max_u64_bytes
    }
  }
}

pub fn from_int_above_max_u64_test() {
  let n = max_u64() + 1
  let assert Error(uint64.ValueOutOfRange(_)) = uint64.from_int(n)
}

fn max_u64() -> Int {
  let two_to_32 = 4_294_967_296
  two_to_32 * two_to_32 - 1
}
