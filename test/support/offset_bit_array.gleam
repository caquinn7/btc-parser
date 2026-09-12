//// Test-only helpers for constructing byte-aligned views with a nonzero
//// backing-buffer bit offset.

import gleam/bit_array

/// Return `bytes` as a logically identical byte-aligned `BitArray` whose
/// backing buffer starts one bit before the returned view.
///
/// The nonzero leading and trailing padding makes accidental direct reads of
/// the backing buffer observably different from reads of the logical bytes.
pub fn with_one_bit_offset(bytes: BitArray) -> BitArray {
  let bit_count = bit_array.bit_size(bytes)
  let padded = <<1:1, bytes:bits, 0x7F:7>>
  let assert <<_:1, offset_bytes:bits-size(bit_count), _:7>> = padded
  offset_bytes
}
