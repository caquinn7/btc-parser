import filepath
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import perf/report
import perf/suite.{
  type PerfResult, type SectionSelection, UnknownSectionSelectors,
}
import simplifile.{type FileError}

pub opaque type Command {
  ListPerfSections
  PrintPerfReport(selection: SectionSelection)
  WritePerfReport(
    selection: SectionSelection,
    path: String,
    format: PerfReportFormat,
  )
}

pub type ArgsError {
  InvalidArguments
  InvalidValue(String)
}

type PerfReportFormat {
  Table
  Csv
}

type ReportArgs {
  ReportArgs(
    output_path: Option(String),
    format: Option(PerfReportFormat),
    section_selectors: List(String),
  )
}

pub fn parse(args: List(String)) -> Result(Command, ArgsError) {
  case args {
    ["--list-sections"] -> Ok(ListPerfSections)
    _ -> parse_report_command(args)
  }
}

fn parse_report_command(args: List(String)) -> Result(Command, ArgsError) {
  use args <- result.try(parse_flags(args, ReportArgs(None, None, [])))

  use selection <- result.try(
    args.section_selectors
    |> list.reverse
    |> suite.select_sections
    |> result.map_error(fn(error) {
      case error {
        UnknownSectionSelectors(selectors) ->
          InvalidValue(unknown_section_selectors_message(selectors))
      }
    }),
  )

  case args.output_path, args.format {
    None, None -> Ok(PrintPerfReport(selection))
    Some(path), None -> Ok(WritePerfReport(selection, path, Csv))
    Some(path), Some(format) -> Ok(WritePerfReport(selection, path, format))
    None, Some(_) -> Error(InvalidArguments)
  }
}

fn parse_flags(
  args: List(String),
  parsed: ReportArgs,
) -> Result(ReportArgs, ArgsError) {
  case args {
    [] -> Ok(parsed)

    ["--out", path, ..rest] ->
      case parsed.output_path, is_flag_value(path) {
        None, True ->
          parse_flags(rest, ReportArgs(..parsed, output_path: Some(path)))

        _, _ -> Error(InvalidArguments)
      }

    ["--format", format, ..rest] ->
      case parsed.format, parse_perf_report_format(format) {
        None, Ok(format) ->
          parse_flags(rest, ReportArgs(..parsed, format: Some(format)))

        _, _ -> Error(InvalidArguments)
      }

    ["--section", selector, ..rest] ->
      case is_flag_value(selector) {
        True ->
          parse_flags(
            rest,
            ReportArgs(..parsed, section_selectors: [
              selector,
              ..parsed.section_selectors
            ]),
          )

        False -> Error(InvalidArguments)
      }

    _ -> Error(InvalidArguments)
  }
}

fn unknown_section_selectors_message(selectors: List(String)) -> String {
  let description = case selectors {
    [_] -> "unknown performance section selector: "
    _ -> "unknown performance section selectors: "
  }

  description
  <> string.join(selectors, ", ")
  <> "\nRun `./benchmarks/run -- --list-sections` to list canonical leaf section IDs."
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
  case command {
    ListPerfSections -> {
      suite.section_ids()
      |> string.join("\n")
      |> io.println

      Ok(Nil)
    }

    PrintPerfReport(selection) -> {
      io.println("Executing performance tests...\n")

      suite.run(selection)
      |> report.to_string
      |> io.println

      Ok(Nil)
    }

    WritePerfReport(selection, path, format) -> {
      io.println("Executing performance tests...\n")

      let perf_result = suite.run(selection)

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
