import btc_parser_fuzz/block/suite as block_suite
import btc_parser_fuzz/fuzz_result.{type FuzzResult}
import btc_parser_fuzz/internal/rng
import btc_parser_fuzz/report
import btc_parser_fuzz/transaction/suite as transaction_suite
import gleam/crypto
import gleam/int
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/result
import simplifile

pub opaque type Command {
  CreateSeedAndIterate(suite: Suite, iterations: Int)
  IterateWithSeed(suite: Suite, iterations: Int, rng_seed: Int)
}

pub type Suite {
  Transaction
  Block
}

pub type ArgsError {
  InvalidValue(String)
  InvalidNumberOfArgs
}

type Args {
  Args(suite: Suite, iterations: Int, rng_seed: Option(Int))
}

pub fn parse(args: List(String)) -> Result(Command, ArgsError) {
  args
  |> parse_args
  |> result.map(fn(args) {
    case args {
      Args(suite, iterations, Some(seed)) ->
        IterateWithSeed(suite, iterations, seed)
      Args(suite, iterations, None) -> CreateSeedAndIterate(suite, iterations)
    }
  })
}

fn parse_args(args: List(String)) -> Result(Args, ArgsError) {
  case args {
    [suite_str, iterations_str, seed_str] -> {
      use suite <- result.try(validate_suite_arg(suite_str))
      use iterations <- result.try(validate_iterations_arg(iterations_str))
      use seed <- result.try(validate_seed_arg(seed_str))
      Ok(Args(suite, iterations, Some(seed)))
    }

    [suite_str, iterations_str] -> {
      use suite <- result.try(validate_suite_arg(suite_str))
      use iterations <- result.try(validate_iterations_arg(iterations_str))
      Ok(Args(suite, iterations, None))
    }

    [suite_str, ..] -> {
      case validate_suite_arg(suite_str) {
        Ok(_) -> Error(InvalidNumberOfArgs)
        Error(error) -> Error(error)
      }
    }

    _ -> Error(InvalidNumberOfArgs)
  }
}

fn validate_suite_arg(arg: String) -> Result(Suite, ArgsError) {
  case arg {
    "transaction" -> Ok(Transaction)
    "block" -> Ok(Block)
    _ -> Error(InvalidValue("suite must be \"transaction\" or \"block\""))
  }
}

fn validate_iterations_arg(arg: String) -> Result(Int, ArgsError) {
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

fn validate_seed_arg(arg: String) -> Result(Int, ArgsError) {
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

/// Runs the fuzz harness, returning an error when any iteration discovers an
/// unhandled exception.
pub fn run(command: Command) -> Result(Nil, Nil) {
  let #(suite, iterations, rng_seed) = case command {
    CreateSeedAndIterate(suite:, iterations:) -> {
      io.println("Generating a random seed...\n")

      let assert <<seed:32-signed>> = crypto.strong_random_bytes(4)
      #(suite, iterations, seed)
    }

    IterateWithSeed(suite:, iterations:, rng_seed:) -> #(
      suite,
      iterations,
      rng_seed,
    )
  }

  let rng = rng.new(rng_seed)
  let rng_state = rng.state(rng)

  io.println(
    "Executing "
    <> suite_name(suite)
    <> " fuzz test with seed "
    <> int.to_string(rng_seed)
    <> "...\n",
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

  case suite {
    Transaction -> run_transaction(iterations, rng)
    Block -> run_block(iterations, rng)
  }
}

fn run_transaction(iterations: Int, rng) -> Result(Nil, Nil) {
  let assert [_, ..] as seed_txs = read_seed_txs()
  let #(fuzz_result, exec_time) =
    run_transaction_fuzz(seed_txs, iterations, rng)

  fuzz_result
  |> report.to_string(
    "transaction",
    exec_time,
    transaction_suite.iteration_failure_to_string,
  )
  |> io.println

  result_from_fuzz_result(fuzz_result)
}

fn run_block(iterations: Int, rng) -> Result(Nil, Nil) {
  let assert [_, ..] as seed_blocks = read_seed_blocks()
  let #(fuzz_result, exec_time) = run_block_fuzz(seed_blocks, iterations, rng)

  fuzz_result
  |> report.to_string(
    "block",
    exec_time,
    block_suite.iteration_failure_to_string,
  )
  |> io.println

  result_from_fuzz_result(fuzz_result)
}

fn read_seed_txs() -> List(transaction_suite.SeedTx) {
  let assert Ok(file_content) =
    simplifile.read("corpus/transaction/seed_txs.txt")

  transaction_suite.parse_seed_txs(file_content)
}

fn read_seed_blocks() -> List(block_suite.SeedBlock) {
  let assert Ok(file_content) = simplifile.read("corpus/block/seed_blocks.txt")

  block_suite.parse_seed_blocks(file_content)
}

fn run_transaction_fuzz(
  seed_txs,
  iteration_count,
  rng,
) -> #(FuzzResult(transaction_suite.IterationFailure), Int) {
  let start = monotonic_time_ms()
  let fuzz_result = transaction_suite.run(seed_txs, iteration_count, rng)
  let elapsed = monotonic_time_ms() - start

  #(fuzz_result, elapsed)
}

fn run_block_fuzz(
  seed_blocks,
  iteration_count,
  rng,
) -> #(FuzzResult(block_suite.IterationFailure), Int) {
  let start = monotonic_time_ms()
  let fuzz_result = block_suite.run(seed_blocks, iteration_count, rng)
  let elapsed = monotonic_time_ms() - start

  #(fuzz_result, elapsed)
}

fn result_from_fuzz_result(
  fuzz_result: FuzzResult(failure),
) -> Result(Nil, Nil) {
  case fuzz_result.failures {
    [] -> Ok(Nil)
    [_, ..] -> Error(Nil)
  }
}

fn suite_name(suite: Suite) -> String {
  case suite {
    Transaction -> "transaction"
    Block -> "block"
  }
}

@external(erlang, "btc_parser_fuzz_command_ffi", "monotonic_time_ms")
@external(javascript, "./btc_parser_fuzz_command_ffi.mjs", "monotonicTimeMs")
fn monotonic_time_ms() -> Int
