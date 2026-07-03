import gleam/bit_array

/// A sequential reader for parsing binary data.
///
/// Maintains the current position while reading through a `BitArray`,
/// tracking both the remaining input and the number of bytes consumed.
pub opaque type Reader {
  Reader(remaining: BitArray, offset: Int)
}

/// Creates a new `Reader` from the given `BitArray` with offset set to `0`.
pub fn new(bytes: BitArray) -> Reader {
  Reader(bytes, 0)
}

/// Advances the reader by the given number of bytes, updating both the
/// remaining input and the offset position.
fn advance_reader(
  reader: Reader,
  bytes_consumed: Int,
  remaining: BitArray,
) -> Reader {
  Reader(remaining:, offset: reader.offset + bytes_consumed)
}

/// Returns all remaining unconsumed bytes from the reader.
pub fn get_remaining(reader: Reader) -> BitArray {
  reader.remaining
}

/// Returns the number of unconsumed bytes remaining in the reader.
pub fn bytes_remaining(reader: Reader) -> Int {
  bit_array.byte_size(reader.remaining)
}

/// Returns the number of bytes consumed
/// from the start of the reader's input.
pub fn get_offset(reader: Reader) -> Int {
  reader.offset
}

/// An error that occurred during a `Reader` operation.
pub type ReaderError {
  /// The number of bytes requested to read is invalid.
  ///
  /// This error occurs when a negative value is provided as the byte count
  /// for a read operation. Byte counts must always be non-negative.
  ///
  /// The `Int` value represents the invalid byte count that was requested.
  InvalidReadCount(Int)

  /// The reader reached the end of the input before enough bytes were available
  /// to complete the current read operation.
  UnexpectedEof(bytes_needed: Int, remaining: Int)
}

fn eof_error(reader: Reader, bytes_needed: Int) {
  UnexpectedEof(bytes_needed:, remaining: bytes_remaining(reader))
}

/// Read the specified number of bytes from the reader.
///
/// Returns the updated reader along with the bytes read, or an error if
/// there are insufficient bytes remaining.
pub fn read_bytes(
  reader: Reader,
  count: Int,
) -> Result(#(Reader, BitArray), ReaderError) {
  use count <- validate_count(count)

  case reader.remaining {
    <<bytes:bytes-size(count), rest:bytes>> ->
      Ok(#(advance_reader(reader, count, rest), bytes))

    _ -> Error(eof_error(reader, count))
  }
}

/// Advances the reader by the specified number of bytes without returning them.
///
/// Returns the updated reader, or an error if there are insufficient bytes remaining.
pub fn skip_bytes(reader: Reader, count: Int) -> Result(Reader, ReaderError) {
  use count <- validate_count(count)

  case reader.remaining {
    <<_:bytes-size(count), rest:bytes>> ->
      Ok(advance_reader(reader, count, rest))

    _ -> Error(eof_error(reader, count))
  }
}

/// Reads the specified number of bytes from the reader without advancing it.
///
/// Returns the bytes read, or an error if there are insufficient bytes remaining.
/// The reader position remains unchanged.
pub fn peek_bytes(reader: Reader, count: Int) -> Result(BitArray, ReaderError) {
  use count <- validate_count(count)

  case reader.remaining {
    <<bytes:bytes-size(count), _:bytes>> -> Ok(bytes)
    _ -> Error(eof_error(reader, count))
  }
}

/// Creates a new reader containing the specified number of bytes from the current position.
///
/// Returns the updated reader (advanced past the taken bytes) along with a new reader
/// containing only the taken bytes, or an error if there are insufficient bytes remaining.
pub fn take_bytes(
  reader: Reader,
  count: Int,
) -> Result(#(Reader, Reader), ReaderError) {
  use count <- validate_count(count)

  case reader.remaining {
    <<bytes:bytes-size(count), rest:bytes>> ->
      Ok(#(advance_reader(reader, count, rest), new(bytes)))

    _ -> Error(eof_error(reader, count))
  }
}

fn validate_count(
  count: Int,
  on_success: fn(Int) -> Result(a, ReaderError),
) -> Result(a, ReaderError) {
  case count < 0 {
    True -> Error(InvalidReadCount(count))
    False -> on_success(count)
  }
}

/// Reads an 8-bit unsigned integer.
///
/// Returns the updated reader along with the integer value, or an error if
/// there are fewer than 1 bytes remaining.
pub fn read_u8(reader: Reader) -> Result(#(Reader, Int), ReaderError) {
  read_uint_le(reader, 8)
}

/// Reads a 16-bit unsigned integer in little-endian format.
///
/// Returns the updated reader along with the integer value, or an error if
/// there are fewer than 2 bytes remaining.
pub fn read_u16_le(reader: Reader) -> Result(#(Reader, Int), ReaderError) {
  read_uint_le(reader, 16)
}

/// Reads a 32-bit unsigned integer in little-endian format.
///
/// Returns the updated reader along with the integer value, or an error if
/// there are fewer than 4 bytes remaining.
pub fn read_u32_le(reader: Reader) -> Result(#(Reader, Int), ReaderError) {
  read_uint_le(reader, 32)
}

/// Reads a 32-bit signed integer in little-endian format.
///
/// Returns the updated reader along with the integer value, or an error if
/// there are fewer than 4 bytes remaining.
pub fn read_i32_le(reader: Reader) -> Result(#(Reader, Int), ReaderError) {
  read_int_le(reader, 32)
}

/// Helper function for reading unsigned little-endian integers of various sizes.
fn read_uint_le(
  reader: Reader,
  bits_needed: Int,
) -> Result(#(Reader, Int), ReaderError) {
  let bytes_needed = bits_needed / 8

  case reader.remaining {
    <<i:unsigned-little-size(bits_needed), rest:bytes>> ->
      Ok(#(advance_reader(reader, bytes_needed, rest), i))

    _ -> Error(eof_error(reader, bytes_needed))
  }
}

/// Helper function for reading signed little-endian integers of various sizes.
fn read_int_le(
  reader: Reader,
  bits_needed: Int,
) -> Result(#(Reader, Int), ReaderError) {
  let bytes_needed = bits_needed / 8

  case reader.remaining {
    <<i:signed-little-size(bits_needed), rest:bytes>> ->
      Ok(#(advance_reader(reader, bytes_needed, rest), i))

    _ -> Error(eof_error(reader, bytes_needed))
  }
}
