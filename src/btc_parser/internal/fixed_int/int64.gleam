import gleam/bit_array
import gleam/int

/// A signed 64-bit integer stored as 8 little-endian bytes.
///
/// This type exists to represent values that must be parsed and preserved
/// exactly across all Gleam targets.
///
/// On the Erlang target, integers are arbitrary precision, but on the
/// JavaScript target integers are represented as IEEE-754 numbers and cannot
/// exactly represent all 64-bit values. By storing the value as raw bytes,
/// `Int64` avoids precision loss while still allowing safe conversions when
/// possible.
///
/// The internal representation is always exactly 8 bytes in little-endian order.
pub opaque type Int64 {
  Int64(bytes_le: BitArray)
}

/// An error that occurred while constructing an `Int64` from a `BitArray`.
pub type FromBytesError {
  /// The input did not contain exactly 64 bits.
  ///
  /// The fields contain the measured and required bit counts, respectively.
  InvalidBitCount(actual: Int, expected: Int)
}

/// Constructs an `Int64` from exactly 8 little-endian bytes.
///
/// Returns an error if the provided `BitArray` does not contain exactly 8 bytes.
///
/// This function does not interpret the bytes beyond validating their length.
/// The numeric value is decoded lazily when conversions are requested.
/// 
/// ## Examples
///
/// ```gleam
/// from_bytes_le(<<0, 0, 0, 0, 0, 0, 0, 0>>)
/// // -> Ok(Int64) representing 0
///
/// from_bytes_le(<<1, 0, 0, 0, 0, 0, 0, 0>>)
/// // -> Ok(Int64) representing 1
///
/// from_bytes_le(<<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>)
/// // -> Ok(Int64) representing -1
///
/// from_bytes_le(<<1, 2, 3>>)
/// // -> Error(InvalidBitCount(actual: 24, expected: 64))
/// ```
pub fn from_bytes_le(bytes: BitArray) -> Result(Int64, FromBytesError) {
  case bytes {
    <<_:bytes-8>> -> Ok(Int64(bytes))
    _ -> Error(InvalidBitCount(bit_array.bit_size(bytes), 64))
  }
}

/// Attempts to convert the value to an `Int`.
///
/// **Target-specific behavior:**
/// - **Erlang**: Always succeeds (arbitrary precision integers)
/// - **JavaScript**: Succeeds only if the value is between `Number.MIN_SAFE_INTEGER` (-(2^53 - 1)) and `Number.MAX_SAFE_INTEGER` (2^53 - 1)
///
/// Returns `Error(Nil)` if the value cannot be safely represented on the current target.
///
/// For values that may exceed safe integer limits on JavaScript, consider using
/// `to_string()` instead, which always preserves the full numeric value.
pub fn to_int(i: Int64) -> Result(Int, Nil) {
  do_to_int(i.bytes_le)
}

@external(javascript, "./fixed_int_ffi.mjs", "int64LeToInt")
fn do_to_int(bytes_le: BitArray) -> Result(Int, Nil) {
  bytes_le
  |> decode_int64_le
  |> Ok
}

/// Converts the value to its base-10 string representation.
///
/// This function always succeeds and preserves the full numeric value on all
/// targets. It is the recommended way to serialize or display an `Int64`,
/// especially on the JavaScript target where large integers cannot be
/// represented natively.
pub fn to_string(i: Int64) -> String {
  do_to_string(i.bytes_le)
}

@external(javascript, "./fixed_int_ffi.mjs", "int64LeToString")
fn do_to_string(bytes_le: BitArray) -> String {
  bytes_le
  |> decode_int64_le
  |> int.to_string
}

fn decode_int64_le(bytes_le: BitArray) -> Int {
  // `<<i:64-signed-little>>` would be simpler, but Gleam warns about
  // truncation on JavaScript even though this fallback only runs on Erlang.

  let assert <<b0, b1, b2, b3, b4, b5, b6, b7>> = bytes_le

  let b7 = case b7 >= 128 {
    True -> b7 - 256
    False -> b7
  }

  let acc = b7 * 256 + b6
  let acc = acc * 256 + b5
  let acc = acc * 256 + b4
  let acc = acc * 256 + b3
  let acc = acc * 256 + b2
  let acc = acc * 256 + b1
  acc * 256 + b0
}
