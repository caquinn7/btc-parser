import gleam/bool
import gleam/int

/// Represents errors that can occur when encoding an integer.
pub type EncodeError {
  /// The integer value is outside the valid range for the target encoding.
  /// Contains the invalid value that was attempted.
  ValueOutOfRange(Int)
}

/// Encodes a signed 32-bit integer as a little-endian `BitArray`.
///
/// Returns `Error(ValueOutOfRange(i))` if `i` is outside the range
/// `-2,147,483,648` to `2,147,483,647`.
///
/// ## Examples
///
/// ```gleam
/// i32_le(1)
/// // -> Ok(<<1, 0, 0, 0>>)
///
/// i32_le(-1)
/// // -> Ok(<<0xFF, 0xFF, 0xFF, 0xFF>>)
///
/// i32_le(2_147_483_648)
/// // -> Error(ValueOutOfRange(2147483648))
/// ```
pub fn i32_le(i: Int) -> Result(BitArray, EncodeError) {
  i_le(i, 32)
}

fn i_le(i: Int, bit_count: Int) -> Result(BitArray, EncodeError) {
  let #(min, max) = compute_limits(bit_count)
  let in_range = min <= i && i <= max
  use <- bool.guard(!in_range, Error(ValueOutOfRange(i)))

  let unsigned_value = case i >= 0 {
    True -> i
    False -> {
      // Reinterpret as two's complement unsigned value,
      // e.g. -1 with 32 bits becomes 2^32 + (-1) = 0xFFFFFFFF
      let modulus = pow_2(bit_count)
      modulus + i
    }
  }

  Ok(to_bytes(unsigned_value, bit_count))
}

fn compute_limits(bit_count: Int) -> #(Int, Int) {
  let sign_bit_value = pow_2(bit_count - 1)
  #(-sign_bit_value, sign_bit_value - 1)
}

fn pow_2(exponent: Int) -> Int {
  // 2^exponent
  int.bitwise_shift_left(1, exponent)
}

fn to_bytes(value: Int, bit_count: Int) -> BitArray {
  to_bytes_loop(value, 0, bit_count / 8, <<>>)
}

fn to_bytes_loop(value: Int, index: Int, byte_count: Int, acc: BitArray) {
  case index == byte_count {
    True -> acc
    False -> {
      let byte =
        value
        |> int.bitwise_shift_right(8 * index)
        |> int.bitwise_and(0xFF)

      to_bytes_loop(value, index + 1, byte_count, <<acc:bits, byte:size(8)>>)
    }
  }
}
