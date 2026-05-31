//// Performance benchmarks for the public `btc_tx` transaction workflows.
////
//// The suite measures repeated operations that callers are expected to pay for:
//// decoding, context-free consensus validation, transaction id computation, and
//// serialization. Input construction, hex decoding, preflight assertions, and
//// consensus validation needed to prepare `Transaction(Validated)` values are
//// intentionally performed before timing begins.
////
//// Benchmark cases run one or more logical operations per timed call. Fast
//// cases use larger batches to reduce timer overhead; slower cases can use
//// smaller batches, down to one operation per timed call. Reported throughput
//// and latency are converted back to one logical operation, such as one
//// `decode` or one `compute_txid` call.

import btc_tx.{
  type Parsed, type Transaction, type Validated, DuplicateInput, ParseFailed,
  PolicyLimitExceeded,
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

/// P2WSH multisig spend: four inputs, each with a 5-item witness stack.
const witness_heavy_p2wsh_tx = "010000000001041d77f8ba9cb7292d2c8d28f7860440c20a695a5ac1b008184351bfd167b1de571100000000fdffffff0e3598526cbf5c071dd670bf1ea2a3d3344531b7cdd0b2803822dc875897315f0400000000ffffffff7c40dfa04ff141d4fe9b78672fdeb94606f964adbb30f0740a93d9b561d2a2730500000000ffffffff1afb4550a6b5ba51133ea1049c758ca4b4dd073a63f1bb3980af72de2235bcbe1100000000ffffffff022b3d0f000000000017a914183fad2e1a32ae1bc65ef3ca3664be338e23d676875c53140000000000220020262aa3a633769751560133c647f56948da4099acf9176b51831b17a180aba7900500483045022100b0f4d44a96453f3bd231d392702c6d88f39469c9f56d3d31abf3498a5554a79102202a55e22cd4390c5e7e51ed02321fa45149f9620654a4473125afd8a98502ae3f01483045022100ecc78689ce66035290d331ac9dbf4cb2392f22b7b127bc24dfbe93981fa6f0e902202cfe5fb41d529b49cf7394a7ec49dd69d49e4f1e15bb16a9e1a577468c5e5d5d01483045022100fca785f594914776f74d01943946252f2be2b80b6d96d9d9669e0e89c5715f6702202d649e5cc3a10c68bd23d5c51e6d91123bec8a0fafb896c60a00efad1bddcfbd018b532102532c7265b2a352e9a2e216edddd5f5cb921f6502b30f3dd42535871f2371cf262102705d91275933db288ba8ba940feb56d6d1d804f77b31de16811b518d9b27dab7210276eb537ec808034480ca7d38b431674d5979088cfae267ec8acd2d57e968dac721029fe1a87be21851bc0a4f3ded0e1758bbeecc7be201a1e7ee7282f77886b8b09d54ae050047304402204cbf2e84f64ce78ff8927ab644884fed95903f56cdfe82404d457f31f12b794202206b56afc382429cfdb44b8fbc3cc016440387a177549dc858ec4ccb135cb4e633014730440220129f8de1bce23635b0aae96c05b6671987760ba14fc4caf7345f0f763a40bc39022011420d6f749094b924bbd115576064ec8718de5449d8972d1490ead123c8349101473044022026ff639597d3dc7cc6286bd01b30e09f44ba5725d4c4e9eb5e228299b12664d002201cd70fdea7a16060def6cd345e5e04056975db2347c4a0eaf0728950eeea57cd018b532102b2a01169433767d3d69a6a4540f21ed91e13d86f48bc8f054d25c347287dc75b2103a2b06276509980518481722afe378cc5cce6e331fb90cde756c3233e6d2936722103be3359e6f3f90eb2c78cece0c66e92772d3af3b67a4cf15d8a6ab0e60b07aa082103f28f4f14ef2fc63f840a6fee7117f5f188ed386c9ee37578587a10b34904d91f54ae050047304402206678ad5f654d188e007f497004c7acb1742149c52c83b4baa525c69907ab6e5f02206575e2a323e8f4d61daa8efc334f3e9fb356c9be31939f0b2a9fed7b81af7f420147304402205f41dddf5198b36522c4fad44babb6604638d8e8544e25225d10d38dd5d58dde022002494ef946fd26f9ac10f3d692328a575249f3a0575cebd7ee53600a8c15e7df014730440220424d5833867f6d9225b81ad77dc954fde2c2deb8eda0f60bf5596d3ed908382402204dcc96eea1a0c1a0c82523cc41be1189dfdafedea346c898897f866c32d39983018b532102dd7d60f3278cc6c59358379fbfa1cd3579f287f526b6537ce5258f91f0d17f1e21035289b8951701046732417df9e635db32e395c680b23d1663616c922a409b72a421035cba8725cc106f7188a2ad017a2252c612a174347a88db41b8c93c51f0aadd7421038823210cadbffa3a4e4bd5d19c47dc7a356320c439e074da945e6153d03525da54ae0500483045022100ac5e0d6268b11afa7a2b28fe9ee84da98a4413f5978863de2dfc084c72354d8e02206d45a484d23f98569a73b10a13d2795946cbe81382bc8526305307b3c1ea75d301473044022041ab10e81aa083a0ff4c0851fbb35678dc10b0e1ae838821df82c20d69b40169022027d6d819e8e820945f0537eba476c8aa0eb9ee2a48ab37559ec09fb1ca0e1e9601473044022010ba6168e3ddb7ca2f70b04329ab3c373e0dc594b48999eecb96c8933380e01f02206a71a244e8d2a3f5c152241d581196cfd9b8ae87ed134f9e53cb6c04788c3380018b53210301065882a06bb9246bb761d9905cfeeeeed6ff218777960fb8c65ea5710709fc21031ace900028040ec46b9d89da58f72e41d1a331cf21f4bef5420dfd68680648c321034c3d7498d35ded063716d66c9f9dcdc82d54094d33ae1d72c2a3b547c27ee0ec2103c5d55f5ec64876c572acc0f9de94ada8e7964bca8d27a838291178d15f564cf754ae00000000"

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

// ==============================================================================
// Transaction decoding
// ==============================================================================

/// Measures `btc_tx.decode` from byte arrays that are prepared before timing.
/// This group includes valid legacy/SegWit fixtures, synthetic many-input legacy
/// transactions, plus malformed inputs that exercise different failure paths:
/// late truncation, which fails after most of the transaction has been parsed,
/// and policy-limit violations, which should reject before doing unnecessary
/// payload work.
fn measure_tx_decoding() -> List(PerfCaseResult) {
  let fixture_inputs = [
    decoded_tx_input("simple legacy tx", simple_legacy_tx),
    decoded_tx_input("simple segwit tx", simple_segwit_tx),
    decoded_tx_input("witness-heavy p2wsh tx", witness_heavy_p2wsh_tx),
    late_truncated_tx_input("late truncated simple legacy tx", simple_legacy_tx),
    late_truncated_tx_input("late truncated simple segwit tx", simple_segwit_tx),
    oversized_scriptsig_policy_input("oversized scriptSig policy tx"),
  ]

  [
    measure_decode(fixture_inputs, measurement_config(100)),
    measure_synthetic_legacy_decoding(
      [1, 20, 100],
      small_synthetic_tx_measurement_config(),
    ),
    measure_synthetic_legacy_decoding(
      [500, 1000],
      large_synthetic_tx_measurement_config(),
    ),
  ]
  |> list.flatten
}

fn measure_decode(
  inputs: List(PerfInput(BitArray)),
  config: PerfMeasurementConfig,
) -> List(PerfCaseResult) {
  run_bench_cases(
    inputs,
    [
      Function(
        "decode",
        bench.repeat(config.operations_per_timed_call, btc_tx.decode),
      ),
    ],
    config,
  )
}

fn measure_synthetic_legacy_decoding(
  tx_input_counts: List(Int),
  config: PerfMeasurementConfig,
) -> List(PerfCaseResult) {
  tx_input_counts
  |> list.map(synthetic_decode_input)
  |> measure_decode(config)
}

fn synthetic_decode_input(tx_input_count: Int) -> PerfInput(BitArray) {
  let tx_bytes = build_synthetic_legacy_tx(tx_input_count, UniquePrevouts)
  let assert Ok(_) = btc_tx.decode(tx_bytes)

  PerfInput(
    "legacy tx inputs=" <> int.to_string(tx_input_count),
    bit_array.byte_size(tx_bytes),
    tx_bytes,
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

fn oversized_scriptsig_policy_input(
  input_label: String,
) -> PerfInput(BitArray) {
  let max_script_size =
    btc_tx.default_decode_policy()
    |> btc_tx.decode_policy_max_script_size

  let script_sig_size = max_script_size + 1
  let script_sig = <<0:size({ script_sig_size * 8 })>>

  // Include the oversized script bytes so this rejects on policy after the
  // length is decoded, rather than rejecting earlier as truncated input.
  let tx_bytes = <<
    1:little-size(32),
    compact_size(1):bits,
    0:size(256),
    0:little-size(32),
    compact_size(script_sig_size):bits,
    script_sig:bits,
    0xFFFFFFFF:little-size(32),
  >>

  let assert Error(ParseFailed(parse_err)) = btc_tx.decode(tx_bytes)
  assert btc_tx.parse_error_kind(parse_err)
    == PolicyLimitExceeded(script_sig_size, max_script_size)

  PerfInput(input_label, bit_array.byte_size(tx_bytes), tx_bytes)
}

// ==============================================================================
// Consensus validation
// ==============================================================================

/// Measures `btc_tx.validate_consensus` on already-parsed synthetic transactions.
/// The valid cases exercise full success-path input scanning. The late-duplicate
/// cases place the duplicate prevout at the end so rejection still walks nearly
/// the whole input list.
fn measure_consensus_validation() -> List(PerfCaseResult) {
  [
    measure_validation_inputs(
      [1, 20, 100],
      valid_consensus_input,
      small_synthetic_tx_measurement_config(),
    ),
    measure_validation_inputs(
      [500, 1000],
      valid_consensus_input,
      large_synthetic_tx_measurement_config(),
    ),
    measure_validation_inputs(
      [20, 100],
      late_duplicate_consensus_input,
      small_synthetic_tx_measurement_config(),
    ),
    measure_validation_inputs(
      [500, 1000],
      late_duplicate_consensus_input,
      large_synthetic_tx_measurement_config(),
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

fn valid_consensus_input(input_count: Int) -> PerfInput(Transaction(Parsed)) {
  validation_input(
    "valid inputs=" <> int.to_string(input_count),
    build_synthetic_legacy_tx(input_count, UniquePrevouts),
    ExpectValid,
  )
}

fn late_duplicate_consensus_input(
  input_count: Int,
) -> PerfInput(Transaction(Parsed)) {
  validation_input(
    "late duplicate inputs=" <> int.to_string(input_count),
    build_synthetic_legacy_tx(input_count, LastPrevoutDuplicatesFirst),
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

// ==============================================================================
// Txid computation & serialization
// ==============================================================================

/// Measures `compute_txid` and `compute_wtxid` on already-validated fixtures.
/// This excludes decode and consensus-validation cost, leaving serialization and
/// double-SHA256 work inside the timed region.
fn measure_txid_computation() -> List(PerfCaseResult) {
  let config = measurement_config(100)

  run_bench_cases(
    validated_tx_inputs(),
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

/// Measures `to_stripped_bytes` and `to_witness_bytes` on already-validated
/// fixtures. Legacy and SegWit transactions are both included because witness
/// serialization changes the code path and payload shape.
fn measure_tx_serialization() -> List(PerfCaseResult) {
  let config = measurement_config(100)

  run_bench_cases(
    validated_tx_inputs(),
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

fn validated_tx_inputs() -> List(PerfInput(Transaction(Validated))) {
  let validated_tx_input = fn(input_label, tx_hex) {
    let assert Ok(tx_bytes) = bit_array.base16_decode(tx_hex)
    let assert Ok(parsed_tx) = btc_tx.decode(tx_bytes)
    let assert Ok(validated_tx) = btc_tx.validate_consensus(parsed_tx)

    PerfInput(input_label, bit_array.byte_size(tx_bytes), validated_tx)
  }

  [
    validated_tx_input("simple legacy tx", simple_legacy_tx),
    validated_tx_input("simple segwit tx", simple_segwit_tx),
    validated_tx_input("witness-heavy p2wsh tx", witness_heavy_p2wsh_tx),
  ]
}

// ==============================================================================
// Run cases
// ==============================================================================

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

// ==============================================================================
// Transaction builders
// ==============================================================================

type SyntheticPrevoutPattern {
  UniquePrevouts
  LastPrevoutDuplicatesFirst
}

fn build_synthetic_legacy_tx(
  input_count: Int,
  prevout_pattern: SyntheticPrevoutPattern,
) -> BitArray {
  let inputs =
    build_synthetic_legacy_inputs(0, input_count, prevout_pattern, <<>>)

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

fn build_synthetic_legacy_inputs(
  index: Int,
  input_count: Int,
  prevout_pattern: SyntheticPrevoutPattern,
  acc: BitArray,
) -> BitArray {
  case index >= input_count {
    True -> acc
    False -> {
      let input =
        build_synthetic_legacy_input(index, input_count, prevout_pattern)

      let acc = <<acc:bits, input:bits>>

      build_synthetic_legacy_inputs(
        index + 1,
        input_count,
        prevout_pattern,
        acc,
      )
    }
  }
}

fn build_synthetic_legacy_input(
  index: Int,
  input_count: Int,
  prevout_pattern: SyntheticPrevoutPattern,
) -> BitArray {
  let prev_txid = {
    let prev_txid_seed =
      synthetic_prev_txid_seed(index, input_count, prevout_pattern)

    <<prev_txid_seed:little-size(32), 0:size(224)>>
  }

  <<
    prev_txid:bits,
    0:little-size(32),
    compact_size(0):bits,
    0xFFFFFFFF:little-size(32),
  >>
}

fn synthetic_prev_txid_seed(
  index: Int,
  input_count: Int,
  prevout_pattern: SyntheticPrevoutPattern,
) -> Int {
  case prevout_pattern {
    UniquePrevouts -> index
    LastPrevoutDuplicatesFirst ->
      case index == input_count - 1 {
        True -> 0
        False -> index
      }
  }
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

// ==============================================================================
// Measurement configs
// ==============================================================================

fn measurement_config(operations_per_timed_call: Int) -> PerfMeasurementConfig {
  PerfMeasurementConfig(
    operations_per_timed_call:,
    warmup_ms: 500,
    duration_ms: 2000,
  )
}

/// Uses larger batches for smaller input/output-vector cases to reduce timer overhead.
fn small_synthetic_tx_measurement_config() -> PerfMeasurementConfig {
  measurement_config(100)
}

/// Uses smaller batches for 500+ input/output-vector cases so slow JS runs still
/// record enough timed calls for stable throughput estimates.
fn large_synthetic_tx_measurement_config() -> PerfMeasurementConfig {
  measurement_config(10)
}
