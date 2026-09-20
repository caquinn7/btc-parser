//// Display-format helpers for ordinary Bitcoin byte data.

import gleam/bit_array
import gleam/string

/// Convert arbitrary bytes to lowercase hexadecimal without reversing them.
pub fn hex(bytes: BitArray) -> String {
  bytes
  |> bit_array.base16_encode
  |> string.lowercase
}
