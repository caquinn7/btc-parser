//// Display-format helpers for Bitcoin's wire-order hashes.

import gleam/bit_array
import gleam/string

/// Convert a wire-order hash to conventional lowercase display hex.
pub fn hash(bytes: BitArray) -> String {
  bytes
  |> reverse_bytes
  |> bit_array.base16_encode
  |> string.lowercase
}

/// Convert arbitrary bytes to lowercase hexadecimal without reversing them.
pub fn hex(bytes: BitArray) -> String {
  bytes
  |> bit_array.base16_encode
  |> string.lowercase
}

fn reverse_bytes(bytes: BitArray) -> BitArray {
  do_reverse_bytes(bytes, <<>>)
}

fn do_reverse_bytes(bytes: BitArray, reversed: BitArray) -> BitArray {
  case bytes {
    <<>> -> reversed
    <<byte, rest:bits>> -> do_reverse_bytes(rest, <<byte, reversed:bits>>)
    _ -> reversed
  }
}
