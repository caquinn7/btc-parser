import argv
import fuzz/fuzz_command.{InvalidNumberOfArgs, InvalidValue}
import gleam/io
import perf/perf_command

const usage_msg = "usage:
  gleam dev [OPTIONS] fuzz <iterations> [seed]
  gleam dev [OPTIONS] perf
  gleam dev [OPTIONS] perf --out <path>
  gleam dev [OPTIONS] perf --format <table|csv> --out <path>"

pub fn main() {
  case argv.load().arguments {
    ["fuzz", ..args] -> fuzz(args)
    ["perf", ..args] -> perf(args)
    _ -> io.println(usage_msg)
  }
}

fn fuzz(args: List(String)) -> Nil {
  case fuzz_command.parse(args) {
    Ok(command) -> {
      case fuzz_command.run(command) {
        Ok(Nil) -> Nil
        Error(Nil) -> exit_failure()
      }
    }
    Error(InvalidNumberOfArgs) -> {
      io.println(usage_msg)
      exit_failure()
    }
    Error(InvalidValue(msg)) -> {
      io.println(msg)
      exit_failure()
    }
  }
}

fn perf(args: List(String)) -> Nil {
  case perf_command.parse(args) {
    Ok(command) -> {
      case perf_command.run(command) {
        Ok(Nil) -> Nil
        Error(_) -> exit_failure()
      }
    }
    Error(Nil) -> {
      io.println(usage_msg)
      exit_failure()
    }
  }
}

@external(erlang, "btc_parser_dev_ffi", "exit_failure")
@external(javascript, "./btc_parser_dev_ffi.mjs", "exitFailure")
fn exit_failure() -> Nil
