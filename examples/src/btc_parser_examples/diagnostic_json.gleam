//// JSON diagnostics for public btc_parser decode and validation errors.

import btc_parser/block
import btc_parser/transaction
import btc_parser_examples/display
import gleam/json.{type Json}

pub fn transaction_deserialize_hex_error(
  error: transaction.DeserializeHexError,
) -> Json {
  case error {
    transaction.InvalidHex ->
      json.object([#("outcome", json.string("invalid_hex"))])
    transaction.DecodeFailed(decode_error) ->
      json.object([
        #("outcome", json.string("decode_error")),
        #("decode_error", transaction_decode_error(decode_error)),
      ])
  }
}

pub fn transaction_decode_error(error: transaction.DecodeError) -> Json {
  json.object([
    #("offset", json.int(transaction.get_decode_error_offset(error))),
    #("path", json.string(transaction.get_decode_error_path(error))),
    #(
      "details",
      transaction_decode_error_kind(transaction.get_decode_error_kind(error)),
    ),
  ])
}

pub fn block_decode_error(error: block.DecodeError) -> Json {
  json.object([
    #("offset", json.int(block.get_decode_error_offset(error))),
    #("path", json.string(block.get_decode_error_path(error))),
    #("details", block_decode_error_kind(block.get_decode_error_kind(error))),
  ])
}

pub fn block_violations(values: List(block.ConsensusViolation)) -> Json {
  json.array(values, block_violation)
}

fn transaction_decode_error_kind(error: transaction.DecodeErrorKind) -> Json {
  case error {
    transaction.NonByteAlignedInput(bit_count) ->
      json.object([
        #("kind", json.string("non_byte_aligned_input")),
        #("bit_count", json.int(bit_count)),
      ])
    transaction.UnexpectedEof(bytes_needed, remaining) ->
      json.object([
        #("kind", json.string("unexpected_eof")),
        #("bytes_needed", json.int(bytes_needed)),
        #("remaining", json.int(remaining)),
      ])
    transaction.NonMinimalCompactSize(encoded_size, value) ->
      json.object([
        #("kind", json.string("non_minimal_compact_size")),
        #("encoded_size", json.int(encoded_size)),
        #("value", json.int(value)),
      ])
    transaction.InvalidSegwitMarkerFlag(marker, flag) ->
      json.object([
        #("kind", json.string("invalid_segwit_marker_flag")),
        #("marker", json.int(marker)),
        #("flag", json.int(flag)),
      ])
    transaction.SuperfluousWitnessRecord ->
      json.object([#("kind", json.string("superfluous_witness_record"))])
    transaction.InsufficientBytes(claimed, remaining) ->
      json.object([
        #("kind", json.string("insufficient_bytes")),
        #("claimed", json.int(claimed)),
        #("remaining", json.int(remaining)),
      ])
    transaction.IntegerOutOfRange(value) ->
      json.object([
        #("kind", json.string("integer_out_of_range")),
        #("value", json.string(value)),
      ])
    transaction.PolicyLimitExceeded(limit, value, max) ->
      json.object([
        #("kind", json.string("policy_limit_exceeded")),
        #("limit", json.string(transaction_decode_policy_limit(limit))),
        #("value", json.int(value)),
        #("max", json.int(max)),
      ])
    transaction.TrailingBytes(count) ->
      json.object([
        #("kind", json.string("trailing_bytes")),
        #("count", json.int(count)),
      ])
  }
}

fn transaction_decode_policy_limit(
  value: transaction.DecodePolicyLimit,
) -> String {
  case value {
    transaction.MaxTransactionSize -> "max_transaction_size"
    transaction.MaxInputCount -> "max_input_count"
    transaction.MaxOutputCount -> "max_output_count"
    transaction.MaxScriptSize -> "max_script_size"
    transaction.MaxWitnessStackItemCount -> "max_witness_stack_item_count"
    transaction.MaxWitnessStackPayloadSize -> "max_witness_stack_payload_size"
  }
}

fn block_decode_error_kind(error: block.DecodeErrorKind) -> Json {
  case error {
    block.NonByteAlignedInput(bit_count) ->
      json.object([
        #("kind", json.string("non_byte_aligned_input")),
        #("bit_count", json.int(bit_count)),
      ])
    block.UnexpectedEof(bytes_needed, remaining) ->
      json.object([
        #("kind", json.string("unexpected_eof")),
        #("bytes_needed", json.int(bytes_needed)),
        #("remaining", json.int(remaining)),
      ])
    block.NonMinimalCompactSize(encoded_size, value) ->
      json.object([
        #("kind", json.string("non_minimal_compact_size")),
        #("encoded_size", json.int(encoded_size)),
        #("value", json.int(value)),
      ])
    block.InsufficientBytes(claimed, remaining) ->
      json.object([
        #("kind", json.string("insufficient_bytes")),
        #("claimed", json.int(claimed)),
        #("remaining", json.int(remaining)),
      ])
    block.IntegerOutOfRange(value) ->
      json.object([
        #("kind", json.string("integer_out_of_range")),
        #("value", json.string(value)),
      ])
    block.TransactionDecodeFailed(transaction_error) ->
      json.object([
        #("kind", json.string("transaction_decode_failed")),
        #("transaction_error", transaction_decode_error(transaction_error)),
      ])
    block.PolicyLimitExceeded(limit, value, max) ->
      json.object([
        #("kind", json.string("policy_limit_exceeded")),
        #("limit", json.string(block_decode_policy_limit(limit))),
        #("value", json.int(value)),
        #("max", json.int(max)),
      ])
    block.TrailingBytes(count) ->
      json.object([
        #("kind", json.string("trailing_bytes")),
        #("count", json.int(count)),
      ])
  }
}

fn block_decode_policy_limit(value: block.DecodePolicyLimit) -> String {
  case value {
    block.MaxBlockSize -> "max_block_size"
    block.MaxTransactionCount -> "max_transaction_count"
  }
}

fn block_violation(value: block.ConsensusViolation) -> Json {
  case value {
    block.NoTransactions ->
      json.object([#("kind", json.string("no_transactions"))])
    block.ImpossiblyLargeTransactionCount ->
      json.object([#("kind", json.string("impossibly_large_transaction_count"))])
    block.InvalidProofOfWork ->
      json.object([#("kind", json.string("invalid_proof_of_work"))])
    block.BaseSizeLimitExceeded(size) ->
      json.object([
        #("kind", json.string("base_size_limit_exceeded")),
        #("size", json.int(size)),
      ])
    block.WeightLimitExceeded(weight) ->
      json.object([
        #("kind", json.string("weight_limit_exceeded")),
        #("weight", json.int(weight)),
      ])
    block.MerkleRootMismatch(actual, expected) ->
      json.object([
        #("kind", json.string("merkle_root_mismatch")),
        #("actual", json.string(display.hash(actual))),
        #("expected", json.string(display.hash(expected))),
      ])
    block.MutatedMerkleTree ->
      json.object([#("kind", json.string("mutated_merkle_tree"))])
    block.MissingCoinbase ->
      json.object([#("kind", json.string("missing_coinbase"))])
    block.UnexpectedCoinbase(index) ->
      json.object([
        #("kind", json.string("unexpected_coinbase")),
        #("index", json.int(index)),
      ])
    block.LegacySigOpLimitExceeded(sigop_count) ->
      json.object([
        #("kind", json.string("legacy_sigop_limit_exceeded")),
        #("sigop_count", json.int(sigop_count)),
      ])
    block.InvalidTransaction(index, violations) ->
      json.object([
        #("kind", json.string("invalid_transaction")),
        #("index", json.int(index)),
        #("violations", json.array(violations, transaction_violation)),
      ])
  }
}

fn transaction_violation(value: transaction.ConsensusViolation) -> Json {
  case value {
    transaction.NoInputs -> json.object([#("kind", json.string("no_inputs"))])
    transaction.NoOutputs -> json.object([#("kind", json.string("no_outputs"))])
    transaction.BaseSizeLimitExceeded(size) ->
      json.object([
        #("kind", json.string("base_size_limit_exceeded")),
        #("size", json.int(size)),
      ])
    transaction.OutputValueOutOfRange(index, value) ->
      json.object([
        #("kind", json.string("output_value_out_of_range")),
        #("index", json.int(index)),
        #("value_satoshis", json.int(value)),
      ])
    transaction.TotalOutputValueOutOfRange(index, total) ->
      json.object([
        #("kind", json.string("total_output_value_out_of_range")),
        #("index", json.int(index)),
        #("total_satoshis", json.int(total)),
      ])
    transaction.CoinbaseWithMultipleInputs ->
      json.object([#("kind", json.string("coinbase_with_multiple_inputs"))])
    transaction.InvalidCoinbaseScriptSigLength ->
      json.object([#("kind", json.string("invalid_coinbase_script_sig_length"))])
    transaction.DuplicateInput(outpoint, first_index, duplicate_index) ->
      json.object([
        #("kind", json.string("duplicate_input")),
        #(
          "outpoint",
          json.object([
            #(
              "txid",
              json.string(display.hash(transaction.get_outpoint_txid(outpoint))),
            ),
            #("vout", json.int(transaction.get_outpoint_vout(outpoint))),
          ]),
        ),
        #("first_index", json.int(first_index)),
        #("duplicate_index", json.int(duplicate_index)),
      ])
  }
}
