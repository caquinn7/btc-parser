/// Results for one invocation of a fuzz suite.
pub type FuzzResult(failure) {
  FuzzResult(
    /// Number of mutation iterations requested for the run.
    iteration_count: Int,
    /// RNG state captured before the first mutation is selected.
    initial_rng_state: Int,
    /// Hex-encoded, order-sensitive SHA-256 hash chain for all mutated inputs.
    /// This acts as a compact fingerprint for reproducible runs.
    trace_hash: String,
    /// Unhandled exceptions rescued while exercising mutated inputs.
    failures: List(failure),
  )
}
