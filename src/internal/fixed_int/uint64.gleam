import gleam/bit_array
import gleam/int
import gleam/result

/// An unsigned 64-bit integer stored as 8 little-endian bytes.
///
/// This type exists to represent values that must be parsed and preserved
/// exactly across all Gleam targets.
///
/// On the Erlang target, integers are arbitrary precision, but on the
/// JavaScript target integers are represented as IEEE-754 numbers and cannot
/// exactly represent all 64-bit values. By storing the value as raw bytes,
/// `Uint64` avoids precision loss while still allowing safe conversions when
/// possible.
///
/// The internal representation is always exactly 8 bytes in little-endian order.
pub opaque type Uint64 {
  Uint64(bytes_le: BitArray)
}

/// Errors that can occur when constructing a `Uint64`.
pub type Uint64Error {
  /// The provided byte sequence does not contain exactly 8 bytes.
  InvalidByteCount(Int)
}

/// Constructs a `Uint64` from exactly 8 little-endian bytes.
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
/// // -> Ok(Uint64) representing 0
///
/// from_bytes_le(<<1, 0, 0, 0, 0, 0, 0, 0>>)
/// // -> Ok(Uint64) representing 1
///
/// from_bytes_le(<<1, 2, 3>>)
/// // -> Error(InvalidByteCount(3))
/// ```
pub fn from_bytes_le(bytes: BitArray) -> Result(Uint64, Uint64Error) {
  case bytes {
    <<_:bytes-size(8)>> -> Ok(Uint64(bytes))
    _ -> Error(InvalidByteCount(bit_array.byte_size(bytes)))
  }
}

/// Errors that can occur when constructing an `Uint64` from an `Int`.
pub type FromIntError {
  /// The value cannot be represented as an unsigned 64-bit integer.
  ///
  /// On Erlang: Value is outside the range [0, 2^64 - 1]
  /// 
  /// On JavaScript: Value is outside the safe integer range [0, 2^53 - 1],
  /// which prevents encoding values that have already lost precision
  ValueOutOfRange(Int)
}

/// Constructs a `Uint64` from a Gleam `Int`.
///
/// **Target-specific behavior:**
/// - **Erlang**: Returns `Error(ValueOutOfRange)` if the value is negative or
///   exceeds the unsigned 64-bit range [0, 2^64 - 1]
/// - **JavaScript**: Returns `Error(ValueOutOfRange)` if the value is negative
///   or exceeds the safe integer range [0, 2^53 - 1], which prevents encoding
///   values that have already lost precision
///
/// ## Examples
///
/// ```gleam
/// from_int(42)
/// // -> Ok(Uint64) representing 42
///
/// from_int(-1)
/// // -> Error(ValueOutOfRange(-1))
///
/// // On Erlang:
/// from_int(18_446_744_073_709_551_616)  // 2^64, exceeds max
/// // -> Error(ValueOutOfRange(18446744073709551616))
///
/// // On JavaScript:
/// from_int(9_007_199_254_740_992)  // 2^53, exceeds safe range
/// // -> Error(ValueOutOfRange(9007199254740992))
/// ```
pub fn from_int(i: Int) -> Result(Uint64, FromIntError) {
  use bytes <- result.try(
    i
    |> do_from_int
    |> result.replace_error(ValueOutOfRange(i)),
  )

  let assert Ok(u64) = from_bytes_le(bytes)
  Ok(u64)
}

@external(javascript, "./int64_ffi.mjs", "uint64FromInt")
fn do_from_int(i: Int) -> Result(BitArray, Nil) {
  // On Erlang, integers are arbitrary precision, so we must check bounds.
  // The valid range for unsigned 64-bit is [0, 2^64 - 1].
  case 0 <= i && i <= 18_446_744_073_709_551_615 {
    True -> Ok(<<i:little-size(64)>>)
    False -> Error(Nil)
  }
}

/// Returns the raw little-endian byte representation of the value.
///
/// The returned `BitArray` is always exactly 8 bytes long.
pub fn to_bytes_le(u: Uint64) -> BitArray {
  u.bytes_le
}

/// Attempts to convert the value to an `Int`.
///
/// **Target-specific behavior:**
/// - **Erlang**: Always succeeds (arbitrary precision integers)
/// - **JavaScript**: Succeeds only if the value is ≤ `Number.MAX_SAFE_INTEGER` (2^53 - 1)
///
/// Returns `Error(Nil)` if the value cannot be safely represented on the current target.
///
/// For values that may exceed safe integer limits on JavaScript, consider using
/// `to_string()` instead, which always preserves the full numeric value.
pub fn to_int(u: Uint64) -> Result(Int, Nil) {
  do_to_int(u.bytes_le)
}

@external(javascript, "./int64_ffi.mjs", "uint64LeToInt")
fn do_to_int(bytes_le: BitArray) -> Result(Int, Nil) {
  let assert <<u:unsigned-little-size(64)>> = bytes_le
  Ok(u)
}

/// Converts the value to its base-10 string representation.
///
/// This function always succeeds and preserves the full numeric value on all
/// targets. It is the recommended way to serialize or display a `Uint64`,
/// especially on the JavaScript target where large integers cannot be
/// represented natively.
pub fn to_string(u: Uint64) -> String {
  do_to_string(u.bytes_le)
}

@external(javascript, "./int64_ffi.mjs", "uint64LeToString")
fn do_to_string(bytes_le: BitArray) -> String {
  let assert <<u:unsigned-little-size(64)>> = bytes_le
  int.to_string(u)
}
