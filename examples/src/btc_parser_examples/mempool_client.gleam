//// Minimal mainnet mempool.space client used only by the examples project.

import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/httpc
import gleam/int
import gleam/result

pub type RequestError {
  HttpError(httpc.HttpError)
  StatusCodeError(Int)
}

pub fn get_transaction_bytes(txid: String) -> Result(BitArray, RequestError) {
  get_bytes("/api/tx/" <> txid <> "/raw")
}

pub fn get_block_hash(block_height: Int) -> Result(String, RequestError) {
  get_string("/api/block-height/" <> int.to_string(block_height))
}

pub fn get_raw_block(block_hash: String) -> Result(BitArray, RequestError) {
  get_bytes("/api/block/" <> block_hash <> "/raw")
}

pub fn error_message(error: RequestError) -> String {
  case error {
    HttpError(_) -> "mempool.space request failed"
    StatusCodeError(status) ->
      "mempool.space returned HTTP " <> int.to_string(status)
  }
}

fn get_bytes(path: String) -> Result(BitArray, RequestError) {
  path
  |> new_request
  |> request.set_body(<<>>)
  |> httpc.send_bits
  |> result.map_error(HttpError)
  |> result.try(map_response)
}

fn get_string(path: String) -> Result(String, RequestError) {
  path
  |> new_request
  |> httpc.send
  |> result.map_error(HttpError)
  |> result.try(map_response)
}

fn new_request(path: String) -> Request(String) {
  request.new()
  |> request.set_host("mempool.space")
  |> request.set_path(path)
}

fn map_response(response: Response(body)) -> Result(body, RequestError) {
  case response.status {
    200 -> Ok(response.body)
    status -> Error(StatusCodeError(status))
  }
}
