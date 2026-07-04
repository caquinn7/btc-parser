import btc_parser/internal/fixed_int/uint64.{type Uint64}
import btc_parser/internal/reader.{type Reader}
import gleam/result

/// An error that occurred while reading a CompactSize-encoded integer.
pub type ReadError {
  /// Indicates insufficient bytes were available in the reader to decode the CompactSize value.
  ///
  /// This occurs when the prefix indicates a certain number of bytes should follow,
  /// but the reader does not have enough remaining bytes to read them.
  ReaderError(reader.ReaderError)

  /// A CompactSize was encoded using more bytes than necessary for its value,
  /// violating Bitcoin’s minimal encoding rules
  ///
  /// `encoded` is the length of the encoded CompactSize in bytes, and `value` is the
  /// decoded integer value.
  NonMinimalCompactSize(encoded: Int, value: Int)
}

/// Read a CompactSize-encoded integer from the reader.
///
/// CompactSize is a variable-length encoding used in Bitcoin transactions to efficiently
/// represent unsigned integers. The encoding uses 1, 3, 5, or 9 bytes depending on the value:
///
/// ------------------------------------------------------------------------------
/// | First byte | Meaning                  | Total bytes | Value range          |
/// | ---------- | ------------------------ | ----------- | -------------------- |
/// | < 0xfd     | value is the byte itself | 1           | 0–252                |
/// | 0xfd       | next **2 bytes** (LE)    | 3           | 253–65,535           |
/// | 0xfe       | next **4 bytes** (LE)    | 5           | 65,536–4,294,967,295 |
/// | 0xff       | next **8 bytes** (LE)    | 9           | ≥ 4,294,967,296      |
/// ------------------------------------------------------------------------------
///
/// Bitcoin enforces minimal encoding: values must use the shortest possible representation.
/// This function returns `NonMinimalCompactSize` if a value is encoded with more bytes
/// than necessary.
///
/// ## Returns
///
/// - `Ok(#(reader, value))` - The updated reader and the decoded U64 value
/// - `Error(ReaderError(_))` - Not enough bytes available to read the encoded value
/// - `Error(NonMinimalCompactSize(_, _))` - The value used non-minimal encoding
pub fn read(reader: Reader) -> Result(#(Reader, Uint64), ReadError) {
  use #(reader, prefix) <- result.try(read_from(reader, reader.read_u8))

  case prefix {
    0xFD -> {
      use #(reader, value) <- result.try(read_from(reader, reader.read_u16_le))

      case value < 253 {
        True -> Error(NonMinimalCompactSize(encoded: 3, value: value))
        False -> {
          let assert Ok(u) = uint64.from_bytes_le(<<value:64-little>>)
          Ok(#(reader, u))
        }
      }
    }

    0xFE -> {
      use #(reader, value) <- result.try(read_from(reader, reader.read_u32_le))

      case value < 65_536 {
        True -> Error(NonMinimalCompactSize(encoded: 5, value:))
        False -> {
          let assert Ok(u) = uint64.from_bytes_le(<<value:64-little>>)
          Ok(#(reader, u))
        }
      }
    }

    0xFF -> {
      use #(reader, bytes) <- result.try(
        read_from(reader, reader.read_bytes(_, 8)),
      )

      let assert <<lower:32-unsigned-little, upper:32-unsigned-little>> = bytes

      // If upper 32 bits are all zeros, the value fits in 32 bits
      // and should have used the 0xFE prefix instead
      case upper == 0 {
        True -> Error(NonMinimalCompactSize(encoded: 9, value: lower))
        False -> {
          let assert Ok(u) = uint64.from_bytes_le(bytes)
          Ok(#(reader, u))
        }
      }
    }

    _ -> {
      let assert Ok(value) =
        uint64.from_bytes_le(<<prefix, 0, 0, 0, 0, 0, 0, 0>>)

      Ok(#(reader, value))
    }
  }
}

fn read_from(
  reader: Reader,
  read_fn: fn(Reader) -> Result(#(Reader, a), reader.ReaderError),
) -> Result(#(Reader, a), ReadError) {
  reader
  |> read_fn
  |> result.map_error(ReaderError)
}

/// Encode an unsigned 64-bit integer as a CompactSize byte array.
///
/// This helper matches the Bitcoin CompactSize encoding rules:
/// - 0-252: single byte
/// - 253-65535: 0xFD followed by 2 bytes (little-endian)
/// - 65536-4294967295: 0xFE followed by 4 bytes (little-endian)
/// - 4294967296+: 0xFF followed by 8 bytes (little-endian)
pub fn write(value: Uint64) -> BitArray {
  case uint64.to_int(value) {
    Ok(v) if v <= 252 -> <<v:8>>
    Ok(v) if v <= 65_535 -> <<0xFD, v:16-little>>
    Ok(v) if v <= 4_294_967_295 -> <<0xFE, v:32-little>>
    Ok(_) | Error(Nil) -> {
      // Value is > 4_294_967_295 or too large for Int on JS target
      let bytes = uint64.to_bytes_le(value)
      <<0xFF, bytes:bits>>
    }
  }
}
