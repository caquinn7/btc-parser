//// Test-only assertions shared by transaction and block test modules.

import btc_parser/transaction.{type DecodeError, type DecodeErrorKind}

/// Assert the common location details of a transaction decode error and return
/// its kind for the caller to compare.
pub fn check_transaction_decode_error(
  error: DecodeError,
  expected_offset: Int,
  expected_path: String,
) -> DecodeErrorKind {
  assert transaction.get_decode_error_offset(error) == expected_offset
  assert transaction.get_decode_error_path(error) == expected_path
  transaction.get_decode_error_kind(error)
}
