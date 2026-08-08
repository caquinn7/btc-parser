//// Target-efficient double-SHA-256 hashing for complete byte arrays.

/// Hash a complete byte array twice with SHA-256.
///
/// The Erlang target uses the one-shot `crypto:hash/2` primitive. JavaScript
/// uses its target-specific implementation so runtimes can select the most
/// efficient supported one-shot operation while retaining a compatibility
/// fallback.
@external(erlang, "double_sha256_ffi", "hash")
@external(javascript, "./double_sha256_ffi.mjs", "hash")
pub fn hash(bytes: BitArray) -> BitArray
