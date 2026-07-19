//// Shared helpers for mapping low-level decode failures and exact integer values
//// into domain-owned decode errors.

import btc_parser/internal/compact_size.{NonMinimalCompactSize, ReaderError}
import btc_parser/internal/fixed_int/uint64.{type Uint64}
import btc_parser/internal/reader.{InvalidReadCount, UnexpectedEof}
import gleam/int
import gleam/result

/// Map a `ReaderError` into a caller-owned decode error type.
///
/// `UnexpectedEof` is converted with the supplied callback so transaction,
/// block, and future domains can keep their own public error variants.
///
/// `InvalidReadCount` represents an internal invariant violation and PANICS
/// with a consistent message.
pub fn map_reader_error(
  reader_error: reader.ReaderError,
  unexpected_eof: fn(Int, Int) -> e,
) -> e {
  case reader_error {
    InvalidReadCount(i) ->
      panic as {
        "tried to read an invalid number of bytes: " <> int.to_string(i) <> "."
      }

    UnexpectedEof(bytes_needed:, remaining:) ->
      unexpected_eof(bytes_needed, remaining)
  }
}

/// Map a CompactSize read error into a caller-owned decode error type.
///
/// Reader failures are delegated to `reader_error`.
///
/// Non-minimal CompactSize encodings are converted with the supplied
/// callback so the caller can attach its own public error variant.
pub fn map_compact_size_error(
  read_error: compact_size.ReadError,
  unexpected_eof: fn(Int, Int) -> e,
  non_minimal_encoding: fn(Int, Int) -> e,
) -> e {
  case read_error {
    ReaderError(reader_err) -> map_reader_error(reader_err, unexpected_eof)
    NonMinimalCompactSize(encoded_size:, value:) ->
      non_minimal_encoding(encoded_size, value)
  }
}

/// Convert a byte-backed unsigned 64-bit value to `Int`.
///
/// If the value cannot be represented as an `Int` on the current target, the
/// original value is converted to a decimal string and passed to the supplied
/// callback.
pub fn uint64_to_int(
  value: Uint64,
  integer_out_of_range: fn(String) -> e,
) -> Result(Int, e) {
  value
  |> uint64.to_int
  |> result.map_error(fn(_) {
    value
    |> uint64.to_string
    |> integer_out_of_range
  })
}
