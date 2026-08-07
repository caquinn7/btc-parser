import gleam/bit_array

/// An unsigned 256-bit integer stored as exactly 32 little-endian bytes.
///
/// This byte-backed representation preserves every unsigned 256-bit value
/// exactly across the Erlang and JavaScript targets without converting it to a
/// target-native integer.
pub opaque type Uint256 {
  Uint256(bytes_le: BitArray)
}

/// An error that occurred while constructing a `Uint256` from a `BitArray`.
pub type FromBytesError {
  /// The provided byte sequence did not contain exactly 32 bytes.
  ///
  /// The contained value is the measured byte count.
  InvalidByteCount(Int)
}

/// Constructs a `Uint256` from exactly 32 little-endian bytes.
///
/// Returns an error if the provided `BitArray` does not contain exactly 32 bytes.
///
/// This function does not interpret the bytes beyond validating their length.
/// They are stored verbatim, so zero and values with the most-significant bit
/// set are both accepted.
///
/// ## Examples
///
/// ```gleam
/// from_bytes_le(<<0:256>>)
/// // -> Ok(Uint256) representing 0
///
/// from_bytes_le(<<1, 0:248>>)
/// // -> Ok(Uint256) representing 1
///
/// from_bytes_le(<<1, 2, 3>>)
/// // -> Error(InvalidByteCount(3))
/// ```
pub fn from_bytes_le(bytes: BitArray) -> Result(Uint256, FromBytesError) {
  case bytes {
    <<_:bytes-32>> -> Ok(Uint256(bytes))
    _ -> Error(InvalidByteCount(bit_array.byte_size(bytes)))
  }
}

/// Returns the raw little-endian byte representation of the value.
///
/// The returned `BitArray` is always exactly 32 bytes long.
pub fn to_bytes_le(u: Uint256) -> BitArray {
  u.bytes_le
}

/// Returns whether every bit in the unsigned 256-bit value is zero.
pub fn is_zero(u: Uint256) -> Bool {
  to_bytes_le(u) == <<0:256>>
}
