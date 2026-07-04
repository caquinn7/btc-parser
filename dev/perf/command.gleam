import filepath
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import perf/transaction/report
import perf/transaction/suite.{type PerfResult}
import simplifile.{type FileError}

pub opaque type Command {
  PrintPerfReport
  WritePerfReport(path: String, format: PerfReportFormat)
}

type PerfReportFormat {
  Table
  Csv
}

type Args {
  Args(output_path: Option(String), format: Option(PerfReportFormat))
}

pub fn parse(args: List(String)) -> Result(Command, Nil) {
  args
  |> parse_flags(Args(None, None))
  |> result.try(fn(args) {
    case args {
      Args(None, None) -> Ok(PrintPerfReport)
      Args(Some(path), None) -> Ok(WritePerfReport(path, Csv))
      Args(Some(path), Some(format)) -> Ok(WritePerfReport(path, format))
      Args(None, Some(_)) -> Error(Nil)
    }
  })
}

fn parse_flags(args: List(String), parsed: Args) -> Result(Args, Nil) {
  case args {
    [] -> Ok(parsed)

    ["--out", path, ..rest] ->
      case parsed.output_path, is_flag_value(path) {
        None, True -> parse_flags(rest, Args(Some(path), parsed.format))
        _, _ -> Error(Nil)
      }

    ["--format", format, ..rest] ->
      case parsed.format, parse_perf_report_format(format) {
        None, Ok(format) ->
          parse_flags(rest, Args(parsed.output_path, Some(format)))

        _, _ -> Error(Nil)
      }

    _ -> Error(Nil)
  }
}

fn is_flag_value(value: String) -> Bool {
  !string.is_empty(value) && !string.starts_with(value, "--")
}

fn parse_perf_report_format(format: String) -> Result(PerfReportFormat, Nil) {
  case format {
    "table" -> Ok(Table)
    "csv" -> Ok(Csv)
    _ -> Error(Nil)
  }
}

/// Runs the performance suite, returning an error when a requested report
/// cannot be written.
pub fn run(command: Command) -> Result(Nil, FileError) {
  io.println("Executing performance tests...\n")

  let perf_result = suite.run()

  case command {
    PrintPerfReport -> {
      perf_result
      |> report.to_string
      |> io.println

      Ok(Nil)
    }

    WritePerfReport(path, format) -> {
      path
      |> write_perf_report(render_perf_report(perf_result, format))
      |> result.map(fn(_) {
        io.println("Saved performance report to " <> path)
        Nil
      })
      |> result.map_error(fn(err) {
        io.println(
          "Failed to write performance report to "
          <> path
          <> ": "
          <> string.inspect(err),
        )
        err
      })
    }
  }
}

fn render_perf_report(
  perf_result: PerfResult,
  format: PerfReportFormat,
) -> String {
  case format {
    Table -> report.to_string(perf_result)
    Csv -> report.to_csv(perf_result)
  }
}

fn write_perf_report(path: String, contents: String) -> Result(Nil, FileError) {
  let parent_directory = filepath.directory_name(path)

  case string.is_empty(parent_directory) {
    True -> simplifile.write(path, contents:)
    False ->
      case simplifile.create_directory_all(parent_directory) {
        Ok(Nil) -> simplifile.write(path, contents:)
        Error(error) -> Error(error)
      }
  }
}
