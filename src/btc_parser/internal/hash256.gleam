import gleam/bit_array

/// A generic 256-bit hash value used in Bitcoin wire data.
///
/// This name describes the value's width, not the single-SHA-256 algorithm.
/// Bitcoin encodes these hashes in little-endian byte order on the wire, which
/// is the order this type stores and exposes them in.
pub opaque type Hash256 {
  Hash256(bytes_le: BitArray)
}

/// An error that occurred while constructing a `Hash256`.
pub type Hash256Error {
  /// The input did not contain exactly 256 bits.
  ///
  /// The fields contain the measured and required bit counts, respectively.
  InvalidBitCount(actual: Int, expected: Int)
}

/// Constructs a `Hash256` from exactly 32 little-endian bytes.
///
/// Returns an error if the provided `BitArray` does not contain exactly 32 bytes.
///
/// ## Examples
///
/// ```gleam
/// from_bytes_le(<<0:size(256)>>)
/// // -> Ok(Hash256) representing an all-zero hash
///
/// from_bytes_le(<<1, 2, 3>>)
/// // -> Error(InvalidBitCount(actual: 24, expected: 256))
/// ```
pub fn from_bytes_le(bytes: BitArray) -> Result(Hash256, Hash256Error) {
  case bytes {
    <<_:bytes-size(32)>> -> Ok(Hash256(bytes))
    _ -> Error(InvalidBitCount(bit_array.bit_size(bytes), 256))
  }
}

/// Returns the raw little-endian byte representation of the value.
///
/// The returned `BitArray` is always exactly 32 bytes long.
pub fn to_bytes_le(x: Hash256) -> BitArray {
  x.bytes_le
}
