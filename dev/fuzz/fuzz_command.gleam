import fuzz/internal/fuzz.{type FuzzResult, type SeedTx}
import fuzz/internal/report
import gleam/crypto
import gleam/int
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/result
import simplifile

pub opaque type FuzzCommand {
  CreateSeedAndIterate(iterations: Int)
  IterateWithSeed(iterations: Int, rng_seed: Int)
}

pub type FuzzArgsError {
  InvalidValue(String)
  InvalidNumberOfArgs
}

type FuzzArgs {
  FuzzArgs(iterations: Int, rng_seed: Option(Int))
}

pub fn parse(args: List(String)) -> Result(FuzzCommand, FuzzArgsError) {
  use args <- result.try(parse_args(args))

  Ok(case args {
    FuzzArgs(iterations, Some(seed)) -> IterateWithSeed(iterations, seed)
    FuzzArgs(iterations, None) -> CreateSeedAndIterate(iterations)
  })
}

fn parse_args(args: List(String)) -> Result(FuzzArgs, FuzzArgsError) {
  case args {
    [iterations_str, seed_str] -> {
      use iterations <- result.try(validate_iterations_arg(iterations_str))
      use seed <- result.try(validate_seed_arg(seed_str))
      Ok(FuzzArgs(iterations, Some(seed)))
    }

    [iterations_str] -> {
      use iterations <- result.try(validate_iterations_arg(iterations_str))
      Ok(FuzzArgs(iterations, None))
    }

    _ -> Error(InvalidNumberOfArgs)
  }
}

fn validate_iterations_arg(arg: String) -> Result(Int, FuzzArgsError) {
  let err_msg = "iterations must be a positive integer"

  use iterations <- result.try(
    arg
    |> int.parse
    |> result.replace_error(InvalidValue(err_msg)),
  )

  case iterations <= 0 {
    True -> Error(InvalidValue(err_msg))
    False -> Ok(iterations)
  }
}

fn validate_seed_arg(arg: String) -> Result(Int, FuzzArgsError) {
  use seed <- result.try(
    arg
    |> int.parse
    |> result.replace_error(InvalidValue("seed must be an integer")),
  )

  let max_rng_seed = 4_294_967_295
  case 0 <= seed && seed <= max_rng_seed {
    True -> Ok(seed)
    False ->
      Error(InvalidValue(
        "seed must be between 0 and " <> int.to_string(max_rng_seed),
      ))
  }
}

pub fn run(command: FuzzCommand) -> Nil {
  let #(iterations, rng_seed) = case command {
    CreateSeedAndIterate(iterations:) -> {
      io.println("Generating a random seed...\n")

      let assert <<seed:32>> = crypto.strong_random_bytes(4)
      #(iterations, seed)
    }

    IterateWithSeed(iterations:, rng_seed:) -> #(iterations, rng_seed)
  }

  io.println(
    "Executing fuzz test with seed " <> int.to_string(rng_seed) <> "...\n",
  )

  let assert [_, ..] as seed_txs = read_seed_txs()
  let #(fuzz_result, exec_time) = run_fuzz(seed_txs, iterations, rng_seed)

  io.println(report.to_string(fuzz_result, exec_time))
}

fn read_seed_txs() -> List(SeedTx) {
  let assert Ok(file_content) = simplifile.read("dev/fuzz/corpus/seed_txs.txt")
  fuzz.parse_seed_txs(file_content)
}

fn run_fuzz(seed_txs, iteration_count, rng_seed) -> #(FuzzResult, Int) {
  let start = monotonic_time_ms()
  let fuzz_result = fuzz.run(seed_txs, iteration_count, rng_seed)
  let elapsed = monotonic_time_ms() - start

  #(fuzz_result, elapsed)
}

@external(erlang, "fuzz_ffi", "monotonic_time_ms")
@external(javascript, "./fuzz_ffi.mjs", "monotonicTimeMs")
fn monotonic_time_ms() -> Int
