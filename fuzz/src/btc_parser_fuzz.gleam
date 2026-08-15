import argv
import btc_parser_fuzz/command.{InvalidNumberOfArgs}
import gleam/io
import gleam/string

const usage_msg = "usage:
  ./fuzz/run [GLEAM_OPTIONS] -- <iterations> [seed]"

pub fn main() -> Nil {
  case command.parse(argv.load().arguments) {
    Ok(command) ->
      case command.run(command) {
        Ok(Nil) -> Nil
        Error(Nil) -> exit_failure("")
      }
    Error(InvalidNumberOfArgs) -> exit_failure(usage_msg)
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

@external(erlang, "btc_parser_fuzz_ffi", "exit_failure")
@external(javascript, "./btc_parser_fuzz_ffi.mjs", "exitFailure")
fn do_exit_failure() -> Nil
