////  Fuzz testing harness for the `btc_parser/transaction` transaction parser.
////
////  The goal is to guarantee that *any* byte input results in either successful
////  deserialization or a well-defined error — never an unhandled exception.
////  Each run receives a corpus of real Bitcoin transactions, applies random
////  structural mutations, and exercises deserialization, validation,
////  inspection, serialization, and txid/wtxid computation. Using real
////  transactions as a baseline produces higher-quality mutations than pure
////  random bytes: they are structurally
////  plausible, so mutations are more likely to reach deep parser paths rather
////  than being rejected at early boundary checks.

import btc_parser/transaction
import btc_parser_fuzz/internal/mutation
import btc_parser_fuzz/internal/rng.{type Rng}
import btc_parser_fuzz/internal/trace.{type Trace}
import exception.{type Exception}
import gleam/bit_array
import gleam/bool
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
    /// Exception rescued while deserializing, validating, inspecting, serializing,
    /// or hashing the mutated transaction.
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
/// applies a structural mutation, and exercises deserialization plus the related
/// validation, inspection, serialization, and hashing APIs. Any unhandled
/// exception is recorded as an `IterationFailure` in the returned `FuzzResult`.
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
      let assert Ok(#(seed_tx, rng)) = rng.sample_one(rng, from: txs)
      let #(mutated_tx, rng) = mutate(seed_tx, rng)

      let trace = trace.update(trace, mutated_tx.bytes)

      let iteration_result =
        exception.rescue(fn() { run_deserialize(mutated_tx.bytes) })

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

fn run_deserialize(mutated_tx_bytes: BitArray) -> Nil {
  case transaction.deserialize(mutated_tx_bytes) {
    Ok(tx) -> {
      let _ = transaction.validate_context_free_consensus(tx)

      tx
      |> transaction.get_outputs
      |> list.each(fn(output) {
        output
        |> transaction.get_output_script_pubkey
        |> transaction.classify_output_script
      })

      let _ = transaction.serialize_stripped(tx)
      assert transaction.serialize(tx) == mutated_tx_bytes

      let _ = transaction.compute_txid(tx)
      let _ = transaction.compute_wtxid(tx)

      Nil
    }

    Error(_) -> Nil
  }
}

// Mutation

fn mutate(seed_tx: SeedTx, rng: Rng) -> #(MutatedTx, Rng) {
  let mutations = [
    #(Truncate, mutation.truncate),
    #(FlipBytes, mutation.flip_bytes),
    #(FlipBits, mutation.flip_bits),
    #(InsertBytes, mutation.insert_bytes),
    #(DeleteSpan, mutation.delete_span),
    #(DuplicateSpan, mutation.duplicate_span),
    #(ZeroSpan, mutation.zero_span),
    #(MutateSegwitMarker, mutate_segwit_marker),
    #(
      MutateCompactSizeCandidate,
      mutation.mutate_heuristic_compact_size_candidate,
    ),
  ]

  let assert Ok(#(#(mutation, mutation_fn), rng)) =
    rng.sample_one(rng, mutations)

  let #(mutated_bytes, rng) = mutation_fn(seed_tx.bytes, rng)
  #(MutatedTx(seed_tx:, mutation:, bytes: mutated_bytes), rng)
}

/// Target the SegWit marker/flag region at offsets 4–5 with one of five mutations:
/// corrupt the marker, corrupt the flag, remove the marker byte, remove the flag byte,
/// or overwrite both with random values.
///
/// Fuzzing purpose:
/// - Specifically stress legacy-vs-SegWit dispatch logic
/// - Useful for parser paths that branch early based on marker/flag interpretation
/// - High value because mistakes here can throw off the interpretation of the entire remainder
fn mutate_segwit_marker(bytes: BitArray, rng: Rng) -> #(BitArray, Rng) {
  // The SegWit marker/flag occupy bytes 4–5 (immediately after the 4-byte version).
  // We target this region regardless of whether the input is actually a SegWit
  // transaction, since corrupting it stresses the legacy-vs-SegWit dispatch.
  let length = bit_array.byte_size(bytes)
  use <- bool.guard(length < 6, #(bytes, rng))

  let #(n, rng) = rng.next_bounded(rng, 5)
  case n {
    // Flip the marker byte (offset 4) to a random nonzero value.
    0 -> {
      let #(v, rng) = rng.next_bounded(rng, 255)
      #(mutation.replace_byte_at(bytes, 4, v + 1), rng)
    }
    // Flip the flag byte (offset 5) to a value other than 0x01.
    1 -> {
      let #(v, rng) = rng.next_bounded(rng, 254)
      #(mutation.replace_byte_at(bytes, 5, v + 2), rng)
    }
    // Remove the marker byte entirely, shifting everything after it left by one.
    2 -> {
      let assert Ok(before) = bit_array.slice(bytes, 0, 4)
      let assert Ok(after) = bit_array.slice(bytes, 5, length - 5)
      #(bit_array.append(before, after), rng)
    }
    // Remove the flag byte entirely.
    3 -> {
      let assert Ok(before) = bit_array.slice(bytes, 0, 5)
      let assert Ok(after) = bit_array.slice(bytes, 6, length - 6)
      #(bit_array.append(before, after), rng)
    }
    // Overwrite both bytes with independent random values (bogus marker/flag combo).
    _ -> {
      let #(m, rng) = rng.next_bounded(rng, 256)
      let #(f, rng) = rng.next_bounded(rng, 256)
      let bytes = mutation.replace_byte_at(bytes, 4, m)
      #(mutation.replace_byte_at(bytes, 5, f), rng)
    }
  }
}
