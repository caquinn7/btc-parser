////  Fuzz testing harness for the `btc_tx` transaction parser.
////
////  The goal is to guarantee that *any* byte input results in either a correct
////  parse or a well-defined error — never an unhandled exception. Each run
////  receives a corpus of real Bitcoin transactions, applies random structural
////  mutations, and exercises the full decode → validate → classify → txid
////  pipeline. Using real transactions as a baseline produces higher-quality
////  mutations than pure random bytes: they are structurally plausible, so
////  mutations are more likely to reach deep parser paths rather than being
////  rejected at early boundary checks.

import btc_tx
import exception.{type Exception}
import fuzz/internal/rng.{type Rng}
import fuzz/internal/trace.{type Trace}
import gleam/bit_array
import gleam/bool
import gleam/int
import gleam/list
import gleam/string

/// Results for one invocation of the fuzz harness.
pub type FuzzResult {
  FuzzResult(
    /// Number of mutation iterations requested for the run.
    iteration_count: Int,
    /// RNG state captured before the first mutation is selected.
    initial_rng_state: Int,
    /// Hex-encoded, order-sensitive SHA-256 hash chain for all mutated inputs.
    /// This acts as a compact fingerprint for reproducible runs.
    trace_hash: String,
    /// Unhandled exceptions rescued while exercising mutated inputs.
    failures: List(IterationFailure),
  )
}

/// Details for one fuzz iteration that raised an unhandled exception.
pub type IterationFailure {
  IterationFailure(
    /// One-based iteration number within the fuzz run.
    iteration: Int,
    /// Seed transaction, mutation kind, and resulting bytes for this failure.
    mutated_tx: MutatedTx,
    /// Hex-encoded mutated transaction bytes for copying into regression tests.
    mutated_tx_hex: String,
    /// Exception rescued from the decode, validate, classify, or txid pipeline.
    exception: Exception,
  )
}

/// Transaction bytes produced by applying a mutation to one corpus seed.
pub type MutatedTx {
  MutatedTx(
    /// Original corpus transaction selected for this iteration.
    seed_tx: SeedTx,
    /// Structural mutation applied to the original transaction bytes.
    mutation: Mutation,
    /// Mutated wire bytes passed into the parser pipeline.
    bytes: BitArray,
  )
}

/// Corpus transaction used as a baseline for structural mutation.
pub type SeedTx {
  SeedTx(
    /// Display-format transaction id recorded in the seed corpus, not the
    /// little-endian txid byte order used on the wire.
    txid: String,
    /// Raw wire bytes decoded from the corpus entry.
    bytes: BitArray,
  )
}

/// Mutation strategy selected for a fuzz iteration.
pub type Mutation {
  /// Cut the byte stream at a random position and discard the tail.
  Truncate
  /// Replace a small number of bytes with random byte values.
  FlipBytes
  /// Toggle a small number of individual bits.
  FlipBits
  /// Insert a short random byte sequence at a random position.
  InsertBytes
  /// Remove a short contiguous byte span.
  DeleteSpan
  /// Copy a short byte span and insert the copy elsewhere.
  DuplicateSpan
  /// Replace a short byte span with zero bytes of the same length.
  ZeroSpan
  /// Corrupt, remove, or replace the SegWit marker/flag bytes.
  MutateSegwitMarker
  /// Mutate a heuristic CompactSize candidate in the byte stream.
  MutateCompactSizeCandidate
}

/// Runs the fuzz harness and returns failures plus reproducibility metadata.
///
/// The harness mutates `seed_txs` for `iteration_count` iterations using the
/// provided deterministic RNG.
///
/// Each iteration draws one transaction from `seed_txs` uniformly at random,
/// applies a structural mutation, and runs the full decode → validate →
/// classify → txid pipeline.  Any unhandled exception is recorded as an
/// `IterationFailure` in the returned `FuzzResult`.
///
/// The RNG's starting state is recorded in the returned `FuzzResult`. The
/// returned `trace_hash` is an order-sensitive SHA-256 hash chain over every
/// mutated input, acting as a compact fingerprint confirming two runs exercised
/// the same sequence of inputs.
pub fn run(
  seed_txs: List(SeedTx),
  iteration_count: Int,
  rng: Rng,
) -> FuzzResult {
  let rng_state = rng.state(rng)

  let #(failures, trace) =
    run_iterations(seed_txs, iteration_count, 1, [], trace.new(), rng)

  let failures = list.reverse(failures)
  let trace_hash = trace.to_hex(trace)

  FuzzResult(
    iteration_count:,
    initial_rng_state: rng_state,
    trace_hash:,
    failures:,
  )
}

/// Parses seed corpus file contents into transactions for the fuzz harness.
///
/// Each accepted line has the pipe-delimited form `txid|codes|hex`, where
/// `txid` is kept as a display-format identifier and `hex` is decoded into raw
/// transaction wire bytes. Lines that do not match that shape are ignored.
pub fn parse_seed_txs(file_content: String) -> List(SeedTx) {
  file_content
  |> string.split("\n")
  |> list.filter_map(fn(line) {
    case string.split(line, "|") {
      [txid, _codes, hex_str] -> {
        let assert Ok(bytes) = bit_array.base16_decode(hex_str)
        Ok(SeedTx(txid:, bytes:))
      }
      _ -> Error(Nil)
    }
  })
}

fn run_iterations(
  txs: List(SeedTx),
  remaining: Int,
  iteration: Int,
  acc: List(IterationFailure),
  trace: Trace,
  rng: Rng,
) -> #(List(IterationFailure), Trace) {
  case remaining == 0 {
    True -> #(acc, trace)
    False -> {
      let assert Ok(#(seed_tx, rng)) = sample_one(rng, from: txs)
      let #(mutated_tx, rng) = mutate(seed_tx, rng)

      let trace = trace.update(trace, mutated_tx.bytes)

      let iteration_result =
        exception.rescue(fn() { run_decode(mutated_tx.bytes) })

      let acc = case iteration_result {
        Ok(_) -> acc

        Error(exception) -> {
          let iteration_failure =
            IterationFailure(
              iteration:,
              mutated_tx:,
              mutated_tx_hex: bit_array.base16_encode(mutated_tx.bytes),
              exception:,
            )

          [iteration_failure, ..acc]
        }
      }

      run_iterations(txs, remaining - 1, iteration + 1, acc, trace, rng)
    }
  }
}

fn run_decode(mutated_tx_bytes: BitArray) -> Nil {
  case btc_tx.decode(mutated_tx_bytes) {
    Ok(decoded_tx) -> {
      case btc_tx.validate_consensus(decoded_tx) {
        Ok(validated_tx) -> {
          validated_tx
          |> btc_tx.get_outputs
          |> list.each(fn(txout) {
            txout
            |> btc_tx.get_output_script_pubkey
            |> btc_tx.classify_output_script
          })

          let _ = btc_tx.compute_txid(validated_tx)
          let _ = btc_tx.compute_wtxid(validated_tx)

          Nil
        }

        Error(_) -> Nil
      }
    }

    Error(_) -> Nil
  }
}

// Mutation

fn mutate(seed_tx: SeedTx, rng: Rng) -> #(MutatedTx, Rng) {
  let mutations = [
    #(Truncate, truncate),
    #(FlipBytes, flip_bytes),
    #(FlipBits, flip_bits),
    #(InsertBytes, insert_bytes),
    #(DeleteSpan, delete_span),
    #(DuplicateSpan, duplicate_span),
    #(ZeroSpan, zero_span),
    #(MutateSegwitMarker, mutate_segwit_marker),
    #(MutateCompactSizeCandidate, mutate_compact_size_candidate),
  ]

  let assert Ok(#(#(mutation, mutation_fn), rng)) = sample_one(rng, mutations)
  let #(mutated_bytes, rng) = mutation_fn(seed_tx.bytes, rng)
  #(MutatedTx(seed_tx:, mutation:, bytes: mutated_bytes), rng)
}

/// Cut the byte stream at a random position and discard everything after it.
///
/// Intended behavior:
/// - Return a prefix of the original bytes
/// - May remove part of a field, part of a varint, or the tail of the tx entirely
///
/// Fuzzing purpose:
/// - Exercise truncated-input handling
/// - Verify the parser fails cleanly on incomplete transactions
/// - Good for boundary checks and "unexpected EOF" style paths
fn truncate(bytes: BitArray, rng: Rng) -> #(BitArray, Rng) {
  let len = bit_array.byte_size(bytes)
  use <- bool.guard(len <= 1, #(bytes, rng))

  let #(slice_count, rng) = rng.next_bounded(rng, len)
  let assert Ok(sliced) = bit_array.slice(bytes, 0, slice_count)
  #(sliced, rng)
}

/// Replace 1–3 bytes at random positions with random replacement values.
///
/// Fuzzing purpose:
/// - Targets byte-level fields throughout the transaction: opcodes, varints, txids, amounts, and length prefixes
/// - Likely to hit many distinct parser paths per iteration
/// - Complementary to `FlipBits`: operates at byte granularity, producing more disruptive changes
fn flip_bytes(bytes: BitArray, rng: Rng) -> #(BitArray, Rng) {
  let len = bit_array.byte_size(bytes)
  use <- bool.guard(len == 0, #(bytes, rng))

  let #(extra, rng) = rng.next_bounded(rng, 3)
  flip_n_bytes(bytes, len, extra + 1, rng)
}

fn flip_n_bytes(
  bytes: BitArray,
  len: Int,
  remaining: Int,
  rng: Rng,
) -> #(BitArray, Rng) {
  case remaining == 0 {
    True -> #(bytes, rng)
    False -> {
      let #(offset, rng) = rng.next_bounded(rng, len)
      let #(new_byte, rng) = rng.next_bounded(rng, 256)
      let bytes = replace_byte_at(bytes, offset, new_byte)
      flip_n_bytes(bytes, len, remaining - 1, rng)
    }
  }
}

fn replace_byte_at(bytes: BitArray, offset: Int, value: Int) -> BitArray {
  let after_len = bit_array.byte_size(bytes) - offset - 1
  let assert Ok(before) = bit_array.slice(bytes, 0, offset)
  let assert Ok(after) = bit_array.slice(bytes, offset + 1, after_len)

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
fn flip_bits(bytes: BitArray, rng: Rng) -> #(BitArray, Rng) {
  let len = bit_array.byte_size(bytes)
  use <- bool.guard(len == 0, #(bytes, rng))

  let #(extra, rng) = rng.next_bounded(rng, 3)
  flip_n_bits(bytes, len, extra + 1, rng)
}

fn flip_n_bits(
  bytes: BitArray,
  len: Int,
  remaining: Int,
  rng: Rng,
) -> #(BitArray, Rng) {
  case remaining {
    0 -> #(bytes, rng)
    _ -> {
      let #(bit_idx, rng) = rng.next_bounded(rng, len * 8)
      let mask = int.bitwise_shift_left(1, bit_idx % 8)
      let bytes = xor_byte_at(bytes, bit_idx / 8, mask)
      flip_n_bits(bytes, len, remaining - 1, rng)
    }
  }
}

fn xor_byte_at(bytes: BitArray, offset: Int, mask: Int) -> BitArray {
  let after_len = bit_array.byte_size(bytes) - offset - 1
  let assert Ok(<<byte:8>>) = bit_array.slice(bytes, offset, 1)
  let assert Ok(before) = bit_array.slice(bytes, 0, offset)
  let assert Ok(after) = bit_array.slice(bytes, offset + 1, after_len)

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
fn insert_bytes(bytes: BitArray, rng: Rng) -> #(BitArray, Rng) {
  let len = bit_array.byte_size(bytes)

  // Insert at any position in [0, len], including the end.
  let #(offset, rng) = rng.next_bounded(rng, len + 1)
  let #(insert_len, rng) = rng.next_bounded(rng, 8)
  let #(inserted, rng) = random_bytes(rng, insert_len + 1)

  let assert Ok(before) = bit_array.slice(bytes, 0, offset)

  let after_len = len - offset
  let assert Ok(after) = bit_array.slice(bytes, offset, after_len)

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
fn delete_span(bytes: BitArray, rng: Rng) -> #(BitArray, Rng) {
  let len = bit_array.byte_size(bytes)
  use <- bool.guard(len <= 1, #(bytes, rng))

  let #(start, rng) = rng.next_bounded(rng, len)
  let #(span_len, rng) = rng.next_bounded(rng, 8)
  let span_len = int.min(span_len + 1, len - start)

  let assert Ok(before) = bit_array.slice(bytes, 0, start)

  let after_start = start + span_len
  let after_len = len - after_start
  let assert Ok(after) = bit_array.slice(bytes, after_start, after_len)

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
fn duplicate_span(bytes: BitArray, rng: Rng) -> #(BitArray, Rng) {
  let len = bit_array.byte_size(bytes)
  use <- bool.guard(len == 0, #(bytes, rng))

  let #(src, rng) = rng.next_bounded(rng, len)
  let #(span_len, rng) = rng.next_bounded(rng, 8)
  let span_len = int.min(span_len + 1, len - src)
  let assert Ok(span) = bit_array.slice(bytes, src, span_len)

  // Insert position is over the original length so the copy can land anywhere
  // including the end, independent of where it was copied from.
  let #(insert_at, rng) = rng.next_bounded(rng, len + 1)
  let assert Ok(before) = bit_array.slice(bytes, 0, insert_at)

  let after_len = len - insert_at
  let assert Ok(after) = bit_array.slice(bytes, insert_at, after_len)

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
fn zero_span(bytes: BitArray, rng: Rng) -> #(BitArray, Rng) {
  let len = bit_array.byte_size(bytes)
  use <- bool.guard(len == 0, #(bytes, rng))

  let #(start, rng) = rng.next_bounded(rng, len)
  let #(span_len, rng) = rng.next_bounded(rng, 8)
  let span_len = int.min(span_len + 1, len - start)

  let assert Ok(before) = bit_array.slice(bytes, 0, start)

  let after_start = start + span_len
  let after_len = len - after_start
  let assert Ok(after) = bit_array.slice(bytes, after_start, after_len)

  let result =
    before
    |> bit_array.append(zero_bytes(span_len))
    |> bit_array.append(after)

  #(result, rng)
}

fn zero_bytes(len: Int) -> BitArray {
  int.range(0, len, <<>>, fn(acc, _i) { bit_array.append(acc, <<0:8>>) })
}

/// Target the segwit marker/flag region at offsets 4–5 with one of five mutations:
/// corrupt the marker, corrupt the flag, remove the marker byte, remove the flag byte,
/// or overwrite both with random values.
///
/// Fuzzing purpose:
/// - Specifically stress legacy-vs-segwit dispatch logic
/// - Useful for parser paths that branch early based on marker/flag interpretation
/// - High value because mistakes here can throw off the interpretation of the entire remainder
fn mutate_segwit_marker(bytes: BitArray, rng: Rng) -> #(BitArray, Rng) {
  // The segwit marker/flag occupy bytes 4–5 (immediately after the 4-byte version).
  // We target this region regardless of whether the input is actually a segwit
  // transaction, since corrupting it stresses the legacy-vs-segwit dispatch.
  let len = bit_array.byte_size(bytes)
  use <- bool.guard(len < 6, #(bytes, rng))

  let #(n, rng) = rng.next_bounded(rng, 5)
  case n {
    // Flip the marker byte (offset 4) to a random nonzero value.
    0 -> {
      let #(v, rng) = rng.next_bounded(rng, 255)
      #(replace_byte_at(bytes, 4, v + 1), rng)
    }
    // Flip the flag byte (offset 5) to a value other than 0x01.
    1 -> {
      let #(v, rng) = rng.next_bounded(rng, 254)
      #(replace_byte_at(bytes, 5, v + 2), rng)
    }
    // Remove the marker byte entirely, shifting everything after it left by one.
    2 -> {
      let assert Ok(before) = bit_array.slice(bytes, 0, 4)
      let assert Ok(after) = bit_array.slice(bytes, 5, len - 5)
      #(bit_array.append(before, after), rng)
    }
    // Remove the flag byte entirely.
    3 -> {
      let assert Ok(before) = bit_array.slice(bytes, 0, 5)
      let assert Ok(after) = bit_array.slice(bytes, 6, len - 6)
      #(bit_array.append(before, after), rng)
    }
    // Overwrite both bytes with independent random values (bogus marker/flag combo).
    _ -> {
      let #(m, rng) = rng.next_bounded(rng, 256)
      let #(f, rng) = rng.next_bounded(rng, 256)
      let bytes = replace_byte_at(bytes, 4, m)
      #(replace_byte_at(bytes, 5, f), rng)
    }
  }
}

type CompactSizeCandidate {
  CompactSizeCandidate(start: Int, width: Int, value: Int)
}

/// Scan the byte stream for heuristic CompactSize candidates, select one at
/// random, and apply a targeted mutation to it.
///
/// Fuzzing purpose:
/// - Targets length-prefixed fields (vin/vout counts, script lengths, witness item lengths)
///   throughout the transaction without requiring structural knowledge of the format
/// - Non-minimal encoding directly targets a protocol rule the parser must enforce
/// - Preserves enough surrounding structure that malformed inputs are likely to reach
///   inner parsing logic rather than being rejected at a boundary check
fn mutate_compact_size_candidate(
  bytes: BitArray,
  rng: Rng,
) -> #(BitArray, Rng) {
  case find_compact_size_candidates(bytes) {
    [] -> #(bytes, rng)

    candidates -> {
      let assert Ok(#(candidate, rng)) = sample_one(rng, candidates)
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
  }
}

fn find_compact_size_candidates(bytes: BitArray) -> List(CompactSizeCandidate) {
  let len = bit_array.byte_size(bytes)

  // Accumulate in reverse for O(1) prepends, then restore order at the end.
  bytes
  |> find_compact_size_candidates_loop(len, 0, [])
  |> list.reverse
}

fn find_compact_size_candidates_loop(
  bytes: BitArray,
  len: Int,
  offset: Int,
  acc: List(CompactSizeCandidate),
) -> List(CompactSizeCandidate) {
  case offset >= len {
    True -> acc
    False -> {
      let assert Ok(<<prefix:8>>) = bit_array.slice(bytes, offset, 1)
      case prefix {
        // 0x00–0xFC: single-byte encoding; the byte itself is the value.
        // Advance by 1 so subsequent bytes are also eligible as candidates.
        p if p <= 0xFC -> {
          let candidate =
            CompactSizeCandidate(start: offset, width: 1, value: p)

          find_compact_size_candidates_loop(bytes, len, offset + 1, [
            candidate,
            ..acc
          ])
        }

        // 0xFD: 3-byte encoding — prefix + 2 LE bytes.
        // Only emit a candidate if 2 bytes actually follow; otherwise fall
        // through to the skip case below.
        0xFD if offset + 3 <= len -> {
          let assert Ok(<<lo:8, hi:8>>) = bit_array.slice(bytes, offset + 1, 2)
          let value = lo + hi * 256
          let candidate = CompactSizeCandidate(start: offset, width: 3, value:)
          // Advance past all 3 bytes so they aren't double-counted.
          find_compact_size_candidates_loop(bytes, len, offset + 3, [
            candidate,
            ..acc
          ])
        }

        // 0xFE: 5-byte encoding — prefix + 4 LE bytes.
        // Same guard: only emit if 4 bytes follow.
        0xFE if offset + 5 <= len -> {
          let assert Ok(<<b0:8, b1:8, b2:8, b3:8>>) =
            bit_array.slice(bytes, offset + 1, 4)

          let value = b0 + b1 * 256 + b2 * 65_536 + b3 * 16_777_216
          let candidate = CompactSizeCandidate(start: offset, width: 5, value:)
          find_compact_size_candidates_loop(bytes, len, offset + 5, [
            candidate,
            ..acc
          ])
        }

        // 0xFF (9-byte encoding) is skipped entirely: the value range exceeds
        // JavaScript's 53-bit safe integer limit. Incomplete 0xFD/0xFE
        // (not enough trailing bytes) also land here and are skipped.
        _ -> find_compact_size_candidates_loop(bytes, len, offset + 1, acc)
      }
    }
  }
}

fn rewrite_compact_size(
  bytes: BitArray,
  candidate: CompactSizeCandidate,
  new_value: Int,
) -> BitArray {
  let after_start = candidate.start + candidate.width
  let after_len = bit_array.byte_size(bytes) - after_start
  let encoded = encode_compact_size(new_value)

  let assert Ok(before) = bit_array.slice(bytes, 0, candidate.start)
  let assert Ok(after) = bit_array.slice(bytes, after_start, after_len)
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
  let after_len = bit_array.byte_size(bytes) - after_start

  let assert Ok(before) = bit_array.slice(bytes, 0, candidate.start)
  let assert Ok(after) = bit_array.slice(bytes, after_start, after_len)

  before
  |> bit_array.append(promoted)
  |> bit_array.append(after)
}

fn truncate_compact_size(
  bytes: BitArray,
  candidate: CompactSizeCandidate,
) -> BitArray {
  let after_start = candidate.start + candidate.width
  let after_len = bit_array.byte_size(bytes) - after_start

  let assert Ok(prefix) = bit_array.slice(bytes, 0, candidate.start)
  let assert Ok(suffix) = bit_array.slice(bytes, after_start, after_len)

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

/// Selects one item from `items` uniformly at random and returns it alongside
/// the new RNG state. Returns `Error(Nil)` for empty lists.
fn sample_one(rng: Rng, from items: List(a)) -> Result(#(a, Rng), Nil) {
  case list.length(items) {
    0 -> Error(Nil)
    len -> {
      let #(idx, rng) = rng.next_bounded(rng, len)
      let assert Ok(item) = list.first(list.drop(items, idx))
      Ok(#(item, rng))
    }
  }
}

/// Generates `len` pseudo-random bytes and returns them as a `BitArray`
/// alongside the new RNG state.
fn random_bytes(rng: Rng, len: Int) -> #(BitArray, Rng) {
  let #(bytes, rng) =
    int.range(0, len, #([], rng), fn(acc, _i) {
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
