//// A fixed-width hash value used throughout Bitcoin wire data.

import gleam/bit_array
import gleam/string

/// A generic 256-bit hash value stored in Bitcoin wire order.
///
/// This name describes the value's width, not the single-SHA-256 algorithm.
/// Bitcoin serializes these hashes in little-endian byte order, which is the
/// order this type stores and exposes through `to_bytes_le`.
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

/// Construct a `Hash256` from exactly 32 little-endian bytes.
///
/// Returns an error if the supplied value does not contain exactly 256 bits.
/// The bytes are stored verbatim without interpreting the hash's semantic role.
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

/// Return the raw little-endian byte representation of a hash.
///
/// The returned `BitArray` is always exactly 32 bytes long and uses the same
/// byte order found in Bitcoin wire data.
pub fn to_bytes_le(hash: Hash256) -> BitArray {
  hash.bytes_le
}

/// Format a hash using Bitcoin's conventional lowercase display notation.
///
/// Bitcoin displays identifiers such as txids and block hashes with the
/// wire-order bytes reversed. The returned string therefore contains exactly
/// 64 lowercase hexadecimal characters.
pub fn to_display_hex(hash: Hash256) -> String {
  hash.bytes_le
  |> reverse_bytes
  |> bit_array.base16_encode
  |> string.lowercase
}

fn reverse_bytes(bytes: BitArray) -> BitArray {
  bytes
  |> collect_reversed_bytes([])
  |> bit_array.concat
}

fn collect_reversed_bytes(
  bytes: BitArray,
  reversed_bytes: List(BitArray),
) -> List(BitArray) {
  case bytes {
    <<>> -> reversed_bytes

    <<byte, rest:bits>> ->
      collect_reversed_bytes(rest, [<<byte>>, ..reversed_bytes])

    // `Hash256` guarantees byte alignment, so this branch is unreachable.
    _ -> panic as "expected byte-aligned input"
  }
}
