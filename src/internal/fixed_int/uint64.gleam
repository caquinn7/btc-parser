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

/// Error that can occur when constructing a `Uint64` from a `BitArray`.
pub type FromBytesError {
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
pub fn from_bytes_le(bytes: BitArray) -> Result(Uint64, FromBytesError) {
  case bytes {
    <<_:bytes-8>> -> Ok(Uint64(bytes))
    _ -> Error(InvalidByteCount(bit_array.byte_size(bytes)))
  }
}

/// Error that can occur when constructing a `Uint64` from an `Int`.
pub type FromIntError {
  /// The value is negative and cannot be represented as an unsigned integer.
  NegativeValue
  /// The value is outside JavaScript's safe integer range.
  UnsafeInteger
  /// The value is greater than the maximum unsigned 64-bit integer.
  ExceedsUint64
}

/// Constructs a `Uint64` from a Gleam `Int`.
///
/// **Target-specific behavior:**
/// - **Erlang**: Returns `Error(NegativeValue)` for negative values and
///   `Error(ExceedsUint64)` for values greater than 2^64 - 1.
/// - **JavaScript**: Returns `Error(NegativeValue)` for negative values and
///   `Error(UnsafeInteger)` for non-negative values greater than
///   `Number.MAX_SAFE_INTEGER` (2^53 - 1), which prevents encoding values that
///   may have already lost precision.
///
/// ## Examples
///
/// ```gleam
/// from_int(42)
/// // -> Ok(Uint64) representing 42
///
/// from_int(-1)
/// // -> Error(NegativeValue)
///
/// // On Erlang:
/// from_int(18_446_744_073_709_551_616)  // 2^64, exceeds max
/// // -> Error(ExceedsUint64)
///
/// // On JavaScript:
/// from_int(9_007_199_254_740_992)  // 2^53, exceeds safe range
/// // -> Error(UnsafeInteger)
/// ```
pub fn from_int(i: Int) -> Result(Uint64, FromIntError) {
  case i < 0 {
    True -> Error(NegativeValue)
    False -> do_from_non_negative_int(i)
  }
}

fn do_from_non_negative_int(i: Int) -> Result(Uint64, FromIntError) {
  i
  |> do_from_int
  |> result.map(fn(bytes) {
    let assert Ok(u64) = from_bytes_le(bytes)
    u64
  })
  |> result.map_error(fn(_) {
    case running_on_javascript() {
      True -> UnsafeInteger
      False -> ExceedsUint64
    }
  })
}

@external(javascript, "./fixed_int_ffi.mjs", "runningOnJavaScript")
fn running_on_javascript() -> Bool {
  False
}

@external(javascript, "./fixed_int_ffi.mjs", "uint64FromInt")
fn do_from_int(i: Int) -> Result(BitArray, Nil) {
  // On Erlang, integers are arbitrary precision, so we must check bounds.
  // The valid range for unsigned 64-bit is [0, 2^64 - 1].
  case 0 <= i && i <= 18_446_744_073_709_551_615 {
    True -> Ok(<<i:64-little>>)
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

@external(javascript, "./fixed_int_ffi.mjs", "uint64LeToInt")
fn do_to_int(bytes_le: BitArray) -> Result(Int, Nil) {
  bytes_le
  |> decode_uint64_le
  |> Ok
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

@external(javascript, "./fixed_int_ffi.mjs", "uint64LeToString")
fn do_to_string(bytes_le: BitArray) -> String {
  bytes_le
  |> decode_uint64_le
  |> int.to_string
}

fn decode_uint64_le(bytes_le: BitArray) -> Int {
  // `<<u:64-unsigned-little>>` would be simpler, but Gleam warns about
  // truncation on JavaScript even though this fallback only runs on Erlang.

  let assert <<b0, b1, b2, b3, b4, b5, b6, b7>> = bytes_le

  let acc = b7 * 256 + b6
  let acc = acc * 256 + b5
  let acc = acc * 256 + b4
  let acc = acc * 256 + b3
  let acc = acc * 256 + b2
  let acc = acc * 256 + b1
  acc * 256 + b0
}
