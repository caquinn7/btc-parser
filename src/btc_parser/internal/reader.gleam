import gleam/bit_array

/// A sequential reader for parsing byte-aligned binary data.
///
/// The reader validates alignment when it is constructed, then retains the
/// input while tracking the number of bytes consumed with a cursor.
pub opaque type Reader {
  Reader(bytes: BitArray, offset: Int)
}

/// An error that occurred while constructing a `Reader`.
pub type ReaderError {
  /// The reader input does not contain a whole number of bytes.
  ///
  /// The wrapped value is the exact total number of bits in the input.
  NonByteAlignedInput(bit_count: Int)
}

/// Creates a new `Reader` from a byte-aligned `BitArray` with offset set to `0`.
///
/// Returns `NonByteAlignedInput` when the input does not contain a whole number
/// of bytes.
pub fn new(bytes: BitArray) -> Result(Reader, ReaderError) {
  let bit_count = bit_array.bit_size(bytes)
  case bit_count % 8 == 0 {
    True -> Ok(Reader(bytes, 0))
    False -> Error(NonByteAlignedInput(bit_count))
  }
}

/// Advances the reader cursor by the given number of bytes.
///
/// Call this only after a successful bounds and alignment check.
fn advance_reader(reader: Reader, bytes_consumed: Int) -> Reader {
  Reader(bytes: reader.bytes, offset: reader.offset + bytes_consumed)
}

/// Returns a lazy slice of all remaining unconsumed bytes from the reader.
pub fn get_remaining(reader: Reader) -> BitArray {
  // Safe: Reader is opaque, starts at offset zero, and advances only after a
  // successful match proves enough complete bytes remain. Reader construction
  // guarantees the bits suffix is byte-aligned.
  let offset = reader.offset
  let assert <<_:bytes-size(offset), remaining:bits>> = reader.bytes
  remaining
}

/// Returns the number of unconsumed bytes remaining in the reader.
pub fn bytes_remaining(reader: Reader) -> Int {
  bit_array.byte_size(reader.bytes) - reader.offset
}

/// Returns the number of bytes consumed
/// from the start of the reader's input.
pub fn get_offset(reader: Reader) -> Int {
  reader.offset
}

/// An error that occurred during a `Reader` operation.
pub type OperationError {
  /// The number of bytes requested to read is invalid.
  ///
  /// This error occurs when a negative value is provided as the byte count
  /// for a read operation. Byte counts must always be non-negative.
  ///
  /// The `Int` value represents the invalid byte count that was requested.
  InvalidReadCount(Int)

  /// The reader reached the end of the input before enough bytes were available
  /// to complete the current read operation. Both values are byte counts.
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
) -> Result(#(Reader, BitArray), OperationError) {
  use count <- validate_count(count)
  let offset = reader.offset

  case reader.bytes {
    <<_:bytes-size(offset), bytes:bytes-size(count), _:bytes>> ->
      Ok(#(advance_reader(reader, count), bytes))

    _ -> Error(eof_error(reader, count))
  }
}

/// Advances the reader by the specified number of bytes without returning them.
///
/// Returns the updated reader, or an error if there are insufficient bytes remaining.
pub fn skip_bytes(
  reader: Reader,
  count: Int,
) -> Result(Reader, OperationError) {
  use count <- validate_count(count)
  let offset = reader.offset

  case reader.bytes {
    <<_:bytes-size(offset), _:bytes-size(count), _:bytes>> ->
      Ok(advance_reader(reader, count))

    _ -> Error(eof_error(reader, count))
  }
}

/// Reads the specified number of bytes from the reader without advancing it.
///
/// Returns the bytes read, or an error if there are insufficient bytes remaining.
/// The reader position remains unchanged.
pub fn peek_bytes(
  reader: Reader,
  count: Int,
) -> Result(BitArray, OperationError) {
  use count <- validate_count(count)
  let offset = reader.offset

  case reader.bytes {
    <<_:bytes-size(offset), bytes:bytes-size(count), _:bytes>> -> Ok(bytes)
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
) -> Result(#(Reader, Reader), OperationError) {
  use count <- validate_count(count)
  let offset = reader.offset

  case reader.bytes {
    <<_:bytes-size(offset), bytes:bytes-size(count), _:bytes>> -> {
      let advanced_reader = advance_reader(reader, count)
      let assert Ok(reader_with_taken_bytes) = new(bytes)

      Ok(#(advanced_reader, reader_with_taken_bytes))
    }

    _ -> Error(eof_error(reader, count))
  }
}

fn validate_count(
  count: Int,
  on_success: fn(Int) -> Result(a, OperationError),
) -> Result(a, OperationError) {
  case count < 0 {
    True -> Error(InvalidReadCount(count))
    False -> on_success(count)
  }
}

/// Reads an 8-bit unsigned integer.
///
/// Returns the updated reader along with the integer value, or an error if
/// there are fewer than 1 bytes remaining.
pub fn read_u8(reader: Reader) -> Result(#(Reader, Int), OperationError) {
  read_uint_le(reader, 1)
}

/// Reads a 16-bit unsigned integer in little-endian format.
///
/// Returns the updated reader along with the integer value, or an error if
/// there are fewer than 2 bytes remaining.
pub fn read_u16_le(reader: Reader) -> Result(#(Reader, Int), OperationError) {
  read_uint_le(reader, 2)
}

/// Reads a 32-bit unsigned integer in little-endian format.
///
/// Returns the updated reader along with the integer value, or an error if
/// there are fewer than 4 bytes remaining.
pub fn read_u32_le(reader: Reader) -> Result(#(Reader, Int), OperationError) {
  read_uint_le(reader, 4)
}

/// Reads a 32-bit signed integer in little-endian format.
///
/// Returns the updated reader along with the integer value, or an error if
/// there are fewer than 4 bytes remaining.
pub fn read_i32_le(reader: Reader) -> Result(#(Reader, Int), OperationError) {
  read_int_le(reader, 4)
}

/// Helper function for reading unsigned little-endian integers of various sizes.
fn read_uint_le(
  reader: Reader,
  size: Int,
) -> Result(#(Reader, Int), OperationError) {
  let offset = reader.offset

  case reader.bytes {
    <<_:bytes-size(offset), u:unsigned-little-size(size)-unit(8), _:bytes>> ->
      Ok(#(advance_reader(reader, size), u))

    _ -> Error(eof_error(reader, size))
  }
}

/// Helper function for reading signed little-endian integers of various sizes.
fn read_int_le(
  reader: Reader,
  size: Int,
) -> Result(#(Reader, Int), OperationError) {
  let offset = reader.offset

  case reader.bytes {
    <<_:bytes-size(offset), i:signed-little-size(size)-unit(8), _:bytes>> ->
      Ok(#(advance_reader(reader, size), i))

    _ -> Error(eof_error(reader, size))
  }
}
