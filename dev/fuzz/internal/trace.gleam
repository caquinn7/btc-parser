import gleam/bit_array
import gleam/crypto.{Sha256}

/// An order-sensitive SHA-256 fingerprint for a sequence of inputs.
pub opaque type Trace {
  Trace(digest: BitArray)
}

/// Creates an empty trace.
pub fn new() -> Trace {
  Trace(<<0:256>>)
}

/// Adds an input to the trace and returns the updated trace.
///
/// Each update computes `SHA256(previous_digest || SHA256(input))`.
pub fn update(trace: Trace, input: BitArray) -> Trace {
  let input_digest = crypto.hash(Sha256, input)
  let digest = crypto.hash(Sha256, bit_array.append(trace.digest, input_digest))
  Trace(digest)
}

/// Returns the trace digest as hexadecimal text.
pub fn to_hex(trace: Trace) -> String {
  bit_array.base16_encode(trace.digest)
}
