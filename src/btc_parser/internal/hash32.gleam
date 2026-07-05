import gleam/bit_array

/// A 32-byte hash used as a Bitcoin transaction identifier.
///
/// Bitcoin encodes these hashes in little-endian byte order on the wire,
/// which is the order this type stores and exposes them in.
pub opaque type Hash32 {
  Hash32(bytes_le: BitArray)
}

/// An error that occurred while constructing a `Hash32`.
pub type Hash32Error {
  /// The provided byte sequence does not contain exactly 32 bytes.
  InvalidByteCount(Int)
}

/// Constructs a `Hash32` from exactly 32 little-endian bytes.
///
/// Returns an error if the provided `BitArray` does not contain exactly 32 bytes.
///
/// ## Examples
///
/// ```gleam
/// from_bytes_le(<<0:size(256)>>)
/// // -> Ok(Hash32) representing an all-zero hash
///
/// from_bytes_le(<<1, 2, 3>>)
/// // -> Error(InvalidByteCount(3))
/// ```
pub fn from_bytes_le(bytes: BitArray) -> Result(Hash32, Hash32Error) {
  case bytes {
    <<_:bytes-size(32)>> -> Ok(Hash32(bytes))
    _ -> Error(InvalidByteCount(bit_array.byte_size(bytes)))
  }
}

/// Returns the raw little-endian byte representation of the value.
///
/// The returned `BitArray` is always exactly 32 bytes long.
pub fn to_bytes_le(x: Hash32) -> BitArray {
  x.bytes_le
}
