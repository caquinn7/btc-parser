import btc_parser_fuzz/fuzz_result.{type FuzzResult}
import gleam/int
import gleam/list
import gleam/string

pub fn to_string(
  fuzz_result: FuzzResult(failure),
  elapsed_ms: Int,
  failure_to_string: fn(failure) -> String,
) -> String {
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
      <> string.join(list.map(failures, failure_to_string), "\n\n")
  }
}
