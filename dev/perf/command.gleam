import filepath
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import perf/transaction/report
import perf/transaction/suite.{
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

type Args {
  Args(
    output_path: Option(String),
    format: Option(PerfReportFormat),
    section_selectors: List(String),
    list_sections: Bool,
  )
}

pub fn parse(args: List(String)) -> Result(Command, ArgsError) {
  args
  |> parse_flags(Args(None, None, [], False))
  |> result.replace_error(InvalidArguments)
  |> result.try(fn(args) {
    case args {
      Args(None, None, [], True) -> Ok(ListPerfSections)
      Args(_, _, _, True) -> Error(InvalidArguments)
      Args(output_path, format, section_selectors, False) -> {
        use selection <- result.try(
          section_selectors
          |> list.reverse
          |> suite.select_sections
          |> result.map_error(fn(error) {
            case error {
              UnknownSectionSelectors(selectors) ->
                InvalidValue(unknown_section_selectors_message(selectors))
            }
          }),
        )

        case output_path, format {
          None, None -> Ok(PrintPerfReport(selection))
          Some(path), None -> Ok(WritePerfReport(selection, path, Csv))
          Some(path), Some(format) ->
            Ok(WritePerfReport(selection, path, format))
          None, Some(_) -> Error(InvalidArguments)
        }
      }
    }
  })
}

fn parse_flags(args: List(String), parsed: Args) -> Result(Args, Nil) {
  case args {
    [] -> Ok(parsed)

    ["--out", path, ..rest] ->
      case parsed.output_path, is_flag_value(path) {
        None, True ->
          parse_flags(
            rest,
            Args(
              Some(path),
              parsed.format,
              parsed.section_selectors,
              parsed.list_sections,
            ),
          )

        _, _ -> Error(Nil)
      }

    ["--format", format, ..rest] ->
      case parsed.format, parse_perf_report_format(format) {
        None, Ok(format) ->
          parse_flags(
            rest,
            Args(
              parsed.output_path,
              Some(format),
              parsed.section_selectors,
              parsed.list_sections,
            ),
          )

        _, _ -> Error(Nil)
      }

    ["--section", selector, ..rest] ->
      case is_flag_value(selector) {
        True ->
          parse_flags(
            rest,
            Args(
              parsed.output_path,
              parsed.format,
              [selector, ..parsed.section_selectors],
              parsed.list_sections,
            ),
          )

        False -> Error(Nil)
      }

    ["--list-sections", ..rest] ->
      case parsed.list_sections {
        False ->
          parse_flags(
            rest,
            Args(
              parsed.output_path,
              parsed.format,
              parsed.section_selectors,
              True,
            ),
          )

        True -> Error(Nil)
      }

    _ -> Error(Nil)
  }
}

fn unknown_section_selectors_message(selectors: List(String)) -> String {
  let description = case selectors {
    [_] -> "unknown performance section selector: "
    _ -> "unknown performance section selectors: "
  }

  description
  <> string.join(selectors, ", ")
  <> "\nRun `gleam dev perf --list-sections` to list canonical leaf section IDs."
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
