import fuzz/transaction/suite.{type FuzzResult, type IterationFailure}
import gleam/int
import gleam/list
import gleam/string

pub fn to_string(fuzz_result: FuzzResult, elapsed_ms: Int) -> String {
  let header =
    "iterations: "
    <> int.to_string(fuzz_result.iteration_count)
    <> "\ninitial rng state: "
    <> int.to_string(fuzz_result.initial_rng_state)
    <> "\ntrace: "
    <> fuzz_result.trace_hash
    <> "\ntime: "
    <> int.to_string(elapsed_ms)
    <> " ms"
    <> "\nfailures: "
    <> int.to_string(list.length(fuzz_result.failures))

  case fuzz_result.failures {
    [] -> header

    failures ->
      header
      <> "\n\n"
      <> string.join(list.map(failures, iteration_failure_to_string), "\n\n")
  }
}

fn iteration_failure_to_string(failure: IterationFailure) -> String {
  "  #"
  <> int.to_string(failure.iteration)
  <> "\n    seed_tx: "
  <> failure.mutated_tx.seed_tx.txid
  <> "\n    mutation: "
  <> string.inspect(failure.mutated_tx.mutation)
  <> "\n    hex: "
  <> failure.mutated_tx_hex
  <> "\n    exception: "
  <> string.inspect(failure.exception)
}
