import internal/compact_size.{NonMinimalCompactSize}
import internal/fixed_int/uint64
import internal/reader

// Single-byte encoding (values 0-252)

pub fn read_returns_single_byte_value_test() {
  let initial_reader = reader.new(<<0xFC, 0xAA>>)
  let assert Ok(#(reader, value)) = compact_size.read(initial_reader)
  let assert Ok(expected) = uint64.from_bytes_le(<<0xFC, 0, 0, 0, 0, 0, 0, 0>>)

  assert value == expected
  assert reader.get_offset(reader) == 1
  assert reader.get_remaining(reader) == <<0xAA>>
}

// 0xfd prefix (2-byte encoding, values 253-65535)

pub fn read_accepts_minimal_fd_threshold_value_test() {
  // Value 253 is the minimum that requires 0xfd prefix
  let initial_reader = reader.new(<<0xFD, 0xFD, 0x00>>)
  let assert Ok(#(reader, value)) = compact_size.read(initial_reader)
  let assert Ok(expected) = uint64.from_bytes_le(<<0xFD, 0, 0, 0, 0, 0, 0, 0>>)

  assert value == expected
  assert reader.get_offset(reader) == 3
}

pub fn read_reads_fd_prefixed_value_test() {
  // 0xfd prefix with 0x00fd (253) little-endian payload
  let initial_reader = reader.new(<<0xFD, 0xFD, 0x00, 0x99>>)
  let assert Ok(#(reader, value)) = compact_size.read(initial_reader)
  let assert Ok(expected) = uint64.from_bytes_le(<<0xFD, 0, 0, 0, 0, 0, 0, 0>>)

  assert value == expected
  assert reader.get_offset(reader) == 3
  assert reader.get_remaining(reader) == <<0x99>>
}

pub fn read_errors_on_non_minimal_fd_encoding_test() {
  // Value 252 must use the single-byte form; a 0xfd prefix is non-minimal.
  let initial_reader = reader.new(<<0xFD, 0xFC, 0x00>>)

  assert compact_size.read(initial_reader)
    == Error(NonMinimalCompactSize(encoded: 3, value: 252))
}

pub fn read_errors_on_partial_fd_read_test() {
  // 0xfd prefix requires 2 bytes, but only 1 is available
  let initial_reader = reader.new(<<0xFD, 0x01>>)

  assert compact_size.read(initial_reader)
    == Error(
      compact_size.ReaderError(reader.UnexpectedEof(
        bytes_needed: 2,
        remaining: 1,
      )),
    )
}

// 0xfe prefix (4-byte encoding, values 65536-4294967295)

pub fn read_accepts_minimal_fe_threshold_value_test() {
  // Value 65536 is the minimum that requires 0xfe prefix
  let initial_reader = reader.new(<<0xFE, 0x00, 0x00, 0x01, 0x00>>)
  let assert Ok(#(reader, value)) = compact_size.read(initial_reader)
  let assert Ok(expected) =
    uint64.from_bytes_le(<<0x00, 0x00, 0x01, 0x00, 0, 0, 0, 0>>)

  assert value == expected
  assert reader.get_offset(reader) == 5
}

pub fn read_reads_fe_prefixed_value_test() {
  // 0xfe prefix with 0x00010000 (65_536) little-endian payload
  let initial_reader = reader.new(<<0xFE, 0x00, 0x00, 0x01, 0x00, 0x01>>)
  let assert Ok(#(reader, value)) = compact_size.read(initial_reader)
  let assert Ok(expected) =
    uint64.from_bytes_le(<<0x00, 0x00, 0x01, 0x00, 0, 0, 0, 0>>)

  assert value == expected
  assert reader.get_offset(reader) == 5
  assert reader.get_remaining(reader) == <<0x01>>
}

pub fn read_errors_on_non_minimal_fe_encoding_test() {
  // Value 65535 must use 0xfd prefix; a 0xfe prefix is non-minimal.
  let initial_reader = reader.new(<<0xFE, 0xFF, 0xFF, 0x00, 0x00>>)

  assert compact_size.read(initial_reader)
    == Error(NonMinimalCompactSize(encoded: 5, value: 65_535))
}

pub fn read_errors_on_partial_fe_read_test() {
  let initial_reader = reader.new(<<0xFE, 0x01, 0x02>>)

  assert compact_size.read(initial_reader)
    == Error(
      compact_size.ReaderError(reader.UnexpectedEof(
        bytes_needed: 4,
        remaining: 2,
      )),
    )
}

// 0xff prefix (8-byte encoding, values 4294967296+)

pub fn read_accepts_minimal_ff_threshold_value_test() {
  // Value 0x100000000 is the minimum that requires 0xff prefix
  let initial_reader =
    reader.new(<<0xFF, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00>>)
  let assert Ok(#(reader, value)) = compact_size.read(initial_reader)
  let assert Ok(expected) =
    uint64.from_bytes_le(<<0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00>>)

  assert value == expected
  assert reader.get_offset(reader) == 9
}

pub fn read_reads_ff_prefixed_value_test() {
  let max_value_bytes = <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>
  let initial_reader = reader.new(<<0xFF, max_value_bytes:bits>>)
  let assert Ok(#(reader, value)) = compact_size.read(initial_reader)
  let assert Ok(expected) = uint64.from_bytes_le(max_value_bytes)

  assert value == expected
  assert reader.get_offset(reader) == 9
  assert reader.get_remaining(reader) == <<>>
}

pub fn read_errors_on_non_minimal_ff_encoding_test() {
  // Value with upper 32 bits zero must use a shorter encoding.
  let initial_reader =
    reader.new(<<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00>>)

  assert compact_size.read(initial_reader)
    == Error(NonMinimalCompactSize(encoded: 9, value: 4_294_967_295))
}

pub fn read_errors_on_partial_ff_read_test() {
  // 0xff prefix requires 8 bytes, but only 7 are available
  let initial_reader =
    reader.new(<<0xFF, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07>>)

  assert compact_size.read(initial_reader)
    == Error(
      compact_size.ReaderError(reader.UnexpectedEof(
        bytes_needed: 8,
        remaining: 7,
      )),
    )
}
