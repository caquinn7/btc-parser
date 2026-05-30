import btc_tx.{
  type Parsed, type Transaction, type Validated, DuplicateInput, ParseFailed,
}
import gleam/bit_array
import gleam/float
import gleam/int
import gleam/list
import gleamy/bench.{
  type BenchResults, type Function, type Input, type Set as BenchSet,
  BenchResults, Duration, Function, Input, Quiet, Set as BenchSet, Warmup,
}

const simple_legacy_tx = "0200000001f83913d8a4af4da53774c45cf074d35c8c6df3dd322f5b2a63cfba609ce6fb164d0000006b483045022100ce7670637cc52de4d7a0063e8a253271f09e282f3f99e8d78e20240f3b769ec90220742aea257871b277a19665434e6007850e54fc2bc64a4b5ff05c107ebf82ef460121032af93439c5e3debd027f60975cc0decc6c5b4e51bc44cbeb06a67aad69f45efafdffffff02458f0000000000001600148b068869b732322472e647126c6da8ce4d2bc5778d790000000000001976a914c76c2748f354526db26c9fbd2e2de47b990678fe88ac00000000"

const simple_segwit_tx = "02000000000101d09297d88fec299d4db728704b56d9e766339b458a42d9a7eac7a1a590e072eb4600000000ffffffff0126071400000000001976a91484548ba3fb385d7d75e5eb31238743206fb8662188ac02483045022100a7690635724cf3ece95afb51b9d0192b3f366b794ee8ccd5cf8dd7bbfaeca027022010376517622589099b18cf43274d145a74a467770973d274949b1c03ef15d550012102019e5e7ef9ee827420bf12e9d8339cdc9102c8fceb5a8187d7bb7072b4db690a00000000"

/// Results for one invocation of the performance suite.
pub type PerfResult {
  PerfResult(cases: List(PerfCaseResult))
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
    /// Description of the action and transaction shape that were measured.
    label: String,
    /// Wire-format size of the transaction used for each operation.
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

type PerfInput(a) {
  PerfInput(label: String, input_size_bytes: Int, value: a)
}

pub fn run() -> PerfResult {
  [
    measure_tx_decoding(),
    measure_consensus_validation(),
    measure_txid_computation(),
    measure_tx_serialization(),
  ]
  |> list.flatten
  |> PerfResult
}

// tx decoding

fn measure_tx_decoding() -> List(PerfCaseResult) {
  let config = standard_measurement_config()

  run_bench_cases(
    [
      decoded_tx_input("simple legacy tx", simple_legacy_tx),
      decoded_tx_input("simple segwit tx", simple_segwit_tx),
      late_truncated_tx_input(
        "late truncated simple legacy tx",
        simple_legacy_tx,
      ),
      late_truncated_tx_input(
        "late truncated simple segwit tx",
        simple_segwit_tx,
      ),
    ],
    [
      Function(
        "decode",
        bench.repeat(config.operations_per_timed_call, btc_tx.decode),
      ),
    ],
    config,
  )
}

fn decoded_tx_input(
  input_label: String,
  tx_hex: String,
) -> PerfInput(BitArray) {
  let assert Ok(tx_bytes) = bit_array.base16_decode(tx_hex)
  let assert Ok(_) = btc_tx.decode(tx_bytes)

  PerfInput(input_label, bit_array.byte_size(tx_bytes), tx_bytes)
}

fn late_truncated_tx_input(
  input_label: String,
  tx_hex: String,
) -> PerfInput(BitArray) {
  let assert Ok(valid_tx_bytes) = bit_array.base16_decode(tx_hex)
  let tx_bytes = drop_last_byte(valid_tx_bytes)
  let assert Error(ParseFailed(_)) = btc_tx.decode(tx_bytes)

  PerfInput(input_label, bit_array.byte_size(tx_bytes), tx_bytes)
}

fn drop_last_byte(bytes: BitArray) -> BitArray {
  let len = bit_array.byte_size(bytes)
  let assert Ok(truncated) = bit_array.slice(bytes, 0, len - 1)
  truncated
}

// consensus validation

fn measure_consensus_validation() -> List(PerfCaseResult) {
  [
    measure_validation_inputs(
      [1, 20, 100],
      valid_validation_input,
      fast_validate_consensus_measurement_config(),
    ),
    measure_validation_inputs(
      [500, 1000],
      valid_validation_input,
      large_validate_consensus_measurement_config(),
    ),
    measure_validation_inputs(
      [20, 100],
      late_duplicate_validation_input,
      fast_validate_consensus_measurement_config(),
    ),
    measure_validation_inputs(
      [500, 1000],
      late_duplicate_validation_input,
      large_validate_consensus_measurement_config(),
    ),
  ]
  |> list.flatten
}

fn measure_validation_inputs(
  input_counts: List(Int),
  build_input: fn(Int) -> PerfInput(Transaction(Parsed)),
  config: PerfMeasurementConfig,
) -> List(PerfCaseResult) {
  input_counts
  |> list.map(build_input)
  |> measure_validate_consensus(config)
}

fn valid_validation_input(input_count: Int) -> PerfInput(Transaction(Parsed)) {
  validation_input(
    "valid inputs=" <> int.to_string(input_count),
    build_validation_tx(input_count, False),
    ExpectValid,
  )
}

fn late_duplicate_validation_input(
  input_count: Int,
) -> PerfInput(Transaction(Parsed)) {
  validation_input(
    "late duplicate inputs=" <> int.to_string(input_count),
    build_validation_tx(input_count, True),
    ExpectLateDuplicate(input_count:),
  )
}

fn validation_input(
  label: String,
  tx_bytes: BitArray,
  expectation: ValidationExpectation,
) -> PerfInput(Transaction(Parsed)) {
  let assert Ok(parsed_tx) = btc_tx.decode(tx_bytes)
  preflight_validate_consensus(parsed_tx, expectation)

  PerfInput(label, bit_array.byte_size(tx_bytes), parsed_tx)
}

fn measure_validate_consensus(
  inputs: List(PerfInput(Transaction(Parsed))),
  config: PerfMeasurementConfig,
) -> List(PerfCaseResult) {
  run_bench_cases(
    inputs,
    [
      Function(
        "validate_consensus",
        bench.repeat(
          config.operations_per_timed_call,
          btc_tx.validate_consensus,
        ),
      ),
    ],
    config,
  )
}

fn build_validation_tx(input_count: Int, duplicate_last: Bool) -> BitArray {
  let inputs = build_validation_inputs(0, input_count, duplicate_last, <<>>)
  let output = <<1000:little-size(64), compact_size(0):bits>>

  <<
    1:little-size(32),
    compact_size(input_count):bits,
    inputs:bits,
    compact_size(1):bits,
    output:bits,
    0:little-size(32),
  >>
}

fn build_validation_inputs(
  index: Int,
  input_count: Int,
  duplicate_last: Bool,
  acc: BitArray,
) -> BitArray {
  case index >= input_count {
    True -> acc
    False -> {
      let input = build_validation_input(index, input_count, duplicate_last)
      build_validation_inputs(index + 1, input_count, duplicate_last, <<
        acc:bits,
        input:bits,
      >>)
    }
  }
}

fn build_validation_input(
  index: Int,
  input_count: Int,
  duplicate_last: Bool,
) -> BitArray {
  let prev_txid = {
    let prevout_index = case duplicate_last && index == input_count - 1 {
      True -> 0
      False -> index
    }
    <<prevout_index:little-size(32), 0:size(224)>>
  }

  <<
    prev_txid:bits,
    0:little-size(32),
    compact_size(0):bits,
    0xFFFFFFFF:little-size(32),
  >>
}

fn compact_size(n: Int) -> BitArray {
  case n {
    _ if n < 0 -> panic as "compact_size: negative values not supported"
    _ if n <= 252 -> <<n:size(8)>>
    _ if n <= 65_535 -> <<0xFD, n:little-size(16)>>
    _ if n <= 4_294_967_295 -> <<0xFE, n:little-size(32)>>
    _ -> <<0xFF, n:little-size(64)>>
  }
}

/// Uses larger batches for fast validation cases to reduce timer overhead.
fn fast_validate_consensus_measurement_config() -> PerfMeasurementConfig {
  validate_consensus_measurement_config(100)
}

/// Uses smaller batches for 500+ input cases so slow JS runs still record
/// enough timed calls for stable throughput estimates.
fn large_validate_consensus_measurement_config() -> PerfMeasurementConfig {
  validate_consensus_measurement_config(10)
}

fn validate_consensus_measurement_config(
  operations_per_timed_call: Int,
) -> PerfMeasurementConfig {
  PerfMeasurementConfig(
    operations_per_timed_call:,
    warmup_ms: 500,
    duration_ms: 2000,
  )
}

type ValidationExpectation {
  ExpectValid
  ExpectLateDuplicate(input_count: Int)
}

fn preflight_validate_consensus(
  parsed_tx: Transaction(Parsed),
  expectation: ValidationExpectation,
) -> Nil {
  case expectation {
    ExpectValid -> {
      let assert Ok(_) = btc_tx.validate_consensus(parsed_tx)
      Nil
    }

    ExpectLateDuplicate(input_count) -> {
      let assert [first_input, ..] = btc_tx.get_inputs(parsed_tx)
      let dup_prev_out = btc_tx.get_input_prev_out(first_input)

      assert btc_tx.validate_consensus(parsed_tx)
        == Error([DuplicateInput(dup_prev_out, 0, input_count - 1)])
    }
  }
}

// txid computation

fn measure_txid_computation() -> List(PerfCaseResult) {
  let config = standard_measurement_config()

  run_bench_cases(
    simple_validated_tx_inputs(),
    [
      Function(
        "compute_txid",
        bench.repeat(config.operations_per_timed_call, btc_tx.compute_txid),
      ),
      Function(
        "compute_wtxid",
        bench.repeat(config.operations_per_timed_call, btc_tx.compute_wtxid),
      ),
    ],
    config,
  )
}

// tx serialization

fn measure_tx_serialization() -> List(PerfCaseResult) {
  let config = standard_measurement_config()

  run_bench_cases(
    simple_validated_tx_inputs(),
    [
      Function(
        "to_stripped_bytes",
        bench.repeat(config.operations_per_timed_call, btc_tx.to_stripped_bytes),
      ),
      Function(
        "to_witness_bytes",
        bench.repeat(config.operations_per_timed_call, btc_tx.to_witness_bytes),
      ),
    ],
    config,
  )
}

// shared helpers

fn standard_measurement_config() -> PerfMeasurementConfig {
  PerfMeasurementConfig(
    operations_per_timed_call: 100,
    warmup_ms: 500,
    duration_ms: 2000,
  )
}

fn simple_validated_tx_inputs() -> List(PerfInput(Transaction(Validated))) {
  [
    validated_tx_input("simple legacy tx", simple_legacy_tx),
    validated_tx_input("simple segwit tx", simple_segwit_tx),
  ]
}

fn validated_tx_input(
  input_label: String,
  tx_hex: String,
) -> PerfInput(Transaction(Validated)) {
  let assert Ok(tx_bytes) = bit_array.base16_decode(tx_hex)
  let assert Ok(parsed_tx) = btc_tx.decode(tx_bytes)
  let assert Ok(validated_tx) = btc_tx.validate_consensus(parsed_tx)

  PerfInput(input_label, bit_array.byte_size(tx_bytes), validated_tx)
}

fn run_bench_cases(
  inputs: List(PerfInput(a)),
  functions: List(Function(a, b)),
  config: PerfMeasurementConfig,
) -> List(PerfCaseResult) {
  let bench_inputs = list.map(inputs, to_bench_input)
  let bench_options = [
    Warmup(config.warmup_ms),
    Duration(config.duration_ms),
    Quiet,
  ]

  bench_inputs
  |> bench.run(functions, bench_options)
  |> build_case_results(inputs, config)
}

fn to_bench_input(input: PerfInput(a)) -> Input(a) {
  let PerfInput(label, _, value) = input
  Input(label, value)
}

fn build_case_results(
  results: BenchResults,
  inputs: List(PerfInput(a)),
  config: PerfMeasurementConfig,
) -> List(PerfCaseResult) {
  let BenchResults(_options, sets) = results
  list.map(sets, build_set_case_result(_, inputs, config))
}

fn build_set_case_result(
  set: BenchSet,
  inputs: List(PerfInput(a)),
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
  inputs: List(PerfInput(a)),
  input_label: String,
) -> Int {
  let assert Ok(input_size_bytes) =
    inputs
    |> list.find_map(fn(input) {
      let PerfInput(label, input_size_bytes, _) = input

      case label == input_label {
        True -> Ok(input_size_bytes)
        False -> Error(Nil)
      }
    })

  input_size_bytes
}
