/// A deterministic pseudo-random number generator based on the Park-Miller
/// LCG. Holds the current generator state, which is advanced by each call to
/// `next_int` and `next_bounded`.
pub opaque type Rng {
  Rng(state: Int)
}

/// Creates a deterministic generator from an integer seed.
pub fn new(seed: Int) -> Rng {
  let s = seed % 2_147_483_647
  let state = case s {
    0 -> 1
    _ if s < 0 -> s + 2_147_483_647
    _ -> s
  }
  Rng(state)
}

/// Returns the generator's current state.
pub fn state(rng: Rng) -> Int {
  rng.state
}

/// Advances the RNG by one step and returns the raw output value alongside
/// the new RNG state.
///
/// Intermediate products stay below 2^47, within JavaScript's 53-bit safe
/// integer range, so the sequence is identical on both Erlang and JavaScript
/// targets.
pub fn next_int(rng: Rng) -> #(Int, Rng) {
  let state = 48_271 * rng.state % 2_147_483_647
  #(state, Rng(state))
}

/// Returns a value in `[0, max)` and the new RNG state.
pub fn next_bounded(rng: Rng, max: Int) -> #(Int, Rng) {
  let #(n, rng) = next_int(rng)
  #(n % max, rng)
}
