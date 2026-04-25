import argv
import fuzz_test/fuzz_test.{type FuzzResult, type IterationFailure, type SeedTx}
import gleam/crypto
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import simplifile

const usage_msg = "usage: gleam dev [OPTIONS] fuzz <iterations> [seed]"

pub fn main() {
  case argv.load().arguments {
    ["fuzz", ..args] -> {
      let #(iteration_count, seed) = parse_fuzz_args(args)

      io.println(
        "Executing fuzz test with seed " <> int.to_string(seed) <> ".\n",
      )

      let assert [_, ..] as seed_txs = read_seed_txs()

      let start = monotonic_time_ms()
      let fuzz_result = fuzz_test.run(seed_txs, iteration_count, seed)
      let elapsed = monotonic_time_ms() - start

      io.println(fuzz_result_to_string(fuzz_result, elapsed))
    }

    _ -> panic as usage_msg
  }
}

fn parse_fuzz_args(args: List(String)) -> #(Int, Int) {
  case args {
    [count_str, seed_str] -> {
      let assert Ok(count) = int.parse(count_str)
      let assert Ok(seed) = int.parse(seed_str)
      #(count, seed)
    }

    [count_str] -> {
      io.println("Seed not specified... one will be randomly generated.\n")

      let assert Ok(count) = int.parse(count_str)
      let assert <<seed:32>> = crypto.strong_random_bytes(4)

      #(count, seed)
    }

    _ -> panic as usage_msg
  }
}

fn read_seed_txs() -> List(SeedTx) {
  let assert Ok(file_content) = simplifile.read("dev/fuzz_test/seed_txs.txt")
  fuzz_test.parse_seed_txs(file_content)
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
