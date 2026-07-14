//// Test-only helpers for constructing canonical Bitcoin wire encodings.

import gleam/bit_array
import gleam/string

/// Encode a non-negative integer as a minimal CompactSize byte array.
pub fn compact_size(value: Int) -> BitArray {
  case value {
    _ if value < 0 -> panic as "compact_size: negative values not supported"
    _ if value <= 252 -> <<value:size(8)>>
    _ if value <= 65_535 -> <<0xFD, value:little-size(16)>>
    _ if value <= 4_294_967_295 -> <<0xFE, value:little-size(32)>>
    _ -> <<0xFF, value:little-size(64)>>
  }
}

pub fn get_display_hex(bytes: BitArray) -> String {
  bytes
  |> reverse_bytes
  |> bit_array.base16_encode
  |> string.lowercase
}

pub fn reverse_bytes(bits: BitArray) -> BitArray {
  do_reverse_bytes(bits, <<>>)
}

fn do_reverse_bytes(bits: BitArray, acc: BitArray) -> BitArray {
  case bits {
    <<>> -> acc
    <<byte, rest:bits>> -> do_reverse_bytes(rest, <<byte, acc:bits>>)
    _ -> panic as "input is not byte-aligned"
  }
}
