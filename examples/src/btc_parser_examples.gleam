//// Run live-data btc_parser examples with `./examples/run -- <example>`.

import argv
import btc_parser/block
import btc_parser/transaction
import btc_parser_examples/diagnostic_json
import btc_parser_examples/display
import btc_parser_examples/mempool_client
import btc_parser_examples/metrics
import btc_parser_examples/metrics_json
import btc_parser_examples/transaction_json
import gleam/int
import gleam/io
import gleam/json.{type Json}
import gleam/result

const mainnet_pow_limit_bytes = <<
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0x00,
  0x00,
  0x00,
  0x00,
>>

pub fn main() -> Nil {
  case run(argv.load().arguments) {
    Ok(output) ->
      output
      |> json.to_string
      |> io.println
    Error(message) -> panic as message
  }
}

fn run(arguments: List(String)) -> Result(Json, String) {
  case arguments {
    ["transaction-json", txid] -> transaction_json_example(txid)
    ["block-metrics", height] -> block_metrics_example(height)
    ["validate-block", height] -> validate_block_example(height)
    ["safe-decode", transaction_hex] -> safe_decode_example(transaction_hex)
    _ -> Error(usage())
  }
}

fn transaction_json_example(txid: String) -> Result(Json, String) {
  use bytes <- result.try(
    txid
    |> mempool_client.get_transaction_bytes
    |> result.map_error(mempool_client.error_message),
  )

  case transaction.deserialize(bytes) {
    Ok(tx) ->
      Ok(
        json.object([
          #("outcome", json.string("decoded")),
          #("requested_txid", json.string(txid)),
          #("transaction", transaction_json.encode(tx)),
        ]),
      )
    Error(error) ->
      Ok(
        json.object([
          #("outcome", json.string("decode_error")),
          #("requested_txid", json.string(txid)),
          #("decode_error", diagnostic_json.transaction_decode_error(error)),
        ]),
      )
  }
}

fn block_metrics_example(height_argument: String) -> Result(Json, String) {
  use height <- result.try(parse_height(height_argument))
  use #(block_hash, bytes) <- result.try(fetch_block(height))

  case block.deserialize(bytes) {
    Ok(block_value) ->
      Ok(
        json.object([
          #("outcome", json.string("decoded")),
          #("height", json.int(height)),
          #("block_hash", json.string(block_hash)),
          #(
            "metrics",
            metrics_json.block_metrics(metrics.block_metrics(block_value)),
          ),
        ]),
      )
    Error(error) ->
      Ok(
        json.object([
          #("outcome", json.string("decode_error")),
          #("height", json.int(height)),
          #("block_hash", json.string(block_hash)),
          #("decode_error", diagnostic_json.block_decode_error(error)),
        ]),
      )
  }
}

fn validate_block_example(height_argument: String) -> Result(Json, String) {
  use height <- result.try(parse_height(height_argument))
  use #(requested_block_hash, bytes) <- result.try(fetch_block(height))

  case block.deserialize(bytes) {
    Error(error) ->
      Ok(
        json.object([
          #("outcome", json.string("decode_error")),
          #("height", json.int(height)),
          #("block_hash", json.string(requested_block_hash)),
          #("decode_error", diagnostic_json.block_decode_error(error)),
        ]),
      )
    Ok(block_value) -> {
      let computed_block_hash =
        display.hash(block.compute_block_hash(block_value))
      let serialization_round_trips = block.serialize(block_value) == bytes
      let block_hash_matches_requested =
        computed_block_hash == requested_block_hash

      case
        block.validate_context_free_consensus(block_value, mainnet_pow_limit())
      {
        Ok(_) ->
          Ok(
            validation_report(
              "validated",
              height,
              requested_block_hash,
              computed_block_hash,
              block_hash_matches_requested,
              serialization_round_trips,
              True,
              [],
            ),
          )
        Error(violations) ->
          Ok(validation_report(
            "validation_failed",
            height,
            requested_block_hash,
            computed_block_hash,
            block_hash_matches_requested,
            serialization_round_trips,
            False,
            violations,
          ))
      }
    }
  }
}

fn safe_decode_example(transaction_hex: String) -> Result(Json, String) {
  case transaction.deserialize_hex(transaction_hex) {
    Ok(tx) ->
      Ok(
        json.object([
          #("outcome", json.string("decoded")),
          #("transaction", transaction_json.encode(tx)),
        ]),
      )
    Error(error) -> Ok(diagnostic_json.transaction_deserialize_hex_error(error))
  }
}

fn validation_report(
  outcome: String,
  height: Int,
  requested_block_hash: String,
  computed_block_hash: String,
  block_hash_matches_requested: Bool,
  serialization_round_trips: Bool,
  context_free_valid: Bool,
  violations: List(block.ConsensusViolation),
) -> Json {
  json.object([
    #("outcome", json.string(outcome)),
    #("height", json.int(height)),
    #("block_hash", json.string(requested_block_hash)),
    #("computed_block_hash", json.string(computed_block_hash)),
    #("block_hash_matches_requested", json.bool(block_hash_matches_requested)),
    #("serialization_round_trips", json.bool(serialization_round_trips)),
    #("context_free_valid", json.bool(context_free_valid)),
    #("violations", diagnostic_json.block_violations(violations)),
  ])
}

fn fetch_block(height: Int) -> Result(#(String, BitArray), String) {
  use block_hash <- result.try(
    height
    |> mempool_client.get_block_hash
    |> result.map_error(mempool_client.error_message),
  )
  use bytes <- result.try(
    block_hash
    |> mempool_client.get_raw_block
    |> result.map_error(mempool_client.error_message),
  )

  Ok(#(block_hash, bytes))
}

fn parse_height(argument: String) -> Result(Int, String) {
  case int.parse(argument) {
    Ok(height) if height >= 0 -> Ok(height)
    _ -> Error("expected a non-negative block height")
  }
}

fn mainnet_pow_limit() -> block.PowLimit {
  let assert Ok(pow_limit) = block.new_pow_limit(mainnet_pow_limit_bytes)
  pow_limit
}

fn usage() -> String {
  "usage: ./examples/run -- <example> [arguments]\n\n"
  <> "examples:\n"
  <> "  transaction-json <txid>\n"
  <> "  block-metrics <height>\n"
  <> "  validate-block <height>\n"
  <> "  safe-decode <transaction-hex>"
}
