import fuzz/internal/fuzz.{type FuzzResult, type SeedTx}
import fuzz/internal/report
import fuzz/internal/rng
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
  args
  |> parse_args
  |> result.map(fn(args) {
    case args {
      FuzzArgs(iterations, Some(seed)) -> IterateWithSeed(iterations, seed)
      FuzzArgs(iterations, None) -> CreateSeedAndIterate(iterations)
    }
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
  let err = InvalidValue("iterations must be a positive integer")

  use iterations <- result.try(
    arg
    |> int.parse
    |> result.replace_error(err),
  )

  case iterations <= 0 {
    True -> Error(err)
    False -> Ok(iterations)
  }
}

fn validate_seed_arg(arg: String) -> Result(Int, FuzzArgsError) {
  use seed <- result.try(
    arg
    |> int.parse
    |> result.replace_error(InvalidValue("seed must be an integer")),
  )

  let min_rng_seed = -2_147_483_648
  let max_rng_seed = 2_147_483_647

  case min_rng_seed <= seed && seed <= max_rng_seed {
    True -> Ok(seed)
    False ->
      Error(InvalidValue(
        "seed must be between "
        <> int.to_string(min_rng_seed)
        <> " and "
        <> int.to_string(max_rng_seed),
      ))
  }
}

pub fn run(command: FuzzCommand) -> Nil {
  let #(iterations, rng_seed) = case command {
    CreateSeedAndIterate(iterations:) -> {
      io.println("Generating a random seed...\n")

      let assert <<seed:32-signed>> = crypto.strong_random_bytes(4)
      #(iterations, seed)
    }

    IterateWithSeed(iterations:, rng_seed:) -> #(iterations, rng_seed)
  }

  let rng = rng.new(rng_seed)
  let rng_state = rng.state(rng)

  io.println(
    "Executing fuzz test with seed " <> int.to_string(rng_seed) <> "...\n",
  )

  case rng_state == rng_seed {
    True -> Nil
    False ->
      io.println(
        "Seed "
        <> int.to_string(rng_seed)
        <> " normalized to RNG state "
        <> int.to_string(rng_state)
        <> ".\n",
      )
  }

  let assert [_, ..] as seed_txs = read_seed_txs()
  let #(fuzz_result, exec_time) = run_fuzz(seed_txs, iterations, rng)

  fuzz_result
  |> report.to_string(exec_time)
  |> io.println
}

fn read_seed_txs() -> List(SeedTx) {
  let assert Ok(file_content) = simplifile.read("dev/fuzz/corpus/seed_txs.txt")
  fuzz.parse_seed_txs(file_content)
}

fn run_fuzz(seed_txs, iteration_count, rng) -> #(FuzzResult, Int) {
  let start = monotonic_time_ms()
  let fuzz_result = fuzz.run(seed_txs, iteration_count, rng)
  let elapsed = monotonic_time_ms() - start

  #(fuzz_result, elapsed)
}

@external(erlang, "fuzz_ffi", "monotonic_time_ms")
@external(javascript, "./fuzz_ffi.mjs", "monotonicTimeMs")
fn monotonic_time_ms() -> Int
