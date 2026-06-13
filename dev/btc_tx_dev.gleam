import argv
import fuzz_test/fuzz_test.{type FuzzResult, type SeedTx}
import fuzz_test/report as fuzz_report
import gleam/crypto
import gleam/int
import gleam/io
import perf_test/perf_test
import perf_test/report as perf_report
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

fn fuzz_command(args: List(String)) -> Nil {
  case parse_fuzz_args(args) {
    Ok(#(iteration_count, rng_seed)) -> {
      io.println(
        "Executing fuzz test with seed " <> int.to_string(rng_seed) <> "...\n",
      )

      let assert [_, ..] as seed_txs = read_seed_txs()
      let #(fuzz_result, exec_time) =
        run_fuzz(seed_txs, iteration_count, rng_seed)

      io.println(fuzz_report.to_string(fuzz_result, exec_time))
    }

    _ -> io.println(usage_msg)
  }
}

fn perf_command() -> Nil {
  io.println("Executing performance tests...\n")

  perf_test.run()
  |> perf_report.to_string
  |> io.println
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

@external(erlang, "ffi", "monotonic_time_ms")
@external(javascript, "./ffi.mjs", "monotonicTimeMs")
fn monotonic_time_ms() -> Int
