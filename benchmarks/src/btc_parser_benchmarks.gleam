import argv
import btc_parser_benchmarks/command.{InvalidArguments}
import gleam/io
import gleam/string

const usage_msg = "usage:
  ./benchmarks/run [GLEAM_OPTIONS]
  ./benchmarks/run [GLEAM_OPTIONS] -- [--section <selector>]...
  ./benchmarks/run [GLEAM_OPTIONS] -- [--section <selector>]... --out <path>
  ./benchmarks/run [GLEAM_OPTIONS] -- [--section <selector>]... --format <table|csv> --out <path>
  ./benchmarks/run [GLEAM_OPTIONS] -- --list-sections"

pub fn main() -> Nil {
  case command.parse(argv.load().arguments) {
    Ok(command) ->
      case command.run(command) {
        Ok(Nil) -> Nil
        Error(_) -> exit_failure("")
      }
    Error(InvalidArguments) -> exit_failure(usage_msg)
    Error(command.InvalidValue(message)) -> exit_failure(message)
  }
}

fn exit_failure(message: String) -> Nil {
  case string.trim(message) {
    "" -> Nil
    _ -> io.println(message)
  }

  do_exit_failure()
}

@external(erlang, "btc_parser_benchmarks_ffi", "exit_failure")
@external(javascript, "./btc_parser_benchmarks_ffi.mjs", "exitFailure")
fn do_exit_failure() -> Nil
