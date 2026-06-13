import argv
import fuzz/fuzz_command.{InvalidNumberOfArgs, InvalidValue}
import gleam/io
import perf_test/perf_command

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
    Ok(command) -> fuzz_command.run(command)
    Error(InvalidNumberOfArgs) -> io.println(usage_msg)
    Error(InvalidValue(msg)) -> io.println(msg)
  }
}

fn perf(args: List(String)) -> Nil {
  case perf_command.parse(args) {
    Ok(command) -> perf_command.run(command)
    Error(Nil) -> io.println(usage_msg)
  }
}
