import btc_parser/internal/double_sha256
import gleam/bit_array

pub fn hash_matches_known_double_sha256_vector_test() {
  let assert Ok(expected) =
    bit_array.base16_decode(
      "4f8b42c22dd3729b519ba6f68d2da7cc5b2d606d05daed5ad5128cc03e6c6358",
    )

  assert double_sha256.hash(<<"abc":utf8>>) == expected
}
