import internal/reader.{InvalidReadCount, UnexpectedEof}

// new

pub fn new_creates_reader_with_zero_offset_test() {
  let reader = reader.new(<<0x01, 0x02>>)
  assert reader.get_offset(reader) == 0
  assert reader.bytes_remaining(reader) == 2
}

// get_remaining

pub fn get_remaining_returns_all_remaining_bytes_test() {
  let reader = reader.new(<<0x01, 0x02, 0x03>>)
  assert reader.get_remaining(reader) == <<0x01, 0x02, 0x03>>

  let assert Ok(#(reader, _)) = reader.read_bytes(reader, 2)
  assert reader.get_remaining(reader) == <<0x03>>
}

// bytes_remaining

pub fn bytes_remaining_returns_remaining_bytes_test() {
  let reader = reader.new(<<0x01, 0x02, 0x03>>)

  let assert Ok(#(reader, _)) = reader.read_bytes(reader, 1)
  assert reader.bytes_remaining(reader) == 2

  let assert Ok(#(reader, _)) = reader.read_bytes(reader, 1)
  assert reader.bytes_remaining(reader) == 1
}

// get_offset

pub fn get_offset_starts_at_zero_test() {
  let reader = reader.new(<<0x01, 0x02, 0x03>>)
  assert reader.get_offset(reader) == 0
}

pub fn get_offset_tracks_position_correctly_test() {
  let reader = reader.new(<<0x01, 0x02, 0x03, 0x04>>)

  let assert Ok(#(reader, _)) = reader.read_bytes(reader, 1)
  assert reader.get_offset(reader) == 1

  let assert Ok(#(reader, _)) = reader.read_bytes(reader, 2)
  assert reader.get_offset(reader) == 3
}

// read_bytes

pub fn read_bytes_returns_invalid_read_count_when_count_is_negative_test() {
  assert reader.read_bytes(reader.new(<<>>), -1) == Error(InvalidReadCount(-1))
}

pub fn read_bytes_reads_0_bytes_when_count_is_zero_test() {
  let reader = reader.new(<<0x02, 0x01>>)
  let assert Ok(#(updated_reader, bytes)) = reader.read_bytes(reader, 0)

  assert updated_reader == reader
  assert bytes == <<>>
  assert reader.get_offset(updated_reader) == 0
}

pub fn read_bytes_returns_eof_when_zero_bytes_test() {
  assert reader.read_bytes(reader.new(<<>>), 1)
    == Error(UnexpectedEof(bytes_needed: 1, remaining: 0))
}

pub fn read_bytes_returns_eof_when_not_enough_bytes_test() {
  assert reader.read_bytes(reader.new(<<0x02, 0x01>>), 3)
    == Error(UnexpectedEof(bytes_needed: 3, remaining: 2))
}

pub fn read_bytes_reads_expected_number_of_bytes_test() {
  let reader = reader.new(<<0x02, 0x01>>)
  let assert Ok(#(reader, bytes)) = reader.read_bytes(reader, 1)

  assert bytes == <<0x02>>
  assert reader.get_offset(reader) == 1
  assert reader.get_remaining(reader) == <<0x01>>
}

pub fn read_bytes_reads_bytes_when_exact_count_test() {
  let reader = reader.new(<<0x02, 0x01>>)
  let assert Ok(#(reader, bytes)) = reader.read_bytes(reader, 2)

  assert bytes == <<0x02, 0x01>>
  assert reader.get_offset(reader) == 2
  assert reader.get_remaining(reader) == <<>>
}

// skip_bytes

pub fn skip_bytes_returns_invalid_read_count_when_count_is_negative_test() {
  assert reader.skip_bytes(reader.new(<<>>), -1) == Error(InvalidReadCount(-1))
}

pub fn skip_bytes_skips_0_bytes_when_count_is_zero_test() {
  let reader = reader.new(<<0x02, 0x01>>)
  let assert Ok(updated_reader) = reader.skip_bytes(reader, 0)

  assert updated_reader == reader
  assert reader.get_offset(updated_reader) == 0
}

pub fn skip_bytes_returns_eof_when_zero_bytes_test() {
  assert reader.skip_bytes(reader.new(<<>>), 1)
    == Error(UnexpectedEof(bytes_needed: 1, remaining: 0))
}

pub fn skip_bytes_returns_eof_when_not_enough_bytes_test() {
  assert reader.skip_bytes(reader.new(<<0x02, 0x01>>), 3)
    == Error(UnexpectedEof(bytes_needed: 3, remaining: 2))
}

pub fn skip_bytes_skips_expected_number_of_bytes_test() {
  let reader = reader.new(<<0x02, 0x01>>)
  let assert Ok(reader) = reader.skip_bytes(reader, 1)

  assert reader.get_offset(reader) == 1
  assert reader.get_remaining(reader) == <<0x01>>
}

pub fn skip_bytes_skips_bytes_when_exact_count_test() {
  let reader = reader.new(<<0x02>>)
  let assert Ok(reader) = reader.skip_bytes(reader, 1)

  assert reader.get_offset(reader) == 1
  assert reader.get_remaining(reader) == <<>>
}

// peek_bytes

pub fn peek_bytes_returns_invalid_read_count_when_count_is_negative_test() {
  assert reader.peek_bytes(reader.new(<<>>), -1) == Error(InvalidReadCount(-1))
}

pub fn peek_bytes_returns_0_bytes_when_count_is_zero_test() {
  let reader = reader.new(<<0x02, 0x01>>)
  let assert Ok(bytes) = reader.peek_bytes(reader, 0)

  assert bytes == <<>>
}

pub fn peek_bytes_returns_eof_when_zero_bytes_test() {
  assert reader.peek_bytes(reader.new(<<>>), 1)
    == Error(UnexpectedEof(bytes_needed: 1, remaining: 0))
}

pub fn peek_bytes_returns_eof_when_not_enough_bytes_test() {
  assert reader.peek_bytes(reader.new(<<0x02, 0x01>>), 3)
    == Error(UnexpectedEof(bytes_needed: 3, remaining: 2))
}

pub fn peek_bytes_returns_expected_number_of_bytes_test() {
  assert reader.peek_bytes(reader.new(<<0x02, 0x01>>), 1) == Ok(<<0x02>>)
}

pub fn peek_bytes_returns_bytes_when_exact_count_test() {
  assert reader.peek_bytes(reader.new(<<0x02>>), 1) == Ok(<<0x02>>)
}

pub fn peek_bytes_does_not_advance_reader_test() {
  let reader = reader.new(<<0x01, 0x02, 0x03>>)
  let assert Ok(bytes) = reader.peek_bytes(reader, 2)

  assert bytes == <<0x01, 0x02>>
  assert reader.get_offset(reader) == 0
  assert reader.get_remaining(reader) == <<0x01, 0x02, 0x03>>
}

pub fn peek_bytes_can_peek_same_bytes_multiple_times_test() {
  let reader = reader.new(<<0xAA, 0xBB>>)

  let assert Ok(bytes1) = reader.peek_bytes(reader, 2)
  let assert Ok(bytes2) = reader.peek_bytes(reader, 2)

  assert bytes1 == <<0xAA, 0xBB>>
  assert bytes2 == <<0xAA, 0xBB>>
  assert reader.get_offset(reader) == 0
}

// take_bytes

pub fn take_bytes_returns_invalid_read_count_when_count_is_negative_test() {
  assert reader.take_bytes(reader.new(<<>>), -1) == Error(InvalidReadCount(-1))
}

pub fn take_bytes_takes_0_bytes_when_count_is_zero_test() {
  let reader = reader.new(<<0x02, 0x01>>)
  let assert Ok(#(updated_reader, sub_reader)) = reader.take_bytes(reader, 0)

  assert updated_reader == reader
  assert reader.get_offset(updated_reader) == 0
  assert reader.get_remaining(sub_reader) == <<>>
}

pub fn take_bytes_returns_eof_when_zero_bytes_test() {
  assert reader.take_bytes(reader.new(<<>>), 1)
    == Error(UnexpectedEof(bytes_needed: 1, remaining: 0))
}

pub fn take_bytes_returns_eof_when_not_enough_bytes_test() {
  assert reader.take_bytes(reader.new(<<0x02, 0x01>>), 3)
    == Error(UnexpectedEof(bytes_needed: 3, remaining: 2))
}

pub fn take_bytes_takes_expected_number_of_bytes_test() {
  let reader = reader.new(<<0x01, 0x02, 0x03>>)
  let assert Ok(#(updated_reader, sub_reader)) = reader.take_bytes(reader, 2)

  assert reader.get_offset(updated_reader) == 2
  assert reader.get_remaining(updated_reader) == <<0x03>>
  assert reader.get_remaining(sub_reader) == <<0x01, 0x02>>
}

pub fn take_bytes_takes_bytes_when_exact_count_test() {
  let reader = reader.new(<<0x01, 0x02>>)
  let assert Ok(#(updated_reader, sub_reader)) = reader.take_bytes(reader, 2)

  assert reader.get_offset(updated_reader) == 2
  assert reader.get_remaining(updated_reader) == <<>>
  assert reader.get_remaining(sub_reader) == <<0x01, 0x02>>
}

pub fn take_bytes_advances_original_reader_test() {
  let reader = reader.new(<<0xAA, 0xBB, 0xCC, 0xDD>>)
  let assert Ok(#(reader, _)) = reader.take_bytes(reader, 2)

  assert reader.get_offset(reader) == 2
  assert reader.get_remaining(reader) == <<0xCC, 0xDD>>
}

pub fn take_bytes_new_reader_has_correct_data_test() {
  let reader = reader.new(<<0xAA, 0xBB, 0xCC, 0xDD>>)
  let assert Ok(#(_, sub_reader)) = reader.take_bytes(reader, 3)

  assert reader.get_remaining(sub_reader) == <<0xAA, 0xBB, 0xCC>>
  assert reader.bytes_remaining(sub_reader) == 3
}

pub fn take_bytes_new_reader_starts_at_offset_zero_test() {
  let reader = reader.new(<<0x01, 0x02, 0x03, 0x04>>)
  // Advance the original reader first
  let assert Ok(#(reader, _)) = reader.read_bytes(reader, 1)
  // Now take bytes from offset 1
  let assert Ok(#(_, sub_reader)) = reader.take_bytes(reader, 2)

  assert reader.get_remaining(sub_reader) == <<0x02, 0x03>>
  assert reader.get_offset(sub_reader) == 0
}

// read_u8

pub fn read_u8_reads_int_test() {
  // Test reading 0x42 with extra bytes remaining
  let reader = reader.new(<<0x42, 0xFF, 0xAA>>)
  let assert Ok(#(reader, value)) = reader.read_u8(reader)

  assert value == 0x42
  assert reader.get_offset(reader) == 1
}

pub fn read_u8_reads_int_when_exactly_one_byte_test() {
  let reader = reader.new(<<0x42>>)
  let assert Ok(#(reader, value)) = reader.read_u8(reader)

  assert value == 0x42
  assert reader.get_offset(reader) == 1
}

pub fn read_u8_reads_max_value_test() {
  let reader = reader.new(<<0xFF>>)
  let assert Ok(#(_, value)) = reader.read_u8(reader)
  assert value == 255
}

pub fn read_u8_returns_eof_when_no_bytes_test() {
  assert reader.read_u8(reader.new(<<>>))
    == Error(UnexpectedEof(bytes_needed: 1, remaining: 0))
}

// read_u16_le

pub fn read_u16_le_reads_int_test() {
  // Test reading 0x0102 in little-endian (0x02, 0x01)
  // with extra bytes remaining
  let reader = reader.new(<<0x02, 0x01, 0xFF, 0xAA>>)
  let assert Ok(#(reader, value)) = reader.read_u16_le(reader)

  assert value == 0x0102
  assert reader.get_offset(reader) == 2
}

pub fn read_u16_le_reads_int_when_exactly_two_bytes_test() {
  let reader = reader.new(<<0x02, 0x01>>)
  let assert Ok(#(reader, value)) = reader.read_u16_le(reader)

  assert value == 0x0102
  assert reader.get_offset(reader) == 2
}

pub fn read_u16_le_returns_eof_when_not_enough_bytes_test() {
  assert reader.read_u16_le(reader.new(<<0x02>>))
    == Error(UnexpectedEof(bytes_needed: 2, remaining: 1))
}

pub fn read_u16_le_reads_max_value_test() {
  let reader = reader.new(<<0xFF, 0xFF>>)
  let assert Ok(#(_, value)) = reader.read_u16_le(reader)
  assert value == 65_535
}

// read_u32_le

pub fn read_u32_le_returns_int_test() {
  // Test reading 0x01020304 in little-endian (0x04, 0x03, 0x02, 0x01)
  // with extra bytes remaining
  let reader = reader.new(<<0x04, 0x03, 0x02, 0x01, 0xFF, 0xAA>>)
  let assert Ok(#(reader, value)) = reader.read_u32_le(reader)

  assert value == 0x01020304
  assert reader.get_offset(reader) == 4
}

pub fn read_u32_le_reads_int_when_exactly_four_bytes_test() {
  let reader = reader.new(<<0x04, 0x03, 0x02, 0x01>>)
  let assert Ok(#(reader, value)) = reader.read_u32_le(reader)

  assert value == 0x01020304
  assert reader.get_offset(reader) == 4
}

pub fn read_u32_le_reads_max_value_test() {
  let reader = reader.new(<<0xFF, 0xFF, 0xFF, 0xFF>>)
  let assert Ok(#(_, value)) = reader.read_u32_le(reader)
  assert value == 4_294_967_295
}

pub fn read_u32_le_returns_eof_when_not_enough_bytes_test() {
  assert reader.read_u32_le(reader.new(<<0x04, 0x03, 0x02>>))
    == Error(UnexpectedEof(bytes_needed: 4, remaining: 3))
}

// read_i32_le

pub fn read_i32_le_reads_positive_int_test() {
  // Test reading 0x01020304 in little-endian (0x04, 0x03, 0x02, 0x01)
  // with extra bytes remaining
  let reader = reader.new(<<0x04, 0x03, 0x02, 0x01, 0xFF, 0xAA>>)
  let assert Ok(#(reader, value)) = reader.read_i32_le(reader)

  assert value == 0x01020304
  assert reader.get_offset(reader) == 4
}

pub fn read_i32_le_reads_negative_int_test() {
  // Test reading -1 (0xFFFFFFFF) in little-endian (0xFF, 0xFF, 0xFF, 0xFF)
  let reader = reader.new(<<0xFF, 0xFF, 0xFF, 0xFF, 0xAA>>)
  let assert Ok(#(reader, value)) = reader.read_i32_le(reader)

  assert value == -1
  assert reader.get_offset(reader) == 4
}

pub fn read_i32_le_reads_int_when_exactly_four_bytes_test() {
  let reader = reader.new(<<0xFF, 0xFF, 0xFF, 0xFF>>)
  let assert Ok(#(reader, value)) = reader.read_i32_le(reader)

  assert value == -1
  assert reader.get_offset(reader) == 4
}

pub fn read_i32_le_reads_max_positive_int_test() {
  // 0x7FFFFFFF = 2147483647
  let reader = reader.new(<<0xFF, 0xFF, 0xFF, 0x7F>>)
  let assert Ok(#(_, value)) = reader.read_i32_le(reader)
  assert value == 2_147_483_647
}

pub fn read_i32_le_reads_min_negative_int_test() {
  // 0x80000000 = -2147483648
  let reader = reader.new(<<0x00, 0x00, 0x00, 0x80>>)
  let assert Ok(#(_, value)) = reader.read_i32_le(reader)
  assert value == -2_147_483_648
}

pub fn read_i32_le_returns_eof_when_not_enough_bytes_test() {
  assert reader.read_i32_le(reader.new(<<0xFF, 0xFF>>))
    == Error(UnexpectedEof(bytes_needed: 4, remaining: 2))
}
// read_i64_le 
