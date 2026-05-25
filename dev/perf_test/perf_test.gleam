import btc_tx.{type Transaction, type Validated}
import gleam/bit_array
import gleam/float
import gleam/int
import gleam/list
import gleamy/bench.{
  type BenchResults, BenchResults, Duration, Function, Input, Quiet,
  Set as BenchSet, Warmup,
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

pub fn run() -> PerfResult {
  PerfResult(cases: [
    decode_simple_legacy_tx(),
    decode_simple_segwit_tx(),
    compute_txid_simple_legacy_tx(),
    compute_wtxid_simple_legacy_tx(),
    compute_txid_simple_segwit_tx(),
    compute_wtxid_simple_segwit_tx(),
  ])
}

/// Measure decoding a small non-SegWit transaction from already-decoded bytes.
fn decode_simple_legacy_tx() -> PerfCaseResult {
  let config =
    PerfMeasurementConfig(
      operations_per_timed_call: 100,
      warmup_ms: 500,
      duration_ms: 2000,
    )
  let assert Ok(tx_bytes) = bit_array.base16_decode(simple_legacy_tx)
  let assert Ok(_) = btc_tx.decode(tx_bytes)

  bench.run(
    [Input("simple legacy tx", tx_bytes)],
    [
      Function(
        "decode",
        bench.repeat(config.operations_per_timed_call, btc_tx.decode),
      ),
    ],
    [Warmup(config.warmup_ms), Duration(config.duration_ms), Quiet],
  )
  |> build_case_result(bit_array.byte_size(tx_bytes), config)
}

fn decode_simple_segwit_tx() -> PerfCaseResult {
  let config =
    PerfMeasurementConfig(
      operations_per_timed_call: 100,
      warmup_ms: 500,
      duration_ms: 2000,
    )
  let assert Ok(tx_bytes) = bit_array.base16_decode(simple_segwit_tx)
  let assert Ok(_) = btc_tx.decode(tx_bytes)

  bench.run(
    [Input("simple segwit tx", tx_bytes)],
    [
      Function(
        "decode",
        bench.repeat(config.operations_per_timed_call, btc_tx.decode),
      ),
    ],
    [Warmup(config.warmup_ms), Duration(config.duration_ms), Quiet],
  )
  |> build_case_result(bit_array.byte_size(tx_bytes), config)
}

fn compute_txid_simple_legacy_tx() -> PerfCaseResult {
  measure_txid_computation(
    "simple legacy tx",
    simple_legacy_tx,
    "compute_txid",
    btc_tx.compute_txid,
  )
}

fn compute_wtxid_simple_legacy_tx() -> PerfCaseResult {
  measure_txid_computation(
    "simple legacy tx",
    simple_legacy_tx,
    "compute_wtxid",
    btc_tx.compute_wtxid,
  )
}

fn compute_txid_simple_segwit_tx() -> PerfCaseResult {
  measure_txid_computation(
    "simple segwit tx",
    simple_segwit_tx,
    "compute_txid",
    btc_tx.compute_txid,
  )
}

fn compute_wtxid_simple_segwit_tx() -> PerfCaseResult {
  measure_txid_computation(
    "simple segwit tx",
    simple_segwit_tx,
    "compute_wtxid",
    btc_tx.compute_wtxid,
  )
}

fn measure_txid_computation(
  input_label: String,
  tx_hex: String,
  function_label: String,
  compute_id: fn(Transaction(Validated)) -> BitArray,
) -> PerfCaseResult {
  let config =
    PerfMeasurementConfig(
      operations_per_timed_call: 100,
      warmup_ms: 500,
      duration_ms: 2000,
    )
  let assert Ok(tx_bytes) = bit_array.base16_decode(tx_hex)
  let assert Ok(parsed_tx) = btc_tx.decode(tx_bytes)
  let assert Ok(validated_tx) = btc_tx.validate_consensus(parsed_tx)

  bench.run(
    [Input(input_label, validated_tx)],
    [
      Function(
        function_label,
        bench.repeat(config.operations_per_timed_call, compute_id),
      ),
    ],
    [Warmup(config.warmup_ms), Duration(config.duration_ms), Quiet],
  )
  |> build_case_result(bit_array.byte_size(tx_bytes), config)
}

fn build_case_result(
  results: BenchResults,
  input_size_bytes: Int,
  config: PerfMeasurementConfig,
) -> PerfCaseResult {
  let assert BenchResults(_options, [BenchSet(input_label, fn_label, samples)]) =
    results

  let timed_call_count = list.length(samples)
  let measured_ms = float.sum(samples)
  let operation_count = timed_call_count * config.operations_per_timed_call

  let operations_per_second =
    1000.0 *. int.to_float(operation_count) /. measured_ms

  let microseconds_per_operation =
    measured_ms *. 1000.0 /. int.to_float(operation_count)

  PerfCaseResult(
    label: fn_label <> " " <> input_label,
    input_size_bytes:,
    config:,
    timed_call_count:,
    measured_ms:,
    operations_per_second:,
    microseconds_per_operation:,
  )
}
