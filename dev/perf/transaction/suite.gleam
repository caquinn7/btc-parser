//// Performance benchmarks for the public `btc_parser/transaction` workflows.
////
//// The suite measures repeated operations that callers are expected to pay for:
//// decoding, transaction inspection, context-free consensus validation,
//// transaction id computation, and serialization. Input construction, hex
//// decoding, validation of inspection fixtures, and preflight assertions are
//// intentionally performed before timing begins.
////
//// Benchmark cases run one or more logical operations per timed call. Fast
//// cases use larger batches to reduce timer overhead; slower cases can use
//// smaller batches, down to one operation per timed call. Reported throughput
//// and latency are converted back to one logical operation, such as one
//// `decode` or one `compute_txid` call.

import btc_parser/transaction.{
  type ContextFreeValidated, type Decoded, type Transaction, DuplicateInput,
  InsufficientBytes, MaxScriptSize, PolicyLimitExceeded,
  TotalOutputValueOutOfRange, UnexpectedEof,
}
import gleam/bit_array
import gleam/float
import gleam/int
import gleam/list
import gleamy/bench.{
  type BenchResults, type Function, type Input, type Set as BenchSet,
  BenchResults, Duration, Function, Input, Quiet, Set as BenchSet, Warmup,
}
import perf/internal/metadata.{type PerfMetadata}

/// Legacy P2PKH-style spend: one input, with P2WPKH and P2PKH outputs.
const simple_legacy_tx = "0200000001f83913d8a4af4da53774c45cf074d35c8c6df3dd322f5b2a63cfba609ce6fb164d0000006b483045022100ce7670637cc52de4d7a0063e8a253271f09e282f3f99e8d78e20240f3b769ec90220742aea257871b277a19665434e6007850e54fc2bc64a4b5ff05c107ebf82ef460121032af93439c5e3debd027f60975cc0decc6c5b4e51bc44cbeb06a67aad69f45efafdffffff02458f0000000000001600148b068869b732322472e647126c6da8ce4d2bc5778d790000000000001976a914c76c2748f354526db26c9fbd2e2de47b990678fe88ac00000000"

/// SegWit P2WPKH-style spend: one input with a 2-item witness stack.
const simple_segwit_tx = "02000000000101d09297d88fec299d4db728704b56d9e766339b458a42d9a7eac7a1a590e072eb4600000000ffffffff0126071400000000001976a91484548ba3fb385d7d75e5eb31238743206fb8662188ac02483045022100a7690635724cf3ece95afb51b9d0192b3f366b794ee8ccd5cf8dd7bbfaeca027022010376517622589099b18cf43274d145a74a467770973d274949b1c03ef15d550012102019e5e7ef9ee827420bf12e9d8339cdc9102c8fceb5a8187d7bb7072b4db690a00000000"

/// P2WSH multisig spend: four inputs, each with a 5-item witness stack.
const witness_heavy_p2wsh_tx = "010000000001041d77f8ba9cb7292d2c8d28f7860440c20a695a5ac1b008184351bfd167b1de571100000000fdffffff0e3598526cbf5c071dd670bf1ea2a3d3344531b7cdd0b2803822dc875897315f0400000000ffffffff7c40dfa04ff141d4fe9b78672fdeb94606f964adbb30f0740a93d9b561d2a2730500000000ffffffff1afb4550a6b5ba51133ea1049c758ca4b4dd073a63f1bb3980af72de2235bcbe1100000000ffffffff022b3d0f000000000017a914183fad2e1a32ae1bc65ef3ca3664be338e23d676875c53140000000000220020262aa3a633769751560133c647f56948da4099acf9176b51831b17a180aba7900500483045022100b0f4d44a96453f3bd231d392702c6d88f39469c9f56d3d31abf3498a5554a79102202a55e22cd4390c5e7e51ed02321fa45149f9620654a4473125afd8a98502ae3f01483045022100ecc78689ce66035290d331ac9dbf4cb2392f22b7b127bc24dfbe93981fa6f0e902202cfe5fb41d529b49cf7394a7ec49dd69d49e4f1e15bb16a9e1a577468c5e5d5d01483045022100fca785f594914776f74d01943946252f2be2b80b6d96d9d9669e0e89c5715f6702202d649e5cc3a10c68bd23d5c51e6d91123bec8a0fafb896c60a00efad1bddcfbd018b532102532c7265b2a352e9a2e216edddd5f5cb921f6502b30f3dd42535871f2371cf262102705d91275933db288ba8ba940feb56d6d1d804f77b31de16811b518d9b27dab7210276eb537ec808034480ca7d38b431674d5979088cfae267ec8acd2d57e968dac721029fe1a87be21851bc0a4f3ded0e1758bbeecc7be201a1e7ee7282f77886b8b09d54ae050047304402204cbf2e84f64ce78ff8927ab644884fed95903f56cdfe82404d457f31f12b794202206b56afc382429cfdb44b8fbc3cc016440387a177549dc858ec4ccb135cb4e633014730440220129f8de1bce23635b0aae96c05b6671987760ba14fc4caf7345f0f763a40bc39022011420d6f749094b924bbd115576064ec8718de5449d8972d1490ead123c8349101473044022026ff639597d3dc7cc6286bd01b30e09f44ba5725d4c4e9eb5e228299b12664d002201cd70fdea7a16060def6cd345e5e04056975db2347c4a0eaf0728950eeea57cd018b532102b2a01169433767d3d69a6a4540f21ed91e13d86f48bc8f054d25c347287dc75b2103a2b06276509980518481722afe378cc5cce6e331fb90cde756c3233e6d2936722103be3359e6f3f90eb2c78cece0c66e92772d3af3b67a4cf15d8a6ab0e60b07aa082103f28f4f14ef2fc63f840a6fee7117f5f188ed386c9ee37578587a10b34904d91f54ae050047304402206678ad5f654d188e007f497004c7acb1742149c52c83b4baa525c69907ab6e5f02206575e2a323e8f4d61daa8efc334f3e9fb356c9be31939f0b2a9fed7b81af7f420147304402205f41dddf5198b36522c4fad44babb6604638d8e8544e25225d10d38dd5d58dde022002494ef946fd26f9ac10f3d692328a575249f3a0575cebd7ee53600a8c15e7df014730440220424d5833867f6d9225b81ad77dc954fde2c2deb8eda0f60bf5596d3ed908382402204dcc96eea1a0c1a0c82523cc41be1189dfdafedea346c898897f866c32d39983018b532102dd7d60f3278cc6c59358379fbfa1cd3579f287f526b6537ce5258f91f0d17f1e21035289b8951701046732417df9e635db32e395c680b23d1663616c922a409b72a421035cba8725cc106f7188a2ad017a2252c612a174347a88db41b8c93c51f0aadd7421038823210cadbffa3a4e4bd5d19c47dc7a356320c439e074da945e6153d03525da54ae0500483045022100ac5e0d6268b11afa7a2b28fe9ee84da98a4413f5978863de2dfc084c72354d8e02206d45a484d23f98569a73b10a13d2795946cbe81382bc8526305307b3c1ea75d301473044022041ab10e81aa083a0ff4c0851fbb35678dc10b0e1ae838821df82c20d69b40169022027d6d819e8e820945f0537eba476c8aa0eb9ee2a48ab37559ec09fb1ca0e1e9601473044022010ba6168e3ddb7ca2f70b04329ab3c373e0dc594b48999eecb96c8933380e01f02206a71a244e8d2a3f5c152241d581196cfd9b8ae87ed134f9e53cb6c04788c3380018b53210301065882a06bb9246bb761d9905cfeeeeed6ff218777960fb8c65ea5710709fc21031ace900028040ec46b9d89da58f72e41d1a331cf21f4bef5420dfd68680648c321034c3d7498d35ded063716d66c9f9dcdc82d54094d33ae1d72c2a3b547c27ee0ec2103c5d55f5ec64876c572acc0f9de94ada8e7964bca8d27a838291178d15f564cf754ae00000000"

const max_satoshis = 2_100_000_000_000_000

/// Results for one invocation of the performance suite.
pub type PerfResult {
  PerfResult(metadata: PerfMetadata, sections: List(PerfSection))
}

/// Named group of performance cases shown together in the report.
pub type PerfSection {
  PerfSection(title: String, cases: List(PerfCaseResult))
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

type PerfCaseInput(a) {
  PerfCaseInput(label: String, input_size_bytes: Int, value: a)
}

type SyntheticTxSpec {
  Legacy(label: String, input_count: Int, output_count: Int)
  Segwit(
    label: String,
    input_count: Int,
    output_count: Int,
    witness_items_per_input: Int,
    witness_item_size: Int,
  )
}

/// Runs all performance benchmark groups and returns their measurements.
///
/// The returned `PerfResult` preserves the report section grouping used by the
/// development benchmark command.
pub fn run() -> PerfResult {
  let metadata = metadata.current()
  let sections =
    [
      measure_tx_decoding(),
      measure_tx_inspection(),
      measure_context_free_consensus_validation(),
      measure_txid_computation(),
      measure_tx_serialization(),
    ]
    |> list.flatten

  PerfResult(metadata:, sections:)
}

// ==============================================================================
// Transaction decoding
// ==============================================================================

/// Measures `transaction.decode` from byte arrays that are prepared before timing.
///
/// This group includes valid legacy/SegWit fixtures, synthetic many-input and
/// many-output legacy transactions, synthetic SegWit transactions that isolate
/// witness scaling dimensions, malformed inputs that fail after most of the
/// transaction has been decoded, and policy-limit violations that should reject
/// before doing unnecessary payload work.
fn measure_tx_decoding() -> List(PerfSection) {
  [
    measure_fixture_tx_decoding(),
    measure_synthetic_input_tx_decoding(),
    measure_synthetic_output_tx_decoding(),
    measure_synthetic_segwit_input_tx_decoding(),
    measure_synthetic_witness_item_tx_decoding(),
    measure_synthetic_witness_payload_tx_decoding(),
    measure_malformed_tx_decoding(),
    measure_policy_limit_tx_decoding(),
  ]
}

fn measure_fixture_tx_decoding() -> PerfSection {
  let fixture_decode_inputs = [
    fixture_decode_case("simple legacy tx", simple_legacy_tx),
    fixture_decode_case("simple segwit tx", simple_segwit_tx),
    fixture_decode_case("witness-heavy tx", witness_heavy_p2wsh_tx),
  ]

  PerfSection(
    "decode / fixtures",
    measure_decode(fixture_decode_inputs, measurement_config(100)),
  )
}

fn measure_synthetic_input_tx_decoding() -> PerfSection {
  PerfSection(
    "decode / synthetic inputs",
    measure_synthetic_legacy_decode_curve(synthetic_input_count_tx_specs),
  )
}

fn measure_synthetic_output_tx_decoding() -> PerfSection {
  PerfSection(
    "decode / synthetic outputs",
    measure_synthetic_legacy_decode_curve(synthetic_output_count_tx_specs),
  )
}

fn measure_synthetic_segwit_input_tx_decoding() -> PerfSection {
  PerfSection(
    "decode / synthetic segwit inputs",
    measure_synthetic_segwit_input_decode_curve(
      synthetic_segwit_input_count_tx_specs,
    ),
  )
}

fn measure_synthetic_witness_item_tx_decoding() -> PerfSection {
  PerfSection(
    "decode / synthetic witness items",
    measure_synthetic_segwit_decode_curve(synthetic_witness_item_tx_specs),
  )
}

fn measure_synthetic_witness_payload_tx_decoding() -> PerfSection {
  let cases =
    [
      measure_synthetic_decoding(
        synthetic_witness_payload_tx_specs([64, 10_000]),
        small_synthetic_tx_measurement_config(),
      ),
      measure_synthetic_decoding(
        synthetic_witness_payload_tx_specs([100_000]),
        large_synthetic_tx_measurement_config(),
      ),
    ]
    |> list.flatten

  PerfSection("decode / synthetic witness payload", cases)
}

fn measure_malformed_tx_decoding() -> PerfSection {
  let malformed_decode_inputs = [
    late_truncated_decode_case(
      "late truncated simple legacy tx",
      simple_legacy_tx,
    ),
    late_truncated_decode_case(
      "late truncated simple segwit tx",
      simple_segwit_tx,
    ),
    late_truncated_witness_payload_decode_case(
      "late truncated witness payload tx",
    ),
  ]

  PerfSection(
    "decode / malformed",
    measure_decode(malformed_decode_inputs, measurement_config(100)),
  )
}

fn measure_policy_limit_tx_decoding() -> PerfSection {
  let policy_limit_decode_inputs = [
    oversized_scriptsig_policy_decode_case("oversized scriptSig tx"),
  ]

  PerfSection(
    "decode / policy limits",
    measure_decode(policy_limit_decode_inputs, measurement_config(100)),
  )
}

fn measure_decode(
  inputs: List(PerfCaseInput(BitArray)),
  config: PerfMeasurementConfig,
) -> List(PerfCaseResult) {
  run_bench_cases(
    inputs,
    [
      Function(
        "decode",
        bench.repeat(config.operations_per_timed_call, transaction.decode),
      ),
    ],
    config,
  )
}

fn measure_synthetic_legacy_decode_curve(
  build_specs: fn(List(Int)) -> List(SyntheticTxSpec),
) -> List(PerfCaseResult) {
  [
    measure_synthetic_decoding(
      build_specs([1, 100]),
      small_synthetic_tx_measurement_config(),
    ),
    measure_synthetic_decoding(
      build_specs([1000]),
      large_synthetic_tx_measurement_config(),
    ),
  ]
  |> list.flatten
}

fn measure_synthetic_segwit_decode_curve(
  build_specs: fn(List(Int)) -> List(SyntheticTxSpec),
) -> List(PerfCaseResult) {
  [
    measure_synthetic_decoding(
      build_specs([1, 100]),
      small_synthetic_tx_measurement_config(),
    ),
    measure_synthetic_decoding(
      build_specs([1000]),
      large_synthetic_tx_measurement_config(),
    ),
  ]
  |> list.flatten
}

fn measure_synthetic_segwit_input_decode_curve(
  build_specs: fn(List(Int)) -> List(SyntheticTxSpec),
) -> List(PerfCaseResult) {
  [
    measure_synthetic_decoding(
      build_specs([1]),
      small_synthetic_tx_measurement_config(),
    ),
    measure_synthetic_decoding(
      build_specs([100]),
      medium_synthetic_tx_measurement_config(),
    ),
    measure_synthetic_decoding(
      build_specs([1000]),
      slow_synthetic_tx_measurement_config(),
    ),
  ]
  |> list.flatten
}

fn measure_synthetic_decoding(
  specs: List(SyntheticTxSpec),
  config: PerfMeasurementConfig,
) -> List(PerfCaseResult) {
  specs
  |> list.map(synthetic_decode_case)
  |> measure_decode(config)
}

fn synthetic_input_count_tx_specs(
  input_counts: List(Int),
) -> List(SyntheticTxSpec) {
  input_counts
  |> list.map(fn(input_count) {
    Legacy(
      label: "legacy tx inputs=" <> int.to_string(input_count),
      input_count:,
      output_count: 1,
    )
  })
}

fn synthetic_output_count_tx_specs(
  output_counts: List(Int),
) -> List(SyntheticTxSpec) {
  output_counts
  |> list.map(fn(output_count) {
    Legacy(
      label: "legacy tx outputs=" <> int.to_string(output_count),
      input_count: 1,
      output_count:,
    )
  })
}

fn synthetic_segwit_input_count_tx_specs(
  input_counts: List(Int),
) -> List(SyntheticTxSpec) {
  input_counts
  |> list.map(fn(input_count) {
    Segwit(
      label: "segwit tx inputs=" <> int.to_string(input_count),
      input_count:,
      output_count: 1,
      witness_items_per_input: 2,
      witness_item_size: 32,
    )
  })
}

fn synthetic_witness_item_tx_specs(
  witness_item_counts: List(Int),
) -> List(SyntheticTxSpec) {
  witness_item_counts
  |> list.map(fn(witness_items_per_input) {
    Segwit(
      label: "segwit tx witness_items="
        <> int.to_string(witness_items_per_input),
      input_count: 1,
      output_count: 1,
      witness_items_per_input:,
      witness_item_size: 32,
    )
  })
}

fn synthetic_witness_payload_tx_specs(
  witness_item_sizes: List(Int),
) -> List(SyntheticTxSpec) {
  witness_item_sizes
  |> list.map(fn(witness_item_size) {
    Segwit(
      label: "segwit tx witness_bytes=" <> int.to_string(witness_item_size),
      input_count: 1,
      output_count: 1,
      witness_items_per_input: 1,
      witness_item_size:,
    )
  })
}

fn synthetic_decode_case(
  synthetic_spec: SyntheticTxSpec,
) -> PerfCaseInput(BitArray) {
  let #(label, tx_bytes) = synthetic_tx_spec_to_bytes(synthetic_spec)

  let assert Ok(_) = transaction.decode(tx_bytes)

  PerfCaseInput(label, bit_array.byte_size(tx_bytes), tx_bytes)
}

fn synthetic_tx_spec_to_bytes(
  synthetic_spec: SyntheticTxSpec,
) -> #(String, BitArray) {
  case synthetic_spec {
    Legacy(label, input_count, output_count) -> #(
      label,
      build_synthetic_legacy_tx(input_count, output_count, UniqueOutPoints),
    )

    Segwit(
      label,
      input_count,
      output_count,
      witness_items_per_input,
      witness_item_size,
    ) -> #(
      label,
      build_synthetic_segwit_tx(
        input_count,
        output_count,
        witness_items_per_input,
        witness_item_size,
      ),
    )
  }
}

fn fixture_decode_case(
  input_label: String,
  tx_hex: String,
) -> PerfCaseInput(BitArray) {
  let assert Ok(tx_bytes) = bit_array.base16_decode(tx_hex)
  let assert Ok(_) = transaction.decode(tx_bytes)

  PerfCaseInput(input_label, bit_array.byte_size(tx_bytes), tx_bytes)
}

fn late_truncated_decode_case(
  input_label: String,
  tx_hex: String,
) -> PerfCaseInput(BitArray) {
  let assert Ok(valid_tx_bytes) = bit_array.base16_decode(tx_hex)
  let tx_bytes = drop_last_byte(valid_tx_bytes)
  let assert Error(decode_err) = transaction.decode(tx_bytes)

  assert transaction.get_decode_error_kind(decode_err)
    == UnexpectedEof(bytes_needed: 4, remaining: 3)

  PerfCaseInput(input_label, bit_array.byte_size(tx_bytes), tx_bytes)
}

fn late_truncated_witness_payload_decode_case(
  input_label: String,
) -> PerfCaseInput(BitArray) {
  let tx_bytes = build_late_truncated_witness_payload_tx()
  let assert Error(decode_err) = transaction.decode(tx_bytes)

  assert transaction.get_decode_error_kind(decode_err)
    == InsufficientBytes(claimed: 32, remaining: 31)

  PerfCaseInput(input_label, bit_array.byte_size(tx_bytes), tx_bytes)
}

fn drop_last_byte(bytes: BitArray) -> BitArray {
  let length = bit_array.byte_size(bytes)
  let assert Ok(truncated) = bit_array.slice(bytes, 0, length - 1)
  truncated
}

fn oversized_scriptsig_policy_decode_case(
  input_label: String,
) -> PerfCaseInput(BitArray) {
  let max_script_size =
    transaction.default_decode_policy()
    |> transaction.decode_policy_max_script_size

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

  let assert Error(decode_err) = transaction.decode(tx_bytes)
  assert transaction.get_decode_error_kind(decode_err)
    == PolicyLimitExceeded(MaxScriptSize, script_sig_size, max_script_size)

  PerfCaseInput(input_label, bit_array.byte_size(tx_bytes), tx_bytes)
}

// ==============================================================================
// Transaction inspection
// ==============================================================================

/// Measures read-only transaction inspection helpers over transactions that
/// have already been decoded and context-free validated before timing begins.
fn measure_tx_inspection() -> List(PerfSection) {
  [measure_coinbase_shape_inspection()]
}

fn measure_coinbase_shape_inspection() -> PerfSection {
  let small_config = fast_measurement_config(100)
  let large_config = fast_measurement_config(10)

  let cases =
    [
      measure_coinbase_shape_input_counts([20, 100], small_config),
      measure_coinbase_shape_input_counts([1000], large_config),
    ]
    |> list.flatten

  PerfSection("inspection / coinbase shape", cases)
}

fn measure_coinbase_shape_input_counts(
  input_counts: List(Int),
  config: PerfMeasurementConfig,
) -> List(PerfCaseResult) {
  input_counts
  |> list.map(coinbase_shape_case)
  |> measure_coinbase_shape(config)
}

fn measure_coinbase_shape(
  inputs: List(PerfCaseInput(Transaction(ContextFreeValidated))),
  config: PerfMeasurementConfig,
) -> List(PerfCaseResult) {
  run_bench_cases(
    inputs,
    [
      Function(
        "has_coinbase_shape",
        bench.repeat(
          config.operations_per_timed_call,
          transaction.has_coinbase_shape,
        ),
      ),
    ],
    config,
  )
}

fn coinbase_shape_case(
  input_count: Int,
) -> PerfCaseInput(Transaction(ContextFreeValidated)) {
  let tx_bytes = build_synthetic_legacy_tx(input_count, 1, UniqueOutPoints)

  let assert Ok(decoded_tx) = transaction.decode(tx_bytes)
  let assert Ok(validated_tx) =
    transaction.validate_context_free_consensus(decoded_tx)

  assert !transaction.has_coinbase_shape(validated_tx)

  PerfCaseInput(
    "regular inputs=" <> int.to_string(input_count),
    bit_array.byte_size(tx_bytes),
    validated_tx,
  )
}

// ==============================================================================
// Context-free consensus validation
// ==============================================================================

/// Measures `transaction.validate_context_free_consensus` on already-decoded
/// synthetic transactions.
///
/// The valid cases exercise full success-path input-count and output-count
/// scanning. The late-duplicate cases place the duplicate outpoint at the end so
/// rejection still walks nearly the whole input list.
fn measure_context_free_consensus_validation() -> List(PerfSection) {
  [
    measure_context_free_consensus_validation_valid_inputs(),
    measure_context_free_consensus_validation_valid_outputs(),
    measure_context_free_consensus_validation_duplicate_input(),
    measure_context_free_consensus_validation_output_overflow(),
  ]
}

fn measure_context_free_consensus_validation_valid_inputs() -> PerfSection {
  let cases =
    [
      measure_validation_input_counts(
        [20, 100],
        valid_input_count_consensus_case,
        small_synthetic_tx_measurement_config(),
      ),
      measure_validation_input_counts(
        [1000],
        valid_input_count_consensus_case,
        large_synthetic_tx_measurement_config(),
      ),
    ]
    |> list.flatten

  PerfSection("validate_context_free_consensus / valid inputs", cases)
}

fn measure_context_free_consensus_validation_valid_outputs() -> PerfSection {
  let cases =
    [
      measure_validation_output_counts(
        [20, 100],
        small_synthetic_tx_measurement_config(),
      ),
      measure_validation_output_counts(
        [1000],
        large_synthetic_tx_measurement_config(),
      ),
    ]
    |> list.flatten

  PerfSection("validate_context_free_consensus / valid outputs", cases)
}

fn measure_context_free_consensus_validation_duplicate_input() -> PerfSection {
  let cases =
    [
      measure_validation_input_counts(
        [20, 100],
        late_duplicate_input_count_consensus_case,
        small_synthetic_tx_measurement_config(),
      ),
      measure_validation_input_counts(
        [1000],
        late_duplicate_input_count_consensus_case,
        large_synthetic_tx_measurement_config(),
      ),
    ]
    |> list.flatten

  PerfSection("validate_context_free_consensus / duplicate inputs", cases)
}

fn measure_context_free_consensus_validation_output_overflow() -> PerfSection {
  let cases =
    [
      measure_validation_output_overflow_counts(
        [20, 100],
        small_synthetic_tx_measurement_config(),
      ),
      measure_validation_output_overflow_counts(
        [1000],
        large_synthetic_tx_measurement_config(),
      ),
    ]
    |> list.flatten

  PerfSection("validate_context_free_consensus / output overflow", cases)
}

fn measure_validation_input_counts(
  input_counts: List(Int),
  build_case: fn(Int) -> PerfCaseInput(Transaction(Decoded)),
  config: PerfMeasurementConfig,
) -> List(PerfCaseResult) {
  input_counts
  |> list.map(build_case)
  |> measure_validate_context_free_consensus(config)
}

fn measure_validation_output_counts(
  output_counts: List(Int),
  config: PerfMeasurementConfig,
) -> List(PerfCaseResult) {
  output_counts
  |> list.map(valid_output_count_consensus_case)
  |> measure_validate_context_free_consensus(config)
}

fn measure_validation_output_overflow_counts(
  output_counts: List(Int),
  config: PerfMeasurementConfig,
) -> List(PerfCaseResult) {
  output_counts
  |> list.map(output_overflow_count_consensus_case)
  |> measure_validate_context_free_consensus(config)
}

fn valid_input_count_consensus_case(
  input_count: Int,
) -> PerfCaseInput(Transaction(Decoded)) {
  context_free_consensus_validation_case(
    "valid inputs=" <> int.to_string(input_count),
    build_synthetic_legacy_tx(input_count, 1, UniqueOutPoints),
    ExpectValid,
  )
}

fn valid_output_count_consensus_case(
  output_count: Int,
) -> PerfCaseInput(Transaction(Decoded)) {
  context_free_consensus_validation_case(
    "valid outputs=" <> int.to_string(output_count),
    build_synthetic_legacy_tx(1, output_count, UniqueOutPoints),
    ExpectValid,
  )
}

fn late_duplicate_input_count_consensus_case(
  input_count: Int,
) -> PerfCaseInput(Transaction(Decoded)) {
  context_free_consensus_validation_case(
    "late duplicate inputs=" <> int.to_string(input_count),
    build_synthetic_legacy_tx(input_count, 1, LastOutPointDuplicatesFirst),
    ExpectLateDuplicate(input_count:),
  )
}

fn output_overflow_count_consensus_case(
  output_count: Int,
) -> PerfCaseInput(Transaction(Decoded)) {
  let outputs = build_output_overflow_outputs(output_count)

  context_free_consensus_validation_case(
    "output overflow outputs=" <> int.to_string(output_count),
    build_synthetic_legacy_tx_with_outputs(
      1,
      outputs,
      output_count,
      UniqueOutPoints,
    ),
    ExpectOutputOverflow(output_count:),
  )
}

fn context_free_consensus_validation_case(
  label: String,
  tx_bytes: BitArray,
  expectation: ContextFreeConsensusValidationExpectation,
) -> PerfCaseInput(Transaction(Decoded)) {
  let assert Ok(decoded_tx) = transaction.decode(tx_bytes)
  preflight_validate_context_free_consensus(decoded_tx, expectation)

  PerfCaseInput(label, bit_array.byte_size(tx_bytes), decoded_tx)
}

fn measure_validate_context_free_consensus(
  inputs: List(PerfCaseInput(Transaction(Decoded))),
  config: PerfMeasurementConfig,
) -> List(PerfCaseResult) {
  run_bench_cases(
    inputs,
    [
      Function(
        "validate_context_free_consensus",
        bench.repeat(
          config.operations_per_timed_call,
          transaction.validate_context_free_consensus,
        ),
      ),
    ],
    config,
  )
}

type ContextFreeConsensusValidationExpectation {
  ExpectValid
  ExpectLateDuplicate(input_count: Int)
  ExpectOutputOverflow(output_count: Int)
}

fn preflight_validate_context_free_consensus(
  decoded_tx: Transaction(Decoded),
  expectation: ContextFreeConsensusValidationExpectation,
) -> Nil {
  case expectation {
    ExpectValid -> {
      let assert Ok(_) = transaction.validate_context_free_consensus(decoded_tx)
      Nil
    }

    ExpectLateDuplicate(input_count) -> {
      let assert [first_input, ..] = transaction.get_inputs(decoded_tx)
      let duplicate_outpoint = transaction.get_input_outpoint(first_input)

      assert transaction.validate_context_free_consensus(decoded_tx)
        == Error([DuplicateInput(duplicate_outpoint, 0, input_count - 1)])
    }

    ExpectOutputOverflow(output_count) -> {
      assert transaction.validate_context_free_consensus(decoded_tx)
        == Error([
          TotalOutputValueOutOfRange(
            output_count - 1,
            max_satoshis + output_count - 1,
          ),
        ])
    }
  }
}

// ==============================================================================
// Txid computation & serialization
// ==============================================================================

/// Measures `compute_txid` and `compute_wtxid` on already-decoded transactions.
///
/// This excludes decode cost, leaving serialization and double-SHA256 work
/// inside the timed region.
fn measure_txid_computation() -> List(PerfSection) {
  [
    measure_fixture_txid_computation(),
    measure_synthetic_input_txid_computation(),
    measure_synthetic_output_txid_computation(),
    measure_synthetic_segwit_input_txid_computation(),
    measure_synthetic_witness_item_txid_computation(),
    measure_synthetic_witness_payload_txid_computation(),
  ]
}

fn measure_fixture_txid_computation() -> PerfSection {
  PerfSection(
    "txid computation / fixtures",
    measure_txid_functions(fixture_decoded_tx_cases(), measurement_config(100)),
  )
}

fn measure_synthetic_input_txid_computation() -> PerfSection {
  PerfSection(
    "txid computation / synthetic inputs",
    measure_synthetic_legacy_txid_curve(synthetic_input_count_tx_specs),
  )
}

fn measure_synthetic_output_txid_computation() -> PerfSection {
  PerfSection(
    "txid computation / synthetic outputs",
    measure_synthetic_legacy_txid_curve(synthetic_output_count_tx_specs),
  )
}

fn measure_synthetic_segwit_input_txid_computation() -> PerfSection {
  PerfSection(
    "txid computation / synthetic segwit inputs",
    measure_synthetic_segwit_txid_curve(synthetic_segwit_input_count_tx_specs),
  )
}

fn measure_synthetic_witness_item_txid_computation() -> PerfSection {
  PerfSection(
    "txid computation / synthetic witness items",
    measure_synthetic_witness_wtxid_curve(synthetic_witness_item_tx_specs),
  )
}

fn measure_synthetic_witness_payload_txid_computation() -> PerfSection {
  let small_specs = synthetic_witness_payload_tx_specs([64, 10_000])
  let large_specs = synthetic_witness_payload_tx_specs([100_000])
  let small_config = small_synthetic_tx_measurement_config()
  let large_config = large_synthetic_tx_measurement_config()

  let cases =
    [
      measure_synthetic_decoded_function(
        small_specs,
        small_config,
        "compute_wtxid",
        transaction.compute_wtxid,
      ),
      measure_synthetic_decoded_function(
        large_specs,
        large_config,
        "compute_wtxid",
        transaction.compute_wtxid,
      ),
    ]
    |> list.flatten

  PerfSection("txid computation / synthetic witness payload", cases)
}

/// Measures `to_stripped_bytes` and `to_wire_bytes` on already-decoded
/// transactions.
///
/// The benchmark set includes legacy and SegWit transactions
/// because witness serialization changes the code path and payload shape.
fn measure_tx_serialization() -> List(PerfSection) {
  [
    measure_fixture_tx_serialization(),
    measure_synthetic_input_tx_serialization(),
    measure_synthetic_output_tx_serialization(),
    measure_synthetic_segwit_input_tx_serialization(),
    measure_synthetic_witness_item_tx_serialization(),
    measure_synthetic_witness_payload_tx_serialization(),
  ]
}

fn measure_fixture_tx_serialization() -> PerfSection {
  PerfSection(
    "serialization / fixtures",
    measure_serialization_functions(
      fixture_decoded_tx_cases(),
      measurement_config(100),
    ),
  )
}

fn measure_synthetic_input_tx_serialization() -> PerfSection {
  PerfSection(
    "serialization / synthetic inputs",
    measure_synthetic_legacy_serialization_curve(synthetic_input_count_tx_specs),
  )
}

fn measure_synthetic_output_tx_serialization() -> PerfSection {
  PerfSection(
    "serialization / synthetic outputs",
    measure_synthetic_legacy_serialization_curve(
      synthetic_output_count_tx_specs,
    ),
  )
}

fn measure_synthetic_segwit_input_tx_serialization() -> PerfSection {
  PerfSection(
    "serialization / synthetic segwit inputs",
    measure_synthetic_segwit_serialization_curve(
      synthetic_segwit_input_count_tx_specs,
    ),
  )
}

fn measure_synthetic_witness_item_tx_serialization() -> PerfSection {
  PerfSection(
    "serialization / synthetic witness items",
    measure_synthetic_witness_serialization_curve(
      synthetic_witness_item_tx_specs,
    ),
  )
}

fn measure_synthetic_witness_payload_tx_serialization() -> PerfSection {
  let small_specs = synthetic_witness_payload_tx_specs([64, 10_000])
  let large_specs = synthetic_witness_payload_tx_specs([100_000])
  let small_config = small_synthetic_tx_measurement_config()
  let large_config = large_synthetic_tx_measurement_config()

  let cases =
    [
      measure_synthetic_decoded_function(
        small_specs,
        small_config,
        "to_wire_bytes",
        transaction.to_wire_bytes,
      ),
      measure_synthetic_decoded_function(
        large_specs,
        large_config,
        "to_wire_bytes",
        transaction.to_wire_bytes,
      ),
    ]
    |> list.flatten

  PerfSection("serialization / synthetic witness payload", cases)
}

fn measure_synthetic_legacy_txid_curve(
  build_specs: fn(List(Int)) -> List(SyntheticTxSpec),
) -> List(PerfCaseResult) {
  let small_specs = build_specs([20, 100])
  let large_specs = build_specs([1000])
  let small_config = small_synthetic_tx_measurement_config()
  let large_config = large_synthetic_tx_measurement_config()

  [
    measure_synthetic_decoded_function(
      small_specs,
      small_config,
      "compute_txid",
      transaction.compute_txid,
    ),
    measure_synthetic_decoded_function(
      large_specs,
      large_config,
      "compute_txid",
      transaction.compute_txid,
    ),
  ]
  |> list.flatten
}

fn measure_synthetic_legacy_serialization_curve(
  build_specs: fn(List(Int)) -> List(SyntheticTxSpec),
) -> List(PerfCaseResult) {
  let small_specs = build_specs([20, 100])
  let large_specs = build_specs([1000])
  let small_config = small_synthetic_tx_measurement_config()
  let large_config = large_synthetic_tx_measurement_config()

  [
    measure_synthetic_decoded_function(
      small_specs,
      small_config,
      "to_stripped_bytes",
      transaction.to_stripped_bytes,
    ),
    measure_synthetic_decoded_function(
      large_specs,
      large_config,
      "to_stripped_bytes",
      transaction.to_stripped_bytes,
    ),
  ]
  |> list.flatten
}

fn measure_synthetic_segwit_txid_curve(
  build_specs: fn(List(Int)) -> List(SyntheticTxSpec),
) -> List(PerfCaseResult) {
  let small_specs = build_specs([20, 100])
  let large_specs = build_specs([1000])

  let small_witness_specs = build_specs([20])
  let medium_witness_specs = build_specs([100])
  let slow_witness_specs = build_specs([1000])

  let small_config = small_synthetic_tx_measurement_config()
  let medium_config = medium_synthetic_tx_measurement_config()
  let large_config = large_synthetic_tx_measurement_config()
  let slow_config = slow_synthetic_tx_measurement_config()

  [
    measure_synthetic_decoded_function(
      small_specs,
      small_config,
      "compute_txid",
      transaction.compute_txid,
    ),
    measure_synthetic_decoded_function(
      large_specs,
      large_config,
      "compute_txid",
      transaction.compute_txid,
    ),
    measure_synthetic_decoded_function(
      small_witness_specs,
      small_config,
      "compute_wtxid",
      transaction.compute_wtxid,
    ),
    measure_synthetic_decoded_function(
      medium_witness_specs,
      medium_config,
      "compute_wtxid",
      transaction.compute_wtxid,
    ),
    measure_synthetic_decoded_function(
      slow_witness_specs,
      slow_config,
      "compute_wtxid",
      transaction.compute_wtxid,
    ),
  ]
  |> list.flatten
}

fn measure_synthetic_witness_wtxid_curve(
  build_specs: fn(List(Int)) -> List(SyntheticTxSpec),
) -> List(PerfCaseResult) {
  let small_specs = build_specs([20, 100])
  let large_specs = build_specs([1000])
  let small_config = small_synthetic_tx_measurement_config()
  let large_config = large_synthetic_tx_measurement_config()

  [
    measure_synthetic_decoded_function(
      small_specs,
      small_config,
      "compute_wtxid",
      transaction.compute_wtxid,
    ),
    measure_synthetic_decoded_function(
      large_specs,
      large_config,
      "compute_wtxid",
      transaction.compute_wtxid,
    ),
  ]
  |> list.flatten
}

fn measure_synthetic_segwit_serialization_curve(
  build_specs: fn(List(Int)) -> List(SyntheticTxSpec),
) -> List(PerfCaseResult) {
  let small_specs = build_specs([20, 100])
  let large_specs = build_specs([1000])

  let small_witness_specs = build_specs([20])
  let medium_witness_specs = build_specs([100])
  let slow_witness_specs = build_specs([1000])

  let small_config = small_synthetic_tx_measurement_config()
  let medium_config = medium_synthetic_tx_measurement_config()
  let large_config = large_synthetic_tx_measurement_config()
  let slow_config = slow_synthetic_tx_measurement_config()

  [
    measure_synthetic_decoded_function(
      small_specs,
      small_config,
      "to_stripped_bytes",
      transaction.to_stripped_bytes,
    ),
    measure_synthetic_decoded_function(
      large_specs,
      large_config,
      "to_stripped_bytes",
      transaction.to_stripped_bytes,
    ),
    measure_synthetic_decoded_function(
      small_witness_specs,
      small_config,
      "to_wire_bytes",
      transaction.to_wire_bytes,
    ),
    measure_synthetic_decoded_function(
      medium_witness_specs,
      medium_config,
      "to_wire_bytes",
      transaction.to_wire_bytes,
    ),
    measure_synthetic_decoded_function(
      slow_witness_specs,
      slow_config,
      "to_wire_bytes",
      transaction.to_wire_bytes,
    ),
  ]
  |> list.flatten
}

fn measure_synthetic_witness_serialization_curve(
  build_specs: fn(List(Int)) -> List(SyntheticTxSpec),
) -> List(PerfCaseResult) {
  let small_specs = build_specs([20, 100])
  let large_specs = build_specs([1000])
  let small_config = small_synthetic_tx_measurement_config()
  let large_config = large_synthetic_tx_measurement_config()

  [
    measure_synthetic_decoded_function(
      small_specs,
      small_config,
      "to_wire_bytes",
      transaction.to_wire_bytes,
    ),
    measure_synthetic_decoded_function(
      large_specs,
      large_config,
      "to_wire_bytes",
      transaction.to_wire_bytes,
    ),
  ]
  |> list.flatten
}

fn measure_synthetic_decoded_function(
  specs: List(SyntheticTxSpec),
  config: PerfMeasurementConfig,
  function_label: String,
  measured_function: fn(Transaction(Decoded)) -> BitArray,
) -> List(PerfCaseResult) {
  specs
  |> list.map(synthetic_decoded_case)
  |> measure_decoded_tx_function(config, function_label, measured_function)
}

fn measure_txid_functions(
  inputs: List(PerfCaseInput(Transaction(Decoded))),
  config: PerfMeasurementConfig,
) -> List(PerfCaseResult) {
  [
    measure_decoded_tx_function(
      inputs,
      config,
      "compute_txid",
      transaction.compute_txid,
    ),
    measure_decoded_tx_function(
      inputs,
      config,
      "compute_wtxid",
      transaction.compute_wtxid,
    ),
  ]
  |> list.flatten
}

fn measure_serialization_functions(
  inputs: List(PerfCaseInput(Transaction(Decoded))),
  config: PerfMeasurementConfig,
) -> List(PerfCaseResult) {
  [
    measure_decoded_tx_function(
      inputs,
      config,
      "to_stripped_bytes",
      transaction.to_stripped_bytes,
    ),
    measure_decoded_tx_function(
      inputs,
      config,
      "to_wire_bytes",
      transaction.to_wire_bytes,
    ),
  ]
  |> list.flatten
}

fn measure_decoded_tx_function(
  inputs: List(PerfCaseInput(Transaction(Decoded))),
  config: PerfMeasurementConfig,
  function_label: String,
  measured_function: fn(Transaction(Decoded)) -> BitArray,
) -> List(PerfCaseResult) {
  run_bench_cases(
    inputs,
    [
      Function(
        function_label,
        bench.repeat(config.operations_per_timed_call, measured_function),
      ),
    ],
    config,
  )
}

fn synthetic_decoded_case(
  synthetic_spec: SyntheticTxSpec,
) -> PerfCaseInput(Transaction(Decoded)) {
  let #(label, tx_bytes) = synthetic_tx_spec_to_bytes(synthetic_spec)
  let assert Ok(decoded_tx) = transaction.decode(tx_bytes)
  PerfCaseInput(label, bit_array.byte_size(tx_bytes), decoded_tx)
}

fn fixture_decoded_tx_cases() -> List(PerfCaseInput(Transaction(Decoded))) {
  let fixture_decoded_tx_case = fn(input_label, tx_hex) {
    let assert Ok(tx_bytes) = bit_array.base16_decode(tx_hex)
    let assert Ok(decoded_tx) = transaction.decode(tx_bytes)
    PerfCaseInput(input_label, bit_array.byte_size(tx_bytes), decoded_tx)
  }

  [
    fixture_decoded_tx_case("simple legacy tx", simple_legacy_tx),
    fixture_decoded_tx_case("simple segwit tx", simple_segwit_tx),
    fixture_decoded_tx_case("witness-heavy tx", witness_heavy_p2wsh_tx),
  ]
}

// ==============================================================================
// Run cases
// ==============================================================================

fn run_bench_cases(
  inputs: List(PerfCaseInput(a)),
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

fn to_bench_input(input: PerfCaseInput(a)) -> Input(a) {
  let PerfCaseInput(label, _, value) = input
  Input(label, value)
}

fn build_case_results(
  results: BenchResults,
  inputs: List(PerfCaseInput(a)),
  config: PerfMeasurementConfig,
) -> List(PerfCaseResult) {
  let BenchResults(_options, sets) = results
  list.map(sets, build_set_case_result(_, inputs, config))
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

// ==============================================================================
// Transaction builders
// ==============================================================================

type SyntheticOutPointPattern {
  UniqueOutPoints
  LastOutPointDuplicatesFirst
}

fn build_synthetic_legacy_tx(
  input_count: Int,
  output_count: Int,
  outpoint_pattern: SyntheticOutPointPattern,
) -> BitArray {
  let outputs = build_synthetic_legacy_outputs(output_count)

  build_synthetic_legacy_tx_with_outputs(
    input_count,
    outputs,
    output_count,
    outpoint_pattern,
  )
}

fn build_synthetic_legacy_tx_with_outputs(
  input_count: Int,
  outputs: BitArray,
  output_count: Int,
  outpoint_pattern: SyntheticOutPointPattern,
) -> BitArray {
  let inputs = build_synthetic_legacy_inputs(input_count, outpoint_pattern)

  <<
    1:little-size(32),
    compact_size(input_count):bits,
    inputs:bits,
    compact_size(output_count):bits,
    outputs:bits,
    0:little-size(32),
  >>
}

fn build_synthetic_segwit_tx(
  input_count: Int,
  output_count: Int,
  witness_items_per_input: Int,
  witness_item_size: Int,
) -> BitArray {
  let inputs = build_synthetic_legacy_inputs(input_count, UniqueOutPoints)

  let outputs = build_synthetic_legacy_outputs(output_count)

  let witnesses =
    build_synthetic_witnesses(
      input_count,
      witness_items_per_input,
      witness_item_size,
    )

  <<
    1:little-size(32),
    0x00,
    0x01,
    compact_size(input_count):bits,
    inputs:bits,
    compact_size(output_count):bits,
    outputs:bits,
    witnesses:bits,
    0:little-size(32),
  >>
}

fn build_late_truncated_witness_payload_tx() -> BitArray {
  let inputs = build_synthetic_legacy_inputs(1, UniqueOutPoints)
  let outputs = build_synthetic_legacy_outputs(1)
  let complete_items = build_synthetic_witness_items(99, 32)
  let truncated_payload = <<0:size({ 31 * 8 })>>

  <<
    1:little-size(32),
    0x00,
    0x01,
    compact_size(1):bits,
    inputs:bits,
    compact_size(1):bits,
    outputs:bits,
    compact_size(100):bits,
    complete_items:bits,
    compact_size(32):bits,
    truncated_payload:bits,
  >>
}

fn build_synthetic_legacy_inputs(
  input_count: Int,
  outpoint_pattern: SyntheticOutPointPattern,
) -> BitArray {
  build_synthetic_legacy_inputs_loop(0, input_count, outpoint_pattern, [])
}

fn build_synthetic_legacy_inputs_loop(
  index: Int,
  input_count: Int,
  outpoint_pattern: SyntheticOutPointPattern,
  acc: List(BitArray),
) -> BitArray {
  case index >= input_count {
    True -> concat_reversed(acc)
    False -> {
      let input =
        build_synthetic_legacy_input(index, input_count, outpoint_pattern)

      build_synthetic_legacy_inputs_loop(
        index + 1,
        input_count,
        outpoint_pattern,
        [input, ..acc],
      )
    }
  }
}

fn build_synthetic_legacy_input(
  index: Int,
  input_count: Int,
  outpoint_pattern: SyntheticOutPointPattern,
) -> BitArray {
  let outpoint_txid_seed =
    synthetic_outpoint_txid_seed(index, input_count, outpoint_pattern)

  let outpoint_txid = <<outpoint_txid_seed:little-size(32), 0:size(224)>>

  <<
    outpoint_txid:bits,
    0:little-size(32),
    compact_size(0):bits,
    0xFFFFFFFF:little-size(32),
  >>
}

fn build_synthetic_legacy_outputs(output_count: Int) -> BitArray {
  build_synthetic_legacy_outputs_loop(output_count, [])
}

fn build_synthetic_legacy_outputs_loop(
  remaining: Int,
  acc: List(BitArray),
) -> BitArray {
  case remaining <= 0 {
    True -> concat_reversed(acc)
    False -> {
      let output = build_synthetic_legacy_output(1000)
      build_synthetic_legacy_outputs_loop(remaining - 1, [output, ..acc])
    }
  }
}

fn build_synthetic_legacy_output(value: Int) -> BitArray {
  <<
    value:little-size(64),
    compact_size(0):bits,
  >>
}

fn build_output_overflow_outputs(output_count: Int) -> BitArray {
  build_output_overflow_outputs_loop(0, output_count, [])
}

fn build_output_overflow_outputs_loop(
  index: Int,
  output_count: Int,
  acc: List(BitArray),
) -> BitArray {
  case index >= output_count {
    True -> concat_reversed(acc)
    False -> {
      let value = case index == output_count - 1 {
        True -> max_satoshis
        False -> 1
      }
      let output = build_synthetic_legacy_output(value)

      build_output_overflow_outputs_loop(index + 1, output_count, [
        output,
        ..acc
      ])
    }
  }
}

fn build_synthetic_witnesses(
  input_count: Int,
  items_per_input: Int,
  item_size: Int,
) -> BitArray {
  build_synthetic_witnesses_loop(input_count, items_per_input, item_size, [])
}

fn build_synthetic_witnesses_loop(
  remaining: Int,
  items_per_input: Int,
  item_size: Int,
  acc: List(BitArray),
) -> BitArray {
  case remaining <= 0 {
    True -> concat_reversed(acc)
    False -> {
      let witness_stack =
        build_synthetic_witness_stack(items_per_input, item_size)

      build_synthetic_witnesses_loop(remaining - 1, items_per_input, item_size, [
        witness_stack,
        ..acc
      ])
    }
  }
}

fn build_synthetic_witness_stack(
  items_per_input: Int,
  item_size: Int,
) -> BitArray {
  let items = build_synthetic_witness_items(items_per_input, item_size)
  <<
    compact_size(items_per_input):bits,
    items:bits,
  >>
}

fn build_synthetic_witness_items(remaining: Int, item_size: Int) -> BitArray {
  build_synthetic_witness_items_loop(remaining, item_size, [])
}

fn build_synthetic_witness_items_loop(
  remaining: Int,
  item_size: Int,
  acc: List(BitArray),
) -> BitArray {
  case remaining <= 0 {
    True -> concat_reversed(acc)
    False -> {
      let item = build_synthetic_witness_item(item_size)
      build_synthetic_witness_items_loop(remaining - 1, item_size, [item, ..acc])
    }
  }
}

fn build_synthetic_witness_item(item_size: Int) -> BitArray {
  let payload = <<0:size({ item_size * 8 })>>
  <<
    compact_size(item_size):bits,
    payload:bits,
  >>
}

fn synthetic_outpoint_txid_seed(
  index: Int,
  input_count: Int,
  outpoint_pattern: SyntheticOutPointPattern,
) -> Int {
  case outpoint_pattern {
    UniqueOutPoints -> index
    LastOutPointDuplicatesFirst ->
      case index == input_count - 1 {
        True -> 0
        False -> index
      }
  }
}

fn concat_reversed(parts: List(BitArray)) -> BitArray {
  parts
  |> list.reverse
  |> bit_array.concat
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
    warmup_ms: 250,
    duration_ms: 1000,
  )
}

/// Uses no batching for operation shapes that are slow enough on JavaScript
/// that batching would leave too few timed calls.
fn slow_synthetic_tx_measurement_config() -> PerfMeasurementConfig {
  measurement_config(1)
}

fn fast_measurement_config(
  operations_per_timed_call: Int,
) -> PerfMeasurementConfig {
  PerfMeasurementConfig(
    operations_per_timed_call:,
    warmup_ms: 100,
    duration_ms: 500,
  )
}

/// Uses larger batches for fast synthetic cases to reduce timer overhead.
fn small_synthetic_tx_measurement_config() -> PerfMeasurementConfig {
  measurement_config(100)
}

/// Uses moderate batching for middle points in operation shapes that become too
/// slow for larger batches.
fn medium_synthetic_tx_measurement_config() -> PerfMeasurementConfig {
  measurement_config(10)
}

/// Uses moderate batching for large synthetic cases that still record enough
/// timed calls on JavaScript.
fn large_synthetic_tx_measurement_config() -> PerfMeasurementConfig {
  measurement_config(10)
}
