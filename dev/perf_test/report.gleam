import gleam/float
import gleam/int
import gleam/list
import gleam/string
import perf_test/perf_test.{type PerfCaseResult, type PerfResult}

pub fn to_string(perf_result: PerfResult) -> String {
  let headings = [
    "case",
    "bytes",
    "ops/call",
    "warmup ms",
    "duration ms",
    "timed calls",
    "measured ms",
    "ops/s",
    "us/op",
  ]
  let rows = list.map(perf_result.cases, case_result_to_row)
  let widths = column_widths([headings, ..rows])

  [
    row_to_string(headings, widths),
    divider_to_string(widths),
    ..list.map(rows, fn(row) { row_to_string(row, widths) })
  ]
  |> string.join("\n")
}

fn case_result_to_row(case_result: PerfCaseResult) -> List(String) {
  [
    case_result.label,
    int.to_string(case_result.input_size_bytes),
    int.to_string(case_result.config.operations_per_timed_call),
    int.to_string(case_result.config.warmup_ms),
    int.to_string(case_result.config.duration_ms),
    format_grouped_int(case_result.timed_call_count),
    format_metric(case_result.measured_ms),
    format_grouped_int(float.round(case_result.operations_per_second)),
    format_metric(case_result.microseconds_per_operation),
  ]
}

fn column_widths(rows: List(List(String))) -> List(Int) {
  case rows {
    [] -> []
    [first, ..rest] ->
      list.fold(rest, list.map(first, string.length), fn(widths, row) {
        list.map2(widths, row, fn(width, value) {
          int.max(width, string.length(value))
        })
      })
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

    _, _ -> ""
  }
}

fn divider_to_string(widths: List(Int)) -> String {
  widths
  |> list.map(fn(width) { string.repeat("-", width) })
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
