import gleam/bit_array
import gleam/string

/// Converts a 32-byte wire-order hash to its conventional display encoding.
pub fn to_display_hex(bytes: BitArray) -> String {
  bytes
  |> reverse_bytes
  |> bit_array.base16_encode
  |> string.lowercase
}

fn reverse_bytes(bytes: BitArray) -> BitArray {
  case bytes {
    <<>> -> <<>>
    _ -> do_reverse_bytes(bytes, <<>>)
  }
}

fn do_reverse_bytes(bytes: BitArray, acc: BitArray) -> BitArray {
  case bytes {
    <<>> -> acc
    <<byte, rest:bits>> -> do_reverse_bytes(rest, <<byte, acc:bits>>)
    _ -> panic as "hash must be byte-aligned"
  }
}
