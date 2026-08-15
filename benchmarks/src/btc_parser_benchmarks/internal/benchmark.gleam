//// Shared measurement primitives for development performance suites.

import gleam/float
import gleam/int
import gleam/list
import gleamy/bench.{
  type BenchResults, type Input, type Set as BenchSet, Duration, Function, Input,
  Quiet, Set as BenchSet, Warmup,
}

/// Prebuilt input for one benchmark case.
pub type PerfCaseInput(a) {
  PerfCaseInput(label: String, input_size_bytes: Int, value: a)
}

/// Settings used to collect measurements for a performance case.
pub type PerfMeasurementConfig {
  PerfMeasurementConfig(
    /// Number of operations run between starting and stopping the clock once.
    /// Timing several operations together reduces the timer's influence on
    /// fast benchmark cases.
    operations_per_timed_call: Int,
    /// Number of milliseconds the case runs before timing is recorded.
    warmup_ms: Int,
    /// Number of milliseconds the case attempts to record timings for.
    duration_ms: Int,
  )
}

/// Measurements for one performance case.
pub type PerfCaseResult {
  PerfCaseResult(
    /// Description of the action and input shape that were measured.
    label: String,
    /// Complete serialized input size for each logical operation.
    input_size_bytes: Int,
    /// Settings used while collecting the measurements below.
    config: PerfMeasurementConfig,
    /// Number of start-clock/run/stop-clock measurements included in the result.
    timed_call_count: Int,
    /// Total milliseconds covered by the timed calls used in the calculations.
    /// This is usually slightly less than `config.duration_ms`.
    measured_ms: Float,
    /// Estimated number of individual operations completed each second.
    operations_per_second: Float,
    /// Estimated time to complete one individual operation, in microseconds.
    microseconds_per_operation: Float,
  )
}

/// Named group of performance cases shown together in the report.
pub type PerfSection {
  PerfSection(
    /// Canonical section identifier used for selection and reporting.
    id: String,
    cases: List(PerfCaseResult),
  )
}

/// A lazily measured concrete leaf section in a domain suite.
pub type PerfSectionDefinition {
  PerfSectionDefinition(id: String, measure: fn() -> List(PerfCaseResult))
}

/// One group of curve values that shares a measurement configuration.
pub type MeasurementCurvePoint {
  MeasurementCurvePoint(values: List(Int), config: PerfMeasurementConfig)
}

/// Measure a curve after building each point's inputs before timing begins.
pub fn measure_curve(
  curve: List(MeasurementCurvePoint),
  build_inputs: fn(List(Int)) -> List(PerfCaseInput(a)),
  function_label: String,
  measured_function: fn(a) -> b,
) -> List(PerfCaseResult) {
  curve
  |> list.flat_map(fn(point) {
    let MeasurementCurvePoint(values, config) = point

    values
    |> build_inputs
    |> measure_cases(config, function_label, measured_function)
  })
}

/// Measure prebuilt inputs for one public operation.
pub fn measure_cases(
  inputs: List(PerfCaseInput(a)),
  config: PerfMeasurementConfig,
  function_label: String,
  measured_function: fn(a) -> b,
) -> List(PerfCaseResult) {
  let bench_inputs = list.map(inputs, to_bench_input)
  let bench_function =
    Function(
      function_label,
      bench.repeat(config.operations_per_timed_call, measured_function),
    )
  let bench_options = [
    Warmup(config.warmup_ms),
    Duration(config.duration_ms),
    Quiet,
  ]

  bench_inputs
  |> bench.run([bench_function], bench_options)
  |> build_case_results(inputs, config)
}

fn to_bench_input(input: PerfCaseInput(a)) -> Input(a) {
  let PerfCaseInput(label, _, value) = input
  Input(label, value)
}

fn build_case_results(
  results: BenchResults,
  inputs: List(PerfCaseInput(a)),
  config: PerfMeasurementConfig,
) -> List(PerfCaseResult) {
  list.map(results.sets, build_set_case_result(_, inputs, config))
}

fn build_set_case_result(
  set: BenchSet,
  inputs: List(PerfCaseInput(a)),
  config: PerfMeasurementConfig,
) -> PerfCaseResult {
  let BenchSet(input_label, fn_label, samples) = set

  let timed_call_count = list.length(samples)
  let measured_ms = float.sum(samples)
  let operation_count = timed_call_count * config.operations_per_timed_call

  let operations_per_second =
    1000.0 *. int.to_float(operation_count) /. measured_ms

  let microseconds_per_operation =
    measured_ms *. 1000.0 /. int.to_float(operation_count)

  PerfCaseResult(
    label: fn_label <> " " <> input_label,
    input_size_bytes: find_input_size_bytes(inputs, input_label),
    config:,
    timed_call_count:,
    measured_ms:,
    operations_per_second:,
    microseconds_per_operation:,
  )
}

fn find_input_size_bytes(
  inputs: List(PerfCaseInput(a)),
  input_label: String,
) -> Int {
  let assert Ok(input_size_bytes) =
    inputs
    |> list.find_map(fn(input) {
      let PerfCaseInput(label, input_size_bytes, _) = input

      case label == input_label {
        True -> Ok(input_size_bytes)
        False -> Error(Nil)
      }
    })

  input_size_bytes
}
