import argv
import fuzz/command.{InvalidNumberOfArgs} as fuzz_command
import gleam/io
import gleam/string

const usage_msg = "usage:
  gleam dev [OPTIONS] fuzz <iterations> [seed]"

pub fn main() {
  case argv.load().arguments {
    ["fuzz", ..args] -> fuzz(args)
    _ -> io.println(usage_msg)
  }
}

fn fuzz(args: List(String)) -> Nil {
  case fuzz_command.parse(args) {
    Ok(command) ->
      case fuzz_command.run(command) {
        Ok(Nil) -> Nil
        Error(Nil) -> exit_failure("")
      }
    Error(InvalidNumberOfArgs) -> {
      exit_failure(usage_msg)
    }
    Error(fuzz_command.InvalidValue(msg)) -> {
      exit_failure(msg)
    }
  }
}

fn exit_failure(exit_msg) {
  case string.trim(exit_msg) {
    "" -> Nil
    _ -> io.println(exit_msg)
  }

  do_exit_failure()
}

@external(erlang, "btc_parser_dev_ffi", "exit_failure")
@external(javascript, "./btc_parser_dev_ffi.mjs", "exitFailure")
fn do_exit_failure() -> Nil
