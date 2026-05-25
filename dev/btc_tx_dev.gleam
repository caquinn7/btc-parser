import argv
import fuzz_test/fuzz_test.{type FuzzResult, type IterationFailure, type SeedTx}
import gleam/crypto
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import perf_test/perf_test.{type PerfCaseResult, type PerfResult}
import simplifile

const usage_msg = "usage:
  gleam dev [OPTIONS] fuzz <iterations> [seed]
  gleam dev [OPTIONS] perf"

pub fn main() {
  case argv.load().arguments {
    ["fuzz", ..args] -> fuzz_command(args)
    ["perf"] -> perf_command()
    _ -> io.println(usage_msg)
  }
}

fn perf_command() -> Nil {
  io.println("Executing performance tests...\n")

  perf_test.run()
  |> perf_result_to_string
  |> io.println
}

fn perf_result_to_string(perf_result: PerfResult) -> String {
  perf_result.cases
  |> list.map(perf_case_result_to_string)
  |> string.join("\n\n")
}

fn perf_case_result_to_string(case_result: PerfCaseResult) -> String {
  "case: "
  <> case_result.label
  <> "\ninput size: "
  <> int.to_string(case_result.input_size_bytes)
  <> " bytes"
  <> "\noperations per timed call: "
  <> int.to_string(case_result.config.operations_per_timed_call)
  <> " operations"
  <> "\nwarmup: "
  <> int.to_string(case_result.config.warmup_ms)
  <> "ms"
  <> "\nduration: "
  <> int.to_string(case_result.config.duration_ms)
  <> "ms"
  <> "\ntimed calls recorded: "
  <> int.to_string(case_result.timed_call_count)
  <> "\nmeasured time: "
  <> float.to_string(float.to_precision(case_result.measured_ms, 3))
  <> "ms"
  <> "\nthroughput: "
  <> float.to_string(float.to_precision(case_result.operations_per_second, 2))
  <> " operations/s"
  <> "\ntime per operation: "
  <> float.to_string(float.to_precision(
    case_result.microseconds_per_operation,
    3,
  ))
  <> "us"
}

fn fuzz_command(args: List(String)) -> Nil {
  case parse_fuzz_args(args) {
    Ok(#(iteration_count, rng_seed)) -> {
      io.println(
        "Executing fuzz test with seed " <> int.to_string(rng_seed) <> "...\n",
      )

      let assert [_, ..] as seed_txs = read_seed_txs()
      let #(fuzz_result, exec_time) =
        run_fuzz(seed_txs, iteration_count, rng_seed)

      io.println(fuzz_result_to_string(fuzz_result, exec_time))
    }

    _ -> io.println(usage_msg)
  }
}

fn parse_fuzz_args(args: List(String)) -> Result(#(Int, Int), Nil) {
  case args {
    [count_str, seed_str] -> {
      let assert Ok(count) = int.parse(count_str)
      let assert Ok(seed) = int.parse(seed_str)
      Ok(#(count, seed))
    }

    [count_str] -> {
      io.println("Generating a random seed...\n")

      let assert Ok(count) = int.parse(count_str)
      let assert <<seed:32>> = crypto.strong_random_bytes(4)

      Ok(#(count, seed))
    }

    _ -> Error(Nil)
  }
}

fn read_seed_txs() -> List(SeedTx) {
  let assert Ok(file_content) = simplifile.read("dev/fuzz_test/seed_txs.txt")
  fuzz_test.parse_seed_txs(file_content)
}

fn run_fuzz(seed_txs, iteration_count, rng_seed) -> #(FuzzResult, Int) {
  let start = monotonic_time_ms()
  let fuzz_result = fuzz_test.run(seed_txs, iteration_count, rng_seed)
  let elapsed = monotonic_time_ms() - start

  #(fuzz_result, elapsed)
}

fn fuzz_result_to_string(fuzz_result: FuzzResult, elapsed: Int) -> String {
  let header =
    "iterations: "
    <> int.to_string(fuzz_result.iteration_count)
    <> "\nseed: "
    <> int.to_string(fuzz_result.rng_seed)
    <> "\ntrace: "
    <> fuzz_result.trace_hash
    <> "\ntime: "
    <> int.to_string(elapsed)
    <> "ms"
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

@external(erlang, "ffi", "monotonic_time_ms")
@external(javascript, "./ffi.mjs", "monotonicTimeMs")
fn monotonic_time_ms() -> Int
