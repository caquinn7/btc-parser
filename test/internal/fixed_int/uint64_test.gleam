import internal/fixed_int/shared_inputs
import internal/fixed_int/uint64.{InvalidByteCount}
import support/target

/// 2^64 - 1
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
  let assert Ok(_) = uint64.from_bytes_le(shared_inputs.one_bytes)
}

// to_bytes_le

pub fn to_bytes_le_returns_bytes_test() {
  let bytes = shared_inputs.one_bytes
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
  let assert Ok(x) = uint64.from_bytes_le(shared_inputs.max_safe_js_int_bytes)
  assert uint64.to_int(x) == Ok(shared_inputs.max_safe_js_int)
}

pub fn to_int_zero_test() {
  let assert Ok(x) = uint64.from_bytes_le(shared_inputs.zero_bytes)
  assert uint64.to_int(x) == Ok(0)
}

pub fn to_int_one_test() {
  let assert Ok(x) = uint64.from_bytes_le(shared_inputs.one_bytes)
  assert uint64.to_int(x) == Ok(1)
}

pub fn to_int_power_of_two_test() {
  // 2^32 = 4294967296
  let assert Ok(x) = uint64.from_bytes_le(shared_inputs.two_to_32_bytes)
  assert uint64.to_int(x) == Ok(shared_inputs.two_to_32)
}

// to_string

pub fn to_string_zero_test() {
  let assert Ok(x) = uint64.from_bytes_le(shared_inputs.zero_bytes)
  assert uint64.to_string(x) == "0"
}

pub fn to_string_one_test() {
  let assert Ok(x) = uint64.from_bytes_le(shared_inputs.one_bytes)
  assert uint64.to_string(x) == "1"
}

pub fn to_string_power_of_two_test() {
  // 2^32 = 4294967296
  let assert Ok(x) = uint64.from_bytes_le(shared_inputs.two_to_32_bytes)
  assert uint64.to_string(x) == "4294967296"
}

pub fn to_string_max_value_test() {
  let assert Ok(x) = uint64.from_bytes_le(max_u64_bytes)
  assert uint64.to_string(x) == "18446744073709551615"
}

// from_int

pub fn from_int_zero_test() {
  let assert Ok(x) = uint64.from_int(0)
  assert uint64.to_bytes_le(x) == shared_inputs.zero_bytes
}

pub fn from_int_one_test() {
  let assert Ok(x) = uint64.from_int(1)
  assert uint64.to_bytes_le(x) == shared_inputs.one_bytes
}

pub fn from_int_large_test() {
  // 2^32 = 4_294_967_296
  let assert Ok(x) = uint64.from_int(shared_inputs.two_to_32)
  assert uint64.to_bytes_le(x) == shared_inputs.two_to_32_bytes
}

pub fn from_int_max_safe_js_int_test() {
  let assert Ok(x) = uint64.from_int(shared_inputs.max_safe_js_int)
  assert uint64.to_bytes_le(x) == shared_inputs.max_safe_js_int_bytes
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
  let n = shared_inputs.max_safe_js_int + 1

  case target.is_javascript() {
    True -> {
      let assert Error(uint64.ValueOutOfRange(_)) = uint64.from_int(n)
      Nil
    }
    False -> {
      let assert Ok(x) = uint64.from_int(n)

      assert uint64.to_bytes_le(x)
        == shared_inputs.max_safe_js_int_plus_one_bytes
    }
  }
}

// The u64 boundaries are outside JavaScript's safe integer range.
// Test them only on Erlang, where Int is arbitrary precision.

pub fn from_int_max_u64_test() {
  case target.is_javascript() {
    True -> Nil
    False -> {
      let assert Ok(x) = uint64.from_int(max_u64())
      assert uint64.to_bytes_le(x) == max_u64_bytes
    }
  }
}

pub fn from_int_above_max_u64_test() {
  case target.is_javascript() {
    True -> Nil
    False -> {
      let n = max_u64() + 1
      let assert Error(uint64.ValueOutOfRange(_)) = uint64.from_int(n)
      Nil
    }
  }
}

// Compute from smaller literals to avoid JavaScript truncation warnings.
// Callers keep this helper in Erlang-only branches when exact 64-bit boundaries matter.

fn max_u64() -> Int {
  shared_inputs.two_to_32 * shared_inputs.two_to_32 - 1
}
