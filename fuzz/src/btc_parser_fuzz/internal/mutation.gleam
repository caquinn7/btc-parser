import btc_parser_fuzz/internal/rng.{type Rng}
import gleam/bit_array
import gleam/bool
import gleam/int
import gleam/list

/// Scan the byte stream for heuristic CompactSize candidates, select one at
/// random, and apply a targeted mutation to it.
///
/// Fuzzing purpose:
/// - Targets length-prefixed fields (input/output counts, script lengths, and
///   witness item lengths)
///   throughout the transaction without requiring structural knowledge of the format
/// - Non-minimal encoding directly targets a protocol rule the parser must enforce
/// - Preserves enough surrounding structure that malformed inputs are likely to reach
///   inner parsing logic rather than being rejected at a boundary check
pub fn mutate_heuristic_compact_size_candidate(
  bytes: BitArray,
  rng: Rng,
) -> #(BitArray, Rng) {
  case find_compact_size_candidates(bytes) {
    [] -> #(bytes, rng)

    candidates -> {
      let assert Ok(#(candidate, rng)) = rng.sample_one(rng, candidates)
      mutate_compact_size_candidate(bytes, candidate, rng)
    }
  }
}

/// Interpret the bytes at `offset` as one CompactSize value and mutate it.
///
/// This is the targeted counterpart to
/// `mutate_heuristic_compact_size_candidate`. It is useful when an enclosing
/// wire format identifies a known CompactSize field, such as a block's
/// transaction count at byte offset 80.
///
/// Invalid offsets, incomplete encodings, and `0xFF` encodings are left
/// unchanged without advancing the RNG. `0xFF` is unsupported because its
/// unsigned 64-bit value may exceed the exact `Int` range on JavaScript.
pub fn mutate_compact_size_at(
  bytes: BitArray,
  offset: Int,
  rng: Rng,
) -> #(BitArray, Rng) {
  case compact_size_candidate_at(bytes, offset) {
    Error(Nil) -> #(bytes, rng)
    Ok(candidate) -> mutate_compact_size_candidate(bytes, candidate, rng)
  }
}

pub type CompactSizeCandidate {
  CompactSizeCandidate(start: Int, width: Int, value: Int)
}

fn mutate_compact_size_candidate(
  bytes: BitArray,
  candidate: CompactSizeCandidate,
  rng: Rng,
) -> #(BitArray, Rng) {
  let #(n, rng) = rng.next_bounded(rng, 5)

  let mutated_bytes = case n {
    0 -> rewrite_compact_size(bytes, candidate, candidate.value + 1)
    1 -> rewrite_compact_size(bytes, candidate, 0)
    2 -> rewrite_compact_size(bytes, candidate, 65_535)
    3 -> rewrite_with_nonminimal_encoding(bytes, candidate)
    _ -> truncate_compact_size(bytes, candidate)
  }

  #(mutated_bytes, rng)
}

fn rewrite_with_nonminimal_encoding(
  bytes: BitArray,
  candidate: CompactSizeCandidate,
) -> BitArray {
  // Force a non-minimal encoding by promoting the value to the next wider
  // prefix. e.g. a 1-byte value (0–252) becomes a 3-byte 0xFD encoding.
  let promoted = case candidate.width {
    1 -> <<0xFD, candidate.value:16-little>>
    3 -> <<0xFE, candidate.value:32-little>>
    _ -> encode_compact_size(candidate.value)
  }

  let after_start = candidate.start + candidate.width
  let after_length = bit_array.byte_size(bytes) - after_start

  let assert Ok(before) = bit_array.slice(bytes, 0, candidate.start)
  let assert Ok(after) = bit_array.slice(bytes, after_start, after_length)

  before
  |> bit_array.append(promoted)
  |> bit_array.append(after)
}

fn truncate_compact_size(
  bytes: BitArray,
  candidate: CompactSizeCandidate,
) -> BitArray {
  let after_start = candidate.start + candidate.width
  let after_length = bit_array.byte_size(bytes) - after_start

  let assert Ok(prefix) = bit_array.slice(bytes, 0, candidate.start)
  let assert Ok(suffix) = bit_array.slice(bytes, after_start, after_length)

  case candidate.width > 1 {
    True -> {
      let assert Ok(truncated_region) =
        bit_array.slice(bytes, candidate.start, candidate.width - 1)

      prefix
      |> bit_array.append(truncated_region)
      |> bit_array.append(suffix)
    }

    False ->
      prefix
      |> bit_array.append(<<0xFD>>)
      |> bit_array.append(suffix)
  }
}

fn find_compact_size_candidates(bytes: BitArray) -> List(CompactSizeCandidate) {
  let length = bit_array.byte_size(bytes)

  // Accumulate in reverse for O(1) prepends, then restore order at the end.
  bytes
  |> find_compact_size_candidates_loop(length, 0, [])
  |> list.reverse
}

fn find_compact_size_candidates_loop(
  bytes: BitArray,
  length: Int,
  offset: Int,
  acc: List(CompactSizeCandidate),
) -> List(CompactSizeCandidate) {
  case offset >= length {
    True -> acc
    False -> {
      case compact_size_candidate_at(bytes, offset) {
        Ok(candidate) ->
          find_compact_size_candidates_loop(
            bytes,
            length,
            offset + candidate.width,
            [candidate, ..acc],
          )

        Error(Nil) ->
          find_compact_size_candidates_loop(bytes, length, offset + 1, acc)
      }
    }
  }
}

fn compact_size_candidate_at(
  bytes: BitArray,
  offset: Int,
) -> Result(CompactSizeCandidate, Nil) {
  let length = bit_array.byte_size(bytes)

  case offset < 0 || offset >= length {
    True -> Error(Nil)
    False -> {
      let assert Ok(<<prefix:8>>) = bit_array.slice(bytes, offset, 1)

      case prefix {
        // 0x00–0xFC: single-byte encoding; the byte itself is the value.
        p if p <= 0xFC ->
          Ok(CompactSizeCandidate(start: offset, width: 1, value: p))

        // 0xFD: 3-byte encoding — prefix + 2 LE bytes.
        0xFD if offset + 3 <= length -> {
          let assert Ok(<<lo:8, hi:8>>) = bit_array.slice(bytes, offset + 1, 2)
          let value = lo + hi * 256
          Ok(CompactSizeCandidate(start: offset, width: 3, value:))
        }

        // 0xFE: 5-byte encoding — prefix + 4 LE bytes.
        0xFE if offset + 5 <= length -> {
          let assert Ok(<<b0:8, b1:8, b2:8, b3:8>>) =
            bit_array.slice(bytes, offset + 1, 4)

          let value = b0 + b1 * 256 + b2 * 65_536 + b3 * 16_777_216
          Ok(CompactSizeCandidate(start: offset, width: 5, value:))
        }

        // 0xFF values may exceed JavaScript's exact `Int` range. Incomplete
        // 0xFD/0xFE encodings are not candidates either.
        _ -> Error(Nil)
      }
    }
  }
}

pub fn rewrite_compact_size(
  bytes: BitArray,
  candidate: CompactSizeCandidate,
  new_value: Int,
) -> BitArray {
  let after_start = candidate.start + candidate.width
  let after_length = bit_array.byte_size(bytes) - after_start
  let encoded = encode_compact_size(new_value)

  let assert Ok(before) = bit_array.slice(bytes, 0, candidate.start)
  let assert Ok(after) = bit_array.slice(bytes, after_start, after_length)
  before
  |> bit_array.append(encoded)
  |> bit_array.append(after)
}

fn encode_compact_size(value: Int) -> BitArray {
  case value {
    v if v <= 252 -> <<v:8>>
    v if v <= 65_535 -> <<0xFD, v:16-little>>
    v if v <= 4_294_967_295 -> <<0xFE, v:32-little>>
    v -> <<0xFF, v:64-little>>
  }
}

/// Cut the byte stream at a random position and discard everything after it.
///
/// Intended behavior:
/// - Return a prefix of the original bytes
/// - May remove part of a field, part of a CompactSize value, or the tail of the
///   transaction entirely
///
/// Fuzzing purpose:
/// - Exercise truncated-input handling
/// - Verify the parser fails cleanly on incomplete transactions
/// - Good for boundary checks and "unexpected EOF" style paths
pub fn truncate(bytes: BitArray, rng: Rng) -> #(BitArray, Rng) {
  let length = bit_array.byte_size(bytes)
  use <- bool.guard(length <= 1, #(bytes, rng))

  let #(slice_count, rng) = rng.next_bounded(rng, length)
  let assert Ok(sliced) = bit_array.slice(bytes, 0, slice_count)
  #(sliced, rng)
}

/// Replace 1–3 bytes at random positions with random replacement values.
///
/// Fuzzing purpose:
/// - Targets byte-level fields throughout the transaction: opcodes, varints, txids, amounts, and length prefixes
/// - Likely to hit many distinct parser paths per iteration
/// - Complementary to `FlipBits`: operates at byte granularity, producing more disruptive changes
pub fn flip_bytes(bytes: BitArray, rng: Rng) -> #(BitArray, Rng) {
  let length = bit_array.byte_size(bytes)
  use <- bool.guard(length == 0, #(bytes, rng))

  let #(extra, rng) = rng.next_bounded(rng, 3)
  flip_n_bytes(bytes, length, extra + 1, rng)
}

fn flip_n_bytes(
  bytes: BitArray,
  length: Int,
  remaining: Int,
  rng: Rng,
) -> #(BitArray, Rng) {
  case remaining == 0 {
    True -> #(bytes, rng)
    False -> {
      let #(offset, rng) = rng.next_bounded(rng, length)
      let #(new_byte, rng) = rng.next_bounded(rng, 256)
      let bytes = replace_byte_at(bytes, offset, new_byte)
      flip_n_bytes(bytes, length, remaining - 1, rng)
    }
  }
}

pub fn replace_byte_at(bytes: BitArray, offset: Int, value: Int) -> BitArray {
  let after_length = bit_array.byte_size(bytes) - offset - 1
  let assert Ok(before) = bit_array.slice(bytes, 0, offset)
  let assert Ok(after) = bit_array.slice(bytes, offset + 1, after_length)

  before
  |> bit_array.append(<<value:8>>)
  |> bit_array.append(after)
}

/// Toggle 1–3 individual bits at random positions within the byte stream.
///
/// Fuzzing purpose:
/// - Produce small, local changes that preserve most structure
/// - Good for off-by-one style length changes, flag changes, and subtle numeric perturbations
/// - Often gets deeper parser coverage than heavier mutations
pub fn flip_bits(bytes: BitArray, rng: Rng) -> #(BitArray, Rng) {
  let length = bit_array.byte_size(bytes)
  use <- bool.guard(length == 0, #(bytes, rng))

  let #(extra, rng) = rng.next_bounded(rng, 3)
  flip_n_bits(bytes, length, extra + 1, rng)
}

fn flip_n_bits(
  bytes: BitArray,
  length: Int,
  remaining: Int,
  rng: Rng,
) -> #(BitArray, Rng) {
  case remaining {
    0 -> #(bytes, rng)
    _ -> {
      let #(bit_idx, rng) = rng.next_bounded(rng, length * 8)
      let mask = int.bitwise_shift_left(1, bit_idx % 8)
      let bytes = xor_byte_at(bytes, bit_idx / 8, mask)
      flip_n_bits(bytes, length, remaining - 1, rng)
    }
  }
}

fn xor_byte_at(bytes: BitArray, offset: Int, mask: Int) -> BitArray {
  let after_length = bit_array.byte_size(bytes) - offset - 1
  let assert Ok(<<byte:8>>) = bit_array.slice(bytes, offset, 1)
  let assert Ok(before) = bit_array.slice(bytes, 0, offset)
  let assert Ok(after) = bit_array.slice(bytes, offset + 1, after_length)

  before
  |> bit_array.append(<<int.bitwise_exclusive_or(byte, mask):8>>)
  |> bit_array.append(after)
}

/// Splice 1–8 random bytes at a random position in the stream.
///
/// Fuzzing purpose:
/// - Shift alignment of everything that follows
/// - Useful for stressing parsers that rely on precise field boundaries
/// - Can create leftover trailing bytes, bogus lengths, or witness/script misalignment
pub fn insert_bytes(bytes: BitArray, rng: Rng) -> #(BitArray, Rng) {
  let length = bit_array.byte_size(bytes)

  // Insert at any position in [0, length], including the end.
  let #(offset, rng) = rng.next_bounded(rng, length + 1)
  let #(insert_length, rng) = rng.next_bounded(rng, 8)
  let #(inserted, rng) = random_bytes(rng, insert_length + 1)

  let assert Ok(before) = bit_array.slice(bytes, 0, offset)

  let after_length = length - offset
  let assert Ok(after) = bit_array.slice(bytes, offset, after_length)

  let result =
    before
    |> bit_array.append(inserted)
    |> bit_array.append(after)

  #(result, rng)
}

/// Remove a contiguous span of 1–8 bytes from a random interior position.
///
/// Fuzzing purpose:
/// - Create internal truncation rather than only tail truncation
/// - Good for breaking field completeness while keeping the rest of the tx present
/// - Useful for malformed scripts, missing witness bytes, or chopped varints
pub fn delete_span(bytes: BitArray, rng: Rng) -> #(BitArray, Rng) {
  let length = bit_array.byte_size(bytes)
  use <- bool.guard(length <= 1, #(bytes, rng))

  let #(start, rng) = rng.next_bounded(rng, length)
  let #(span_length, rng) = rng.next_bounded(rng, 8)
  let span_length = int.min(span_length + 1, length - start)

  let assert Ok(before) = bit_array.slice(bytes, 0, start)

  let after_start = start + span_length
  let after_length = length - after_start
  let assert Ok(after) = bit_array.slice(bytes, after_start, after_length)

  #(bit_array.append(before, after), rng)
}

/// Copy a contiguous span of 1–8 bytes from a random source position and
/// insert the copy at a separate random position in the output.
///
/// Fuzzing purpose:
/// - The copied bytes are structurally plausible (drawn from a real transaction), so
///   mutations are more likely to pass early rejection and reach inner parsing logic
/// - Useful for triggering count/length mismatches between declared and actual input/output counts
/// - Can produce inflated witness stacks, repeated script fragments, or duplicated field regions
pub fn duplicate_span(bytes: BitArray, rng: Rng) -> #(BitArray, Rng) {
  let length = bit_array.byte_size(bytes)
  use <- bool.guard(length == 0, #(bytes, rng))

  let #(src, rng) = rng.next_bounded(rng, length)
  let #(span_length, rng) = rng.next_bounded(rng, 8)
  let span_length = int.min(span_length + 1, length - src)
  let assert Ok(span) = bit_array.slice(bytes, src, span_length)

  // Insert position is over the original length so the copy can land anywhere
  // including the end, independent of where it was copied from.
  let #(insert_at, rng) = rng.next_bounded(rng, length + 1)
  let assert Ok(before) = bit_array.slice(bytes, 0, insert_at)

  let after_length = length - insert_at
  let assert Ok(after) = bit_array.slice(bytes, insert_at, after_length)

  let result =
    before
    |> bit_array.append(span)
    |> bit_array.append(after)

  #(result, rng)
}

/// Replace a contiguous span of 1-8 bytes with zero bytes of the same length.
///
/// Fuzzing purpose:
/// - Destroy local meaning without changing offsets
/// - Useful when you want corruption but do not want global re-alignment effects
/// - Good for txids, values, sequence numbers, scripts, and witness payloads
/// - Can expose zero-value edge cases: zero amounts, zeroed txids (as in coinbase inputs), or empty scripts
pub fn zero_span(bytes: BitArray, rng: Rng) -> #(BitArray, Rng) {
  let length = bit_array.byte_size(bytes)
  use <- bool.guard(length == 0, #(bytes, rng))

  let #(start, rng) = rng.next_bounded(rng, length)
  let #(span_length, rng) = rng.next_bounded(rng, 8)
  let span_length = int.min(span_length + 1, length - start)

  let assert Ok(before) = bit_array.slice(bytes, 0, start)

  let after_start = start + span_length
  let after_length = length - after_start
  let assert Ok(after) = bit_array.slice(bytes, after_start, after_length)

  let result =
    before
    |> bit_array.append(zero_bytes(span_length))
    |> bit_array.append(after)

  #(result, rng)
}

fn zero_bytes(length: Int) -> BitArray {
  int.range(0, length, <<>>, fn(acc, _i) { bit_array.append(acc, <<0:8>>) })
}

/// Generates `length` pseudo-random bytes and returns them as a `BitArray`
/// alongside the new RNG state.
fn random_bytes(rng: Rng, length: Int) -> #(BitArray, Rng) {
  let #(bytes, rng) =
    int.range(0, length, #([], rng), fn(acc, _i) {
      let #(bytes, rng) = acc
      let #(byte_val, rng) = rng.next_bounded(rng, 256)
      #([<<byte_val:8>>, ..bytes], rng)
    })

  let bytes =
    bytes
    |> list.reverse
    |> bit_array.concat

  #(bytes, rng)
}
