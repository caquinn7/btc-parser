import gleam/bit_array
import gleam/int
import gleam/result

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

/// Error that can occur when constructing an `Int64`.
pub type FromBytesError {
  /// The provided byte sequence does not contain exactly 8 bytes.
  InvalidByteCount(Int)
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
/// // -> Error(InvalidByteCount(3))
/// ```
pub fn from_bytes_le(bytes: BitArray) -> Result(Int64, FromBytesError) {
  case bytes {
    <<_:bytes-8>> -> Ok(Int64(bytes))
    _ -> Error(InvalidByteCount(bit_array.byte_size(bytes)))
  }
}

/// Returns the raw little-endian byte representation of the value.
///
/// The returned `BitArray` is always exactly 8 bytes long.
pub fn to_bytes_le(i: Int64) -> BitArray {
  i.bytes_le
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

/// Error that can occur when constructing an `Int64` from an `Int`.
pub type FromIntError {
  /// The value is outside JavaScript's safe integer range.
  UnsafeInteger
  /// The value is less than the minimum signed 64-bit integer.
  BelowMinInt64
  /// The value is greater than the maximum signed 64-bit integer.
  ExceedsInt64
}

/// Constructs an `Int64` from a Gleam `Int`.
///
/// **Target-specific behavior:**
/// - **Erlang**: Returns `Error(ExceedsInt64)` for values greater than
///   2^63 - 1 and `Error(BelowMinInt64)` for values less than -2^63.
/// - **JavaScript**: Returns `Error(UnsafeInteger)` for values outside the safe
///   integer range [-(2^53 - 1), 2^53 - 1], which prevents encoding values
///   that may have already lost precision.
///
/// ## Examples
///
/// ```gleam
/// from_int(42)
/// // -> Ok(Int64) representing 42
///
/// from_int(-1)
/// // -> Ok(Int64) representing -1
///
/// // On Erlang:
/// from_int(9_223_372_036_854_775_808)  // 2^63, exceeds max
/// // -> Error(ExceedsInt64)
///
/// from_int(-9_223_372_036_854_775_809)  // less than -2^63
/// // -> Error(BelowMinInt64)
///
/// // On JavaScript:
/// from_int(9_007_199_254_740_992)  // 2^53, exceeds safe range
/// // -> Error(UnsafeInteger)
/// ```
pub fn from_int(i: Int) -> Result(Int64, FromIntError) {
  i
  |> do_from_int
  |> result.map(fn(bytes) {
    let assert Ok(i64) = from_bytes_le(bytes)
    i64
  })
  |> result.replace_error(case running_on_javascript() {
    True -> UnsafeInteger
    // `do_from_int` has already established that this exact Erlang integer is
    // outside the signed 64-bit range, so its sign identifies the failed bound.
    False ->
      case i < 0 {
        True -> BelowMinInt64
        False -> ExceedsInt64
      }
  })
}

@external(javascript, "./fixed_int_ffi.mjs", "runningOnJavaScript")
fn running_on_javascript() -> Bool {
  False
}

@external(javascript, "./fixed_int_ffi.mjs", "int64FromInt")
fn do_from_int(i: Int) -> Result(BitArray, Nil) {
  // On Erlang, integers are arbitrary precision, so we must check bounds.
  // The valid range for signed 64-bit is [-2^63, 2^63 - 1].
  case -9_223_372_036_854_775_808 <= i && i <= 9_223_372_036_854_775_807 {
    True -> Ok(<<i:64-little>>)
    False -> Error(Nil)
  }
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

/// Converts a Gleam `Int` directly to its little-endian byte representation.
///
/// This is a convenience wrapper around `from_int` and `to_bytes_le`.
/// The returned `BitArray` is always exactly 8 bytes long.
///
/// Returns the same errors as `from_int`:
/// - **Erlang**: `ExceedsInt64` above 2^63 - 1 and `BelowMinInt64` below -2^63.
/// - **JavaScript**: `UnsafeInteger` outside the safe integer range
///   [-(2^53 - 1), 2^53 - 1].
///
/// ## Examples
///
/// ```gleam
/// int_to_bytes_le(1)
/// // -> Ok(<<1, 0, 0, 0, 0, 0, 0, 0>>)
///
/// int_to_bytes_le(-1)
/// // -> Ok(<<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>)
///
/// int_to_bytes_le(9_223_372_036_854_775_808)  // 2^63, exceeds max on Erlang
/// // -> Error(ExceedsInt64)
/// ```
pub fn int_to_bytes_le(i: Int) -> Result(BitArray, FromIntError) {
  i
  |> from_int
  |> result.map(to_bytes_le)
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
