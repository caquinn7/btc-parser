import gleam/list
import gleam/result
import gleam/string

/// Errors that can occur when converting a hex string to bytes.
pub type HexToBytesError {
  /// The hex string has an odd number of characters. Hex strings must have
  /// an even length since each byte requires two hex characters.
  OddLength
  /// An invalid hex character was encountered at the specified index.
  /// Valid hex characters are: 0-9, a-f, A-F.
  InvalidHexChar(char: String, index: Int)
}

/// Converts a hexadecimal string into a BitArray of bytes.
///
/// Each pair of hex characters (0-9, a-f, A-F) is converted to one byte.
/// The function is case-insensitive.
///
/// ## Examples
///
/// ```gleam
/// hex_to_bytes("48656c6c6f")
/// // -> Ok(<<"Hello":utf8>>)
///
/// hex_to_bytes("deadbeef")
/// // -> Ok(<<0xde, 0xad, 0xbe, 0xef>>)
///
/// hex_to_bytes("")
/// // -> Ok(<<>>)
///
/// hex_to_bytes("abc")
/// // -> Error(OddLength)
///
/// hex_to_bytes("xyz")
/// // -> Error(InvalidHexChar("x", 0))
/// ```
pub fn hex_to_bytes(hex: String) -> Result(BitArray, HexToBytesError) {
  hex
  // Split hex string into individual characters
  |> string.to_graphemes
  // Group into pairs: ["a", "b", "c", "d"] -> [#("a", "b"), #("c","d")]
  |> list.sized_chunk(2)
  |> list.try_map(fn(chunk) {
    case chunk {
      [hi, low] -> Ok(#(hi, low))
      _ -> Error(OddLength)
    }
  })
  // Associate each pair with it's index: [#("a", "b"), #("c","d")] -> [#(0, "a", "b"), #(1, "c","d")]
  |> result.map(
    list.index_map(_, fn(pair, i) {
      let #(hi, low) = pair
      #(i, hi, low)
    }),
  )
  // Convert each pair to a byte
  |> result.try(list.try_map(_, parse_hex_pair))
  // Pack all bytes into a BitArray
  |> result.map(list.fold(_, <<>>, fn(acc, byte) { <<acc:bits, byte:8>> }))
}

/// Converts a pair of hex characters into a single byte (0..255).
fn parse_hex_pair(
  indexed_pair: #(Int, String, String),
) -> Result(Int, HexToBytesError) {
  let #(chunk_index, a, b) = indexed_pair

  // Convert high nibble character, tracking its position in the original string
  // chunk_index is the pair index, so multiply by 2 to get the character position
  // Example: chunk 1 → chars at positions 2 and 3
  let hi_result =
    a
    |> hex_char_to_nibble
    |> result.map_error(fn(_) { InvalidHexChar(a, chunk_index * 2) })

  // Convert low nibble character, tracking its position in the original string
  // Add 1 to get the second character in the pair
  let lo_result =
    b
    |> hex_char_to_nibble
    |> result.map_error(fn(_) { InvalidHexChar(b, chunk_index * 2 + 1) })

  // Combine the nibbles into a byte: high nibble * 16 + low nibble
  // Example: 'a' (10) and 'b' (11) → 10 * 16 + 11 = 171 (0xab)
  case hi_result, lo_result {
    Ok(hi), Ok(lo) -> Ok(hi * 16 + lo)
    Error(err), _ | _, Error(err) -> Error(err)
  }
}

/// Converts a single hex character (as a 1-char String) into a nibble 0..15.
/// A "nibble" is a group of 4 bits.
fn hex_char_to_nibble(ch: String) -> Result(Int, Nil) {
  case string.lowercase(ch) {
    "0" -> Ok(0)
    "1" -> Ok(1)
    "2" -> Ok(2)
    "3" -> Ok(3)
    "4" -> Ok(4)
    "5" -> Ok(5)
    "6" -> Ok(6)
    "7" -> Ok(7)
    "8" -> Ok(8)
    "9" -> Ok(9)
    "a" -> Ok(10)
    "b" -> Ok(11)
    "c" -> Ok(12)
    "d" -> Ok(13)
    "e" -> Ok(14)
    "f" -> Ok(15)
    _ -> Error(Nil)
  }
}
