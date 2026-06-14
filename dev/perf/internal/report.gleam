import gleam/float
import gleam/int
import gleam/list
import gleam/string
import perf/internal/perf.{
  type PerfCaseResult, type PerfResult, type PerfSection,
}

pub fn to_string(perf_result: PerfResult) -> String {
  let headings = [
    "case",
    "bytes",
    "warmup ms",
    "duration ms",
    "ops/call",
    "timed calls",
    "measured ms",
    "ops/s",
    "us/op",
  ]

  let rows =
    perf_result.sections
    |> list.map(section_to_width_rows)
    |> list.flatten

  let widths = column_widths([headings, ..rows])

  let section_lines =
    perf_result.sections
    |> list.map(section_to_string(_, widths))
    |> string.join("\n\n")

  case perf_result.sections {
    [] -> [row_to_string(headings, widths), divider_to_string(widths)]
    _ -> [
      row_to_string(headings, widths),
      divider_to_string(widths),
      section_lines,
    ]
  }
  |> string.join("\n")
}

pub fn to_csv(perf_result: PerfResult) -> String {
  let headings = [
    "section",
    "case",
    "bytes",
    "warmup_ms",
    "duration_ms",
    "ops_per_timed_call",
    "timed_call_count",
    "measured_ms",
    "operations_per_second",
    "microseconds_per_operation",
  ]

  let rows =
    perf_result.sections
    |> list.flat_map(section_to_csv_rows)

  [string.join(headings, with: ","), ..rows]
  |> string.join("\n")
}

fn section_to_width_rows(section: PerfSection) -> List(List(String)) {
  [[section_title(section)], ..list.map(section.cases, case_result_to_row)]
}

fn section_to_string(section: PerfSection, widths: List(Int)) -> String {
  let case_lines =
    section.cases
    |> list.map(fn(case_result) {
      case_result
      |> case_result_to_row
      |> row_to_string(widths)
    })

  [section_title(section), ..case_lines]
  |> string.join("\n")
}

fn section_title(section: PerfSection) -> String {
  "[" <> section.title <> "]"
}

fn section_to_csv_rows(section: PerfSection) -> List(String) {
  section.cases
  |> list.map(case_result_to_csv_row(section.title, _))
}

fn case_result_to_row(case_result: PerfCaseResult) -> List(String) {
  [
    case_result.label,
    int.to_string(case_result.input_size_bytes),
    int.to_string(case_result.config.warmup_ms),
    int.to_string(case_result.config.duration_ms),
    int.to_string(case_result.config.operations_per_timed_call),
    format_grouped_int(case_result.timed_call_count),
    format_metric(case_result.measured_ms),
    format_grouped_int(float.round(case_result.operations_per_second)),
    format_metric(case_result.microseconds_per_operation),
  ]
}

fn case_result_to_csv_row(
  section_title: String,
  case_result: PerfCaseResult,
) -> String {
  [
    csv_string(section_title),
    csv_string(case_result.label),
    int.to_string(case_result.input_size_bytes),
    int.to_string(case_result.config.warmup_ms),
    int.to_string(case_result.config.duration_ms),
    int.to_string(case_result.config.operations_per_timed_call),
    int.to_string(case_result.timed_call_count),
    float.to_string(case_result.measured_ms),
    float.to_string(case_result.operations_per_second),
    float.to_string(case_result.microseconds_per_operation),
  ]
  |> string.join(with: ",")
}

fn csv_string(value: String) -> String {
  let quote = "\""
  quote <> string.replace(value, each: quote, with: quote <> quote) <> quote
}

fn column_widths(rows: List(List(String))) -> List(Int) {
  case rows {
    [] -> []
    [first, ..rest] ->
      list.fold(rest, list.map(first, string.length), fn(widths, row) {
        max_column_widths(widths, row)
      })
  }
}

fn max_column_widths(widths: List(Int), row: List(String)) -> List(Int) {
  case widths, row {
    [], [] -> []
    [], [value, ..values] -> [
      string.length(value),
      ..max_column_widths([], values)
    ]
    [width, ..widths], [] -> [width, ..widths]
    [width, ..widths], [value, ..values] -> [
      int.max(width, string.length(value)),
      ..max_column_widths(widths, values)
    ]
  }
}

fn row_to_string(row: List(String), widths: List(Int)) -> String {
  case row, widths {
    [label, ..values], [label_width, ..value_widths] ->
      string.pad_end(label, to: label_width, with: " ")
      <> "  "
      <> string.join(
        list.map2(values, value_widths, fn(value, width) {
          string.pad_start(value, to: width, with: " ")
        }),
        "  ",
      )

    _, _ -> panic as "perf report row/width column mismatch"
  }
}

fn divider_to_string(widths: List(Int)) -> String {
  widths
  |> list.map(string.repeat("-", _))
  |> string.join("  ")
}

fn format_grouped_int(value: Int) -> String {
  case value < 1000 {
    True -> int.to_string(value)
    False ->
      format_grouped_int(value / 1000)
      <> ","
      <> string.pad_start(int.to_string(value % 1000), to: 3, with: "0")
  }
}

fn format_metric(value: Float) -> String {
  let thousandths = float.round(value *. 1000.0)

  int.to_string(thousandths / 1000)
  <> "."
  <> string.pad_start(int.to_string(thousandths % 1000), to: 3, with: "0")
}
