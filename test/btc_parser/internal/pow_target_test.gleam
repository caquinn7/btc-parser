import btc_parser/internal/hash256.{type Hash256}
import btc_parser/internal/pow_target.{
  type PowTarget, InvalidBitCount, NegativeTarget, Overflow, ZeroTarget,
}
import gleam/bit_array
import gleam/list
import gleam/order.{Eq, Gt, Lt}

// from_bytes_le

pub fn from_bytes_le_reports_incorrect_bit_counts_test() {
  assert pow_target.from_bytes_le(<<>>)
    == Error(InvalidBitCount(actual: 0, expected: 256))

  assert pow_target.from_bytes_le(<<0:size({ 31 * 8 })>>)
    == Error(InvalidBitCount(actual: 248, expected: 256))

  assert pow_target.from_bytes_le(<<0:255>>)
    == Error(InvalidBitCount(actual: 255, expected: 256))

  assert pow_target.from_bytes_le(<<0:257>>)
    == Error(InvalidBitCount(actual: 257, expected: 256))

  assert pow_target.from_bytes_le(<<0:size({ 33 * 8 })>>)
    == Error(InvalidBitCount(actual: 264, expected: 256))
}

pub fn from_bytes_le_rejects_zero_target_test() {
  assert pow_target.from_bytes_le(<<0:256>>) == Error(ZeroTarget)
}

pub fn from_bytes_le_accepts_smallest_nonzero_target_test() {
  let assert Ok(_) = pow_target.from_bytes_le(<<0x01, 0:248>>)
}

pub fn from_bytes_le_accepts_target_with_most_significant_bit_set_test() {
  // A proof-of-work target is an unsigned 256-bit magnitude.
  let assert Ok(_) = pow_target.from_bytes_le(<<0:248, 0x80>>)
}

pub fn from_bytes_le_preserves_distinct_little_endian_values_test() {
  let assert Ok(one) = pow_target.from_bytes_le(<<0x01, 0:248>>)
  let assert Ok(two_to_248) = pow_target.from_bytes_le(<<0:248, 0x01>>)

  assert one != two_to_248
}

// compare

pub fn compare_returns_eq_for_identical_values_test() {
  let target = pow_target_from_bytes_le(<<0x01, 0:248>>)

  assert pow_target.compare(target, target) == Eq
}

pub fn compare_returns_eq_for_equivalent_compact_and_expanded_values_test() {
  let assert Ok(from_compact) =
    pow_target.from_compact_encoding(<<0xFF, 0xFF, 0x00, 0x1D>>)

  let from_expanded =
    pow_target_from_bytes_le(<<
      0:size({ 26 * 8 }),
      0xFF,
      0xFF,
      0:32,
    >>)

  assert pow_target.compare(from_compact, from_expanded) == Eq
}

pub fn compare_orders_adjacent_low_byte_values_test() {
  let one = pow_target_from_bytes_le(<<0x01, 0:248>>)
  let two = pow_target_from_bytes_le(<<0x02, 0:248>>)

  assert pow_target.compare(one, two) == Lt
  assert pow_target.compare(two, one) == Gt
}

pub fn compare_prioritizes_more_significant_bytes_test() {
  let lower = pow_target_from_bytes_le(<<0xFF, 0x01, 0:240>>)
  let higher = pow_target_from_bytes_le(<<0x00, 0x02, 0:240>>)

  assert pow_target.compare(lower, higher) == Lt
  assert pow_target.compare(higher, lower) == Gt
}

pub fn compare_detects_a_difference_in_a_middle_byte_test() {
  let lower = pow_target_from_bytes_le(<<0x01, 0:120, 0x12, 0:120>>)
  let higher = pow_target_from_bytes_le(<<0x01, 0:120, 0x13, 0:120>>)

  assert pow_target.compare(lower, higher) == Lt
  assert pow_target.compare(higher, lower) == Gt
}

pub fn compare_treats_bit_255_as_unsigned_test() {
  let upper_half = pow_target_from_bytes_le(<<0x01, 0:240, 0x80>>)
  let lower_half = pow_target_from_bytes_le(<<0xFF, 0:240, 0x7F>>)

  assert pow_target.compare(upper_half, lower_half) == Gt
  assert pow_target.compare(lower_half, upper_half) == Lt
}

pub fn compare_orders_mainnet_genesis_target_below_mainnet_pow_limit_test() {
  let genesis_target =
    pow_target_from_bytes_le(<<
      0:size({ 26 * 8 }),
      0xFF,
      0xFF,
      0:32,
    >>)

  let pow_limit =
    list.repeat(<<0xFF>>, 28)
    |> bit_array.concat
    |> fn(bytes) { <<bytes:bits, 0:32>> }
    |> pow_target_from_bytes_le

  assert pow_target.compare(genesis_target, pow_limit) == Lt
  assert pow_target.compare(pow_limit, genesis_target) == Gt
}

// is_satisfied_by

pub fn is_satisfied_by_accepts_zero_hash_for_smallest_nonzero_target_test() {
  let target = pow_target_from_bytes_le(<<0x01, 0:248>>)
  let zero_hash = hash256_from_bytes_le(<<0:256>>)

  assert pow_target.is_satisfied_by(target, zero_hash)
}

pub fn is_satisfied_by_accepts_hash_below_target_test() {
  let target = pow_target_from_bytes_le(<<0x03, 0:248>>)
  let hash = hash256_from_bytes_le(<<0x02, 0:248>>)

  assert pow_target.is_satisfied_by(target, hash)
}

pub fn is_satisfied_by_accepts_hash_equal_to_target_test() {
  let target = pow_target_from_bytes_le(<<0x34, 0x12, 0:240>>)
  let hash = hash256_from_bytes_le(<<0x34, 0x12, 0:240>>)

  assert pow_target.is_satisfied_by(target, hash)
}

pub fn is_satisfied_by_rejects_hash_one_greater_than_target_test() {
  let target = pow_target_from_bytes_le(<<0x01, 0:248>>)
  let hash = hash256_from_bytes_le(<<0x02, 0:248>>)

  assert !pow_target.is_satisfied_by(target, hash)
}

pub fn is_satisfied_by_prioritizes_more_significant_hash_bytes_test() {
  let target = pow_target_from_bytes_le(<<0xFF, 0x01, 0:240>>)
  let hash = hash256_from_bytes_le(<<0x00, 0x02, 0:240>>)

  assert !pow_target.is_satisfied_by(target, hash)
}

pub fn is_satisfied_by_treats_bit_255_as_unsigned_test() {
  let upper_half_target = pow_target_from_bytes_le(<<0x00, 0:240, 0x80>>)
  let lower_half_hash = hash256_from_bytes_le(<<0xFF, 0:240, 0x7F>>)
  let lower_half_target = pow_target_from_bytes_le(<<0xFF, 0:240, 0x7F>>)
  let upper_half_hash = hash256_from_bytes_le(<<0x00, 0:240, 0x80>>)

  assert pow_target.is_satisfied_by(upper_half_target, lower_half_hash)
  assert !pow_target.is_satisfied_by(lower_half_target, upper_half_hash)
}

pub fn is_satisfied_by_accepts_mainnet_genesis_hash_test() {
  let assert Ok(genesis_target) =
    pow_target.from_compact_encoding(<<0xFF, 0xFF, 0x00, 0x1D>>)

  let genesis_hash =
    hash256_from_bytes_le(<<
      0x6F,
      0xE2,
      0x8C,
      0x0A,
      0xB6,
      0xF1,
      0xB3,
      0x72,
      0xC1,
      0xA6,
      0xA2,
      0x46,
      0xAE,
      0x63,
      0xF7,
      0x4F,
      0x93,
      0x1E,
      0x83,
      0x65,
      0xE1,
      0x5A,
      0x08,
      0x9C,
      0x68,
      0xD6,
      0x19,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    >>)

  assert pow_target.is_satisfied_by(genesis_target, genesis_hash)
}

// from_compact_encoding

pub fn from_compact_encoding_reports_incorrect_bit_counts_test() {
  assert pow_target.from_compact_encoding(<<>>)
    == Error(InvalidBitCount(actual: 0, expected: 32))

  assert pow_target.from_compact_encoding(<<0:24>>)
    == Error(InvalidBitCount(actual: 24, expected: 32))

  assert pow_target.from_compact_encoding(<<0:31>>)
    == Error(InvalidBitCount(actual: 31, expected: 32))

  assert pow_target.from_compact_encoding(<<0:33>>)
    == Error(InvalidBitCount(actual: 33, expected: 32))

  assert pow_target.from_compact_encoding(<<0:40>>)
    == Error(InvalidBitCount(actual: 40, expected: 32))
}

pub fn from_compact_encoding_rejects_zero_coefficient_test() {
  assert pow_target.from_compact_encoding(<<0x00, 0x00, 0x00, 0x1D>>)
    == Error(ZeroTarget)
}

pub fn from_compact_encoding_rejects_coefficient_shifted_to_zero_test() {
  // 0x000001 >> 16 = 0 when the exponent is 1.
  assert pow_target.from_compact_encoding(<<0x01, 0x00, 0x00, 0x01>>)
    == Error(ZeroTarget)
}

pub fn from_compact_encoding_treats_signed_zero_as_zero_test() {
  // The sign bit does not make a zero magnitude negative.
  assert pow_target.from_compact_encoding(<<0x00, 0x00, 0x80, 0x1D>>)
    == Error(ZeroTarget)
}

pub fn from_compact_encoding_rejects_negative_target_test() {
  assert pow_target.from_compact_encoding(<<0xFF, 0xFF, 0x80, 0x1D>>)
    == Error(NegativeTarget)
}

pub fn from_compact_encoding_prefers_negative_to_overflow_test() {
  // Exponent 35 overflows, and 0x00800001 also has its sign bit set.
  assert pow_target.from_compact_encoding(<<0x01, 0x00, 0x80, 0x23>>)
    == Error(NegativeTarget)
}

pub fn from_compact_encoding_prefers_zero_to_overflow_test() {
  // A zero coefficient remains zero regardless of the oversized exponent.
  assert pow_target.from_compact_encoding(<<0x00, 0x00, 0x00, 0x23>>)
    == Error(ZeroTarget)
}

pub fn from_compact_encoding_rejects_exponent_above_34_test() {
  assert pow_target.from_compact_encoding(<<0x01, 0x00, 0x00, 0x23>>)
    == Error(Overflow)
}

pub fn from_compact_encoding_checks_exponent_34_overflow_boundary_test() {
  // At exponent 34, a coefficient of 0xFF still fits in 256 bits.
  assert_compact_decodes_to(<<0xFF, 0x00, 0x00, 0x22>>, <<
    0:size({ 31 * 8 }),
    0xFF,
  >>)

  assert pow_target.from_compact_encoding(<<0x00, 0x01, 0x00, 0x22>>)
    == Error(Overflow)
}

pub fn from_compact_encoding_checks_exponent_33_overflow_boundary_test() {
  // At exponent 33, a coefficient of 0xFFFF still fits in 256 bits.
  assert_compact_decodes_to(<<0xFF, 0xFF, 0x00, 0x21>>, <<
    0:size({ 30 * 8 }),
    0xFF,
    0xFF,
  >>)

  assert pow_target.from_compact_encoding(<<0x00, 0x00, 0x01, 0x21>>)
    == Error(Overflow)
}

pub fn from_compact_encoding_decodes_mainnet_genesis_target_test() {
  assert_compact_decodes_to(<<0xFF, 0xFF, 0x00, 0x1D>>, <<
    0:size({ 26 * 8 }),
    0xFF,
    0xFF,
    0:32,
  >>)
}

pub fn from_compact_encoding_decodes_exponent_three_test() {
  assert_compact_decodes_to(<<0x56, 0x34, 0x12, 0x03>>, <<
    0x56,
    0x34,
    0x12,
    0:size({ 29 * 8 }),
  >>)
}

pub fn from_compact_encoding_right_shifts_for_small_exponents_test() {
  assert_compact_decodes_to(<<0x56, 0x34, 0x12, 0x02>>, <<
    0x34,
    0x12,
    0:size({ 30 * 8 }),
  >>)

  assert_compact_decodes_to(<<0x56, 0x34, 0x12, 0x01>>, <<
    0x12,
    0:size({ 31 * 8 }),
  >>)
}

pub fn from_compact_encoding_left_shifts_for_large_exponents_test() {
  assert_compact_decodes_to(<<0x56, 0x34, 0x12, 0x04>>, <<
    0x00,
    0x56,
    0x34,
    0x12,
    0:size({ 28 * 8 }),
  >>)
}

pub fn from_compact_encoding_decodes_regtest_compact_target_test() {
  assert_compact_decodes_to(<<0xFF, 0xFF, 0x7F, 0x20>>, <<
    0:size({ 29 * 8 }),
    0xFF,
    0xFF,
    0x7F,
  >>)
}

fn assert_compact_decodes_to(compact: BitArray, expected_bytes_le: BitArray) {
  let assert Ok(actual) = pow_target.from_compact_encoding(compact)
  let expected = pow_target_from_bytes_le(expected_bytes_le)
  assert actual == expected
}

fn pow_target_from_bytes_le(bytes: BitArray) -> PowTarget {
  let assert Ok(target) = pow_target.from_bytes_le(bytes)
  target
}

fn hash256_from_bytes_le(bytes: BitArray) -> Hash256 {
  let assert Ok(hash) = hash256.from_bytes_le(bytes)
  hash
}
