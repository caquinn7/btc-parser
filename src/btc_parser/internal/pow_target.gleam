import btc_parser/internal/fixed_int/uint256.{type Uint256}
import btc_parser/internal/hash32.{type Hash32}
import gleam/bit_array
import gleam/bool
import gleam/int
import gleam/order.{type Order, Eq, Gt, Lt}
import gleam/result

const compact_coefficient_byte_count = 3

const target_byte_count = 32

/// A nonzero unsigned 256-bit Bitcoin proof-of-work target.
///
/// This type guarantees that the target is a nonzero unsigned 256-bit value
/// with an exact 32-byte little-endian representation. Whether it is permitted
/// by a network's proof-of-work limit is checked separately.
pub opaque type PowTarget {
  PowTarget(Uint256)
}

/// An error that occurred while constructing a `PowTarget`.
pub type ConstructionError {
  /// The input did not contain the required number of bytes.
  ///
  /// The fields contain the measured and required byte counts, respectively.
  InvalidByteCount(actual: Int, expected: Int)

  /// The input represented a target of zero.
  ZeroTarget

  /// A nonzero compact encoding had its sign bit set.
  NegativeTarget

  /// A compact encoding represented a value that requires more than 256 bits.
  Overflow
}

/// Constructs a proof-of-work target from exactly 32 little-endian bytes.
///
/// Returns `InvalidByteCount` if the input is not exactly 32 bytes and
/// `ZeroTarget` if every input bit is zero. Because the bytes represent an
/// unsigned magnitude directly, this function cannot return `NegativeTarget`
/// or `Overflow`.
pub fn from_bytes_le(bytes: BitArray) -> Result(PowTarget, ConstructionError) {
  bytes
  |> uint256.from_bytes_le
  |> result.map_error(fn(err) {
    case err {
      uint256.InvalidByteCount(count) -> InvalidByteCount(count, 32)
    }
  })
  |> result.try(from_uint256)
}

/// Expands Bitcoin's four-byte compact target encoding into a `PowTarget`.
///
/// The input must be the compact `nBits` value in its block-header wire order:
/// a three-byte little-endian coefficient followed by a one-byte exponent.
/// The coefficient's high bit is interpreted as the compact encoding's sign
/// bit rather than as part of its magnitude.
///
/// For exponents greater than `3`, the numeric target is:
///
/// `target = coefficient × 256^(exponent - 3)`
///
/// For example, `<<0x56, 0x34, 0x12, 0x04>>` has coefficient `0x123456` and
/// exponent `4`, so it expands to the numeric target `0x12345600`. Its
/// 32-byte little-endian representation is
/// `<<0x00, 0x56, 0x34, 0x12, 0:size(224)>>`.
///
/// Smaller exponents right-shift the coefficient by `8 × (3 - exponent)` bits.
/// For example, `<<0x56, 0x34, 0x12, 0x02>>` is right-shifted by eight bits to
/// the numeric target `0x1234`. Its 32-byte little-endian representation is
/// `<<0x34, 0x12, 0:size(240)>>`.
///
/// Returns an error when the input is not exactly four bytes or represents a
/// zero, negative, or greater-than-256-bit target. This function does not check
/// the expanded target against a network's proof-of-work limit or expected
/// chain difficulty.
pub fn from_compact_encoding(
  bytes: BitArray,
) -> Result(PowTarget, ConstructionError) {
  case bytes {
    <<coefficient:24-little, exponent:8>> -> {
      let adjusted_magnitude = {
        let magnitude_mask = 0x007FFFFF
        let compact_magnitude = int.bitwise_and(coefficient, magnitude_mask)
        adjust_compact_magnitude(compact_magnitude, exponent)
      }

      use <- bool.guard(adjusted_magnitude == 0, Error(ZeroTarget))

      let is_negative = {
        let sign_mask = 0x00800000
        int.bitwise_and(coefficient, sign_mask) != 0
      }

      use <- bool.guard(is_negative, Error(NegativeTarget))

      use <- bool.guard(
        requires_more_than_256_bits(adjusted_magnitude, exponent),
        Error(Overflow),
      )

      let target_bytes = expand_compact_magnitude(adjusted_magnitude, exponent)

      // The preceding checks guarantee the expansion is not zero and exactly 32 bytes.
      let assert Ok(target) = uint256.from_bytes_le(target_bytes)
      let assert Ok(target) = from_uint256(target)
      Ok(target)
    }

    _ -> Error(InvalidByteCount(bit_array.byte_size(bytes), 4))
  }
}

/// Adjusts the signless compact coefficient by right-shifting it when the
/// exponent is smaller than its three-byte encoded width.
fn adjust_compact_magnitude(compact_magnitude: Int, exponent: Int) -> Int {
  case exponent <= compact_coefficient_byte_count {
    True ->
      int.bitwise_shift_right(
        compact_magnitude,
        8 * { compact_coefficient_byte_count - exponent },
      )
    False -> compact_magnitude
  }
}

/// Reports whether expanding a normalized compact magnitude would exceed the
/// 32-byte proof-of-work target representation.
fn requires_more_than_256_bits(magnitude: Int, exponent: Int) -> Bool {
  case exponent <= compact_coefficient_byte_count {
    True -> False
    False -> {
      let expanded_magnitude_byte_count =
        exponent
        - compact_coefficient_byte_count
        + significant_byte_count(magnitude)

      expanded_magnitude_byte_count > target_byte_count
    }
  }
}

/// Returns the fewest bytes needed to encode a compact magnitude.
fn significant_byte_count(magnitude: Int) -> Int {
  case magnitude <= 0xFF {
    True -> 1
    False ->
      case magnitude <= 0xFFFF {
        True -> 2
        False -> compact_coefficient_byte_count
      }
  }
}

/// Expands a normalized compact magnitude into exactly 32 little-endian target
/// bytes after its size has been checked.
fn expand_compact_magnitude(magnitude: Int, exponent: Int) -> BitArray {
  case exponent <= compact_coefficient_byte_count {
    True -> <<
      magnitude:24-little,
      0:size({ { target_byte_count - compact_coefficient_byte_count } * 8 }),
    >>

    False -> {
      let zero_bytes_at_low_end = exponent - compact_coefficient_byte_count
      let magnitude_bytes = significant_bytes_le(magnitude)
      let zero_bytes_at_high_end =
        target_byte_count
        - zero_bytes_at_low_end
        - bit_array.byte_size(magnitude_bytes)

      <<
        0:size({ zero_bytes_at_low_end * 8 }),
        magnitude_bytes:bits,
        0:size({ zero_bytes_at_high_end * 8 }),
      >>
    }
  }
}

/// Serializes a compact magnitude in little-endian order without high-order
/// zero bytes.
fn significant_bytes_le(magnitude: Int) -> BitArray {
  case significant_byte_count(magnitude) {
    1 -> <<magnitude:8>>
    2 -> <<magnitude:16-little>>
    _ -> <<magnitude:24-little>>
  }
}

/// Wraps a nonzero unsigned 256-bit value as a proof-of-work target.
fn from_uint256(value: Uint256) -> Result(PowTarget, ConstructionError) {
  case uint256.is_zero(value) {
    True -> Error(ZeroTarget)
    False -> Ok(PowTarget(value))
  }
}

/// Compares two proof-of-work targets as unsigned 256-bit integers.
///
/// The returned order describes `target` relative to `pow_limit`: `Lt` means
/// the target is lower, `Eq` means they are equal, and `Gt` means the target
/// exceeds the limit.
pub fn compare(target: PowTarget, pow_limit: PowTarget) -> Order {
  let PowTarget(target) = target
  let PowTarget(pow_limit) = pow_limit

  compare_bytes_from_most_significant(
    uint256.to_bytes_le(target),
    uint256.to_bytes_le(pow_limit),
    31,
  )
}

/// Returns whether a block hash satisfies the proof-of-work target.
///
/// The hash and target are compared as unsigned 256-bit integers. A hash
/// satisfies the target when its numeric value is less than or equal to the
/// target.
pub fn is_satisfied_by(target: PowTarget, block_hash: Hash32) -> Bool {
  let PowTarget(target) = target

  let order =
    compare_bytes_from_most_significant(
      hash32.to_bytes_le(block_hash),
      uint256.to_bytes_le(target),
      31,
    )

  case order {
    Lt | Eq -> True
    Gt -> False
  }
}

fn compare_bytes_from_most_significant(
  left: BitArray,
  right: BitArray,
  byte_index: Int,
) -> Order {
  case byte_index < 0 {
    True -> Eq
    False -> {
      // `Uint256` and `Hash32` guarantee that their byte representations
      // contain exactly 32 bytes, so these slices are in bounds while
      // `byte_index` is nonnegative.
      let assert Ok(<<left_byte>>) = bit_array.slice(left, byte_index, 1)
      let assert Ok(<<right_byte>>) = bit_array.slice(right, byte_index, 1)

      case left_byte < right_byte {
        True -> Lt
        False ->
          case left_byte > right_byte {
            True -> Gt
            False ->
              compare_bytes_from_most_significant(left, right, byte_index - 1)
          }
      }
    }
  }
}
