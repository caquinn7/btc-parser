import filepath
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import perf/internal/perf.{type PerfResult}
import perf/internal/report
import simplifile.{type FileError}

pub opaque type PerfCommand {
  PrintPerfReport
  WritePerfReport(path: String, format: PerfReportFormat)
}

type PerfReportFormat {
  Table
  Csv
}

type PerfArgs {
  PerfArgs(output_path: Option(String), format: Option(PerfReportFormat))
}

pub fn parse(args: List(String)) -> Result(PerfCommand, Nil) {
  use perf_args <- result.try(parse_flags(args, PerfArgs(None, None)))

  case perf_args {
    PerfArgs(None, None) -> Ok(PrintPerfReport)
    PerfArgs(Some(path), None) -> Ok(WritePerfReport(path, Csv))
    PerfArgs(Some(path), Some(format)) -> Ok(WritePerfReport(path, format))
    PerfArgs(None, Some(_)) -> Error(Nil)
  }
}

fn parse_flags(args: List(String), parsed: PerfArgs) -> Result(PerfArgs, Nil) {
  case args {
    [] -> Ok(parsed)

    ["--out", path, ..rest] ->
      case parsed.output_path, is_flag_value(path) {
        None, True ->
          parse_flags(
            rest,
            PerfArgs(output_path: Some(path), format: parsed.format),
          )
        _, _ -> Error(Nil)
      }

    ["--format", format, ..rest] ->
      case parsed.format, parse_perf_report_format(format) {
        None, Ok(format) ->
          parse_flags(
            rest,
            PerfArgs(output_path: parsed.output_path, format: Some(format)),
          )
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

pub fn run(command: PerfCommand) -> Nil {
  io.println("Executing performance tests...\n")

  let perf_result = perf.run()

  case command {
    PrintPerfReport ->
      perf_result
      |> report.to_string
      |> io.println

    WritePerfReport(path, format) -> {
      let contents = render_perf_report(perf_result, format)

      case write_perf_report(path, contents) {
        Ok(Nil) -> io.println("Saved performance report to " <> path)
        Error(error) ->
          io.println(
            "Failed to write performance report to "
            <> path
            <> ": "
            <> string.inspect(error),
          )
      }
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
