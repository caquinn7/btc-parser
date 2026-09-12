//// Deterministic metrics extractor for the transaction fuzz corpus.
////
//// Run from the repository root with:
////
////   ./fuzz/run -m btc_parser_fuzz/transaction/corpus_metrics
////
//// The tab-separated report contains one row per corpus record in source order.
//// Metrics and taxonomy codes are derived only through the public transaction API.

import btc_parser/transaction
import btc_parser_fuzz/internal/hash
import gleam/bit_array
import gleam/bool
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import simplifile

const corpus_path = "corpus/transaction/seed_txs.txt"

type CorpusRecord {
  CorpusRecord(txid: String, recorded_codes: String, bytes: BitArray)
}

type Serialization {
  LegacySerialization
  SegwitSerialization
}

type InputMetrics {
  InputMetrics(
    max_script_sig_length: Int,
    script_sig_252_count: Int,
    script_sig_253_count: Int,
    near_policy_script_sig_count: Int,
  )
}

type OutputMetrics {
  OutputMetrics(
    max_script_pubkey_length: Int,
    script_pubkey_252_count: Int,
    script_pubkey_253_count: Int,
    near_policy_script_pubkey_count: Int,
    p2pk_output_count: Int,
    p2pkh_output_count: Int,
    p2sh_output_count: Int,
    p2wpkh_output_count: Int,
    p2wsh_output_count: Int,
    p2tr_output_count: Int,
    p2a_output_count: Int,
    bare_multisig_output_count: Int,
    null_data_output_count: Int,
    other_witness_program_output_count: Int,
    nonstandard_output_count: Int,
    op_return_nonstandard_output_count: Int,
  )
}

type WitnessMetrics {
  WitnessMetrics(
    empty_stack_count: Int,
    nonempty_stack_count: Int,
    max_stack_item_count: Int,
    stack_252_count: Int,
    stack_253_count: Int,
    max_stack_payload_size: Int,
    zero_length_item_count: Int,
    item_252_count: Int,
    item_253_count: Int,
    item_65_535_count: Int,
    item_65_536_count: Int,
    max_item_length: Int,
  )
}

type Metrics {
  Metrics(
    txid: String,
    computed_txid: String,
    computed_wtxid: String,
    txid_matches: Bool,
    recorded_codes: String,
    derived_codes: List(String),
    serialization: Serialization,
    context_free_valid: Bool,
    coinbase_shape: Bool,
    version: Int,
    lock_time: Int,
    input_count: Int,
    output_count: Int,
    base_size: Int,
    total_size: Int,
    witness_size: Int,
    weight: Int,
    input_metrics: InputMetrics,
    output_metrics: OutputMetrics,
    witness_metrics: WitnessMetrics,
  )
}

/// Print one deterministic TSV row for every transaction corpus record.
pub fn main() -> Nil {
  let assert Ok(file_content) = simplifile.read(corpus_path)
  let records = parse_records(file_content)
  let metrics = list.map(records, measure)

  metrics
  |> render_report
  |> io.println
}

fn parse_records(file_content: String) -> List(CorpusRecord) {
  file_content
  |> string.split("\n")
  |> list.filter(fn(line) { !string.is_empty(string.trim(line)) })
  |> list.map(parse_record)
}

fn parse_record(line: String) -> CorpusRecord {
  case string.split(line, "|") {
    [txid, recorded_codes, hex] -> {
      let assert Ok(bytes) = bit_array.base16_decode(hex)
      CorpusRecord(txid:, recorded_codes:, bytes:)
    }
    _ -> panic as "transaction corpus record must have exactly three fields"
  }
}

fn measure(record: CorpusRecord) -> Metrics {
  let assert Ok(tx) = transaction.deserialize(record.bytes)
  assert transaction.serialize(tx) == record.bytes

  let serialization = case transaction.is_segwit(tx) {
    True -> SegwitSerialization
    False -> LegacySerialization
  }
  let input_count = transaction.get_input_count(tx)
  let output_count = transaction.get_output_count(tx)
  let base_size = transaction.compute_base_size(tx)
  let total_size = transaction.compute_total_size(tx)
  let witness_size = total_size - base_size
  let input_metrics = measure_inputs(transaction.get_inputs(tx))
  let output_metrics = measure_outputs(transaction.get_outputs(tx))
  let witness_metrics = measure_witnesses(tx)
  let coinbase_shape = has_coinbase_shape(tx)
  let context_free_valid = case
    transaction.validate_context_free_consensus(tx)
  {
    Ok(_) -> True
    Error(_) -> False
  }
  let computed_txid = hash.to_display_hex(transaction.compute_txid(tx))
  assert computed_txid == record.txid

  let metrics =
    Metrics(
      txid: record.txid,
      computed_txid:,
      computed_wtxid: hash.to_display_hex(transaction.compute_wtxid(tx)),
      txid_matches: computed_txid == record.txid,
      recorded_codes: record.recorded_codes,
      derived_codes: [],
      serialization:,
      context_free_valid:,
      coinbase_shape:,
      version: transaction.get_version(tx),
      lock_time: transaction.get_lock_time(tx),
      input_count:,
      output_count:,
      base_size:,
      total_size:,
      witness_size:,
      weight: transaction.compute_weight(tx),
      input_metrics:,
      output_metrics:,
      witness_metrics:,
    )

  let derived_codes = derive_codes(metrics)
  assert record.recorded_codes == string.join(derived_codes, with: ",")

  Metrics(..metrics, derived_codes:)
}

fn has_coinbase_shape(tx: transaction.Transaction(state)) -> Bool {
  case transaction.get_inputs(tx) {
    [input] -> {
      let script_sig_length =
        input
        |> transaction.get_input_script_sig
        |> transaction.get_script_size

      transaction.input_has_null_outpoint(input)
      && script_sig_length >= 2
      && script_sig_length <= 100
    }
    _ -> False
  }
}

fn measure_inputs(inputs: List(transaction.Input)) -> InputMetrics {
  list.fold(inputs, new_input_metrics(), fn(metrics, input) {
    let script_sig_length =
      input
      |> transaction.get_input_script_sig
      |> transaction.get_script_size

    InputMetrics(
      max_script_sig_length: int.max(
        metrics.max_script_sig_length,
        script_sig_length,
      ),
      script_sig_252_count: metrics.script_sig_252_count
        + bool_to_int(script_sig_length == 252),
      script_sig_253_count: metrics.script_sig_253_count
        + bool_to_int(script_sig_length == 253),
      near_policy_script_sig_count: metrics.near_policy_script_sig_count
        + bool_to_int(script_sig_length >= 9000 && script_sig_length <= 10_000),
    )
  })
}

fn new_input_metrics() -> InputMetrics {
  InputMetrics(0, 0, 0, 0)
}

fn measure_outputs(outputs: List(transaction.Output)) -> OutputMetrics {
  list.fold(outputs, new_output_metrics(), measure_output)
}

fn measure_output(
  metrics: OutputMetrics,
  output: transaction.Output,
) -> OutputMetrics {
  let script = transaction.get_output_script_pubkey(output)
  let script_length = transaction.get_script_size(script)
  let script_type = transaction.classify_output_script(script)
  let op_return_nonstandard = case
    transaction.get_raw_script_bytes(script),
    script_type
  {
    <<0x6A, _:bits>>, transaction.NonStandard -> True
    _, _ -> False
  }

  let metrics =
    OutputMetrics(
      ..metrics,
      max_script_pubkey_length: int.max(
        metrics.max_script_pubkey_length,
        script_length,
      ),
      script_pubkey_252_count: metrics.script_pubkey_252_count
        + bool_to_int(script_length == 252),
      script_pubkey_253_count: metrics.script_pubkey_253_count
        + bool_to_int(script_length == 253),
      near_policy_script_pubkey_count: metrics.near_policy_script_pubkey_count
        + bool_to_int(script_length >= 9000 && script_length <= 10_000),
      op_return_nonstandard_output_count: metrics.op_return_nonstandard_output_count
        + bool_to_int(op_return_nonstandard),
    )

  case script_type {
    transaction.P2PK ->
      OutputMetrics(..metrics, p2pk_output_count: metrics.p2pk_output_count + 1)
    transaction.P2PKH ->
      OutputMetrics(
        ..metrics,
        p2pkh_output_count: metrics.p2pkh_output_count + 1,
      )
    transaction.P2SH ->
      OutputMetrics(..metrics, p2sh_output_count: metrics.p2sh_output_count + 1)
    transaction.P2WPKH ->
      OutputMetrics(
        ..metrics,
        p2wpkh_output_count: metrics.p2wpkh_output_count + 1,
      )
    transaction.P2WSH ->
      OutputMetrics(
        ..metrics,
        p2wsh_output_count: metrics.p2wsh_output_count + 1,
      )
    transaction.P2TR ->
      OutputMetrics(..metrics, p2tr_output_count: metrics.p2tr_output_count + 1)
    transaction.P2A ->
      OutputMetrics(..metrics, p2a_output_count: metrics.p2a_output_count + 1)
    transaction.BareMultisig ->
      OutputMetrics(
        ..metrics,
        bare_multisig_output_count: metrics.bare_multisig_output_count + 1,
      )
    transaction.NullData ->
      OutputMetrics(
        ..metrics,
        null_data_output_count: metrics.null_data_output_count + 1,
      )
    transaction.OtherWitnessProgram(_) ->
      OutputMetrics(
        ..metrics,
        other_witness_program_output_count: metrics.other_witness_program_output_count
          + 1,
      )
    transaction.NonStandard ->
      OutputMetrics(
        ..metrics,
        nonstandard_output_count: metrics.nonstandard_output_count + 1,
      )
  }
}

fn new_output_metrics() -> OutputMetrics {
  OutputMetrics(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

fn measure_witnesses(tx: transaction.Transaction(state)) -> WitnessMetrics {
  case transaction.get_witnesses(tx) {
    Error(_) -> new_witness_metrics()
    Ok(stacks) -> list.fold(stacks, new_witness_metrics(), measure_stack)
  }
}

fn measure_stack(
  metrics: WitnessMetrics,
  stack: transaction.WitnessStack,
) -> WitnessMetrics {
  let items = transaction.get_witness_items(stack)
  let item_count = list.length(items)
  let payload_size =
    list.fold(items, 0, fn(size, item) {
      let item_length =
        item
        |> transaction.get_witness_item_bytes
        |> bit_array.byte_size

      size + item_length
    })
  let metrics =
    WitnessMetrics(
      ..metrics,
      empty_stack_count: metrics.empty_stack_count
        + bool_to_int(transaction.is_witness_stack_empty(stack)),
      nonempty_stack_count: metrics.nonempty_stack_count
        + bool_to_int(!transaction.is_witness_stack_empty(stack)),
      max_stack_item_count: int.max(metrics.max_stack_item_count, item_count),
      stack_252_count: metrics.stack_252_count + bool_to_int(item_count == 252),
      stack_253_count: metrics.stack_253_count + bool_to_int(item_count == 253),
      max_stack_payload_size: int.max(
        metrics.max_stack_payload_size,
        payload_size,
      ),
    )

  list.fold(items, metrics, measure_witness_item)
}

fn measure_witness_item(
  metrics: WitnessMetrics,
  item: transaction.WitnessItem,
) -> WitnessMetrics {
  let item_length =
    item
    |> transaction.get_witness_item_bytes
    |> bit_array.byte_size

  WitnessMetrics(
    ..metrics,
    zero_length_item_count: metrics.zero_length_item_count
      + bool_to_int(item_length == 0),
    item_252_count: metrics.item_252_count + bool_to_int(item_length == 252),
    item_253_count: metrics.item_253_count + bool_to_int(item_length == 253),
    item_65_535_count: metrics.item_65_535_count
      + bool_to_int(item_length == 65_535),
    item_65_536_count: metrics.item_65_536_count
      + bool_to_int(item_length == 65_536),
    max_item_length: int.max(metrics.max_item_length, item_length),
  )
}

fn new_witness_metrics() -> WitnessMetrics {
  WitnessMetrics(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

fn derive_codes(metrics: Metrics) -> List(String) {
  let input = metrics.input_metrics
  let output = metrics.output_metrics
  let witness = metrics.witness_metrics

  [
    #(metrics.serialization == LegacySerialization, "T01"),
    #(metrics.serialization == SegwitSerialization, "T02"),
    #(metrics.coinbase_shape, "T03"),
    #(metrics.input_count == 1, "I01"),
    #(metrics.input_count >= 200, "I02"),
    #(metrics.output_count == 1, "O01"),
    #(metrics.output_count >= 200, "O02"),
    #(witness.empty_stack_count > 0 && witness.nonempty_stack_count > 0, "W01"),
    #(witness.zero_length_item_count > 0, "W02"),
    #(witness.max_item_length >= 65_536, "W03"),
    #(witness.max_stack_item_count >= 253, "W04"),
    #(input.near_policy_script_sig_count > 0, "L01"),
    #(output.near_policy_script_pubkey_count > 0, "L02"),
    #(output.p2pk_output_count > 0, "F01"),
    #(output.p2pkh_output_count > 0, "F02"),
    #(output.p2sh_output_count > 0, "F03"),
    #(output.p2wpkh_output_count > 0, "F04"),
    #(output.p2wsh_output_count > 0, "F05"),
    #(output.p2tr_output_count > 0, "F06"),
    #(output.bare_multisig_output_count > 0, "F07"),
    #(output.null_data_output_count > 0, "F08"),
    #(output.other_witness_program_output_count > 0, "F09"),
    #(
      output.nonstandard_output_count
        > output.op_return_nonstandard_output_count,
      "F10",
    ),
    #(output.op_return_nonstandard_output_count > 0, "F11"),
    #(output.p2a_output_count > 0, "F12"),
    #(metrics.total_size >= 360_000 && metrics.total_size <= 400_000, "S01"),
  ]
  |> list.filter_map(fn(entry) {
    let #(included, code) = entry
    case included {
      True -> Ok(code)
      False -> Error(Nil)
    }
  })
}

fn render_report(metrics: List(Metrics)) -> String {
  [report_header(), ..list.map(metrics, render_row)]
  |> string.join(with: "\n")
}

fn report_header() -> String {
  [
    "txid",
    "computed_txid",
    "computed_wtxid",
    "txid_matches",
    "recorded_codes",
    "derived_codes",
    "serialization",
    "context_free_valid",
    "coinbase_shape",
    "version",
    "lock_time",
    "input_count",
    "input_count_width",
    "output_count",
    "output_count_width",
    "base_size",
    "total_size",
    "witness_size",
    "weight",
    "max_script_sig_length",
    "script_sig_252_count",
    "script_sig_253_count",
    "near_policy_script_sig_count",
    "max_script_pubkey_length",
    "script_pubkey_252_count",
    "script_pubkey_253_count",
    "near_policy_script_pubkey_count",
    "empty_witness_stack_count",
    "nonempty_witness_stack_count",
    "max_witness_stack_item_count",
    "witness_stack_252_count",
    "witness_stack_253_count",
    "max_witness_stack_payload_size",
    "zero_length_witness_item_count",
    "witness_item_252_count",
    "witness_item_253_count",
    "witness_item_65535_count",
    "witness_item_65536_count",
    "max_witness_item_length",
    "p2pk_output_count",
    "p2pkh_output_count",
    "p2sh_output_count",
    "p2wpkh_output_count",
    "p2wsh_output_count",
    "p2tr_output_count",
    "p2a_output_count",
    "bare_multisig_output_count",
    "null_data_output_count",
    "other_witness_program_output_count",
    "nonstandard_output_count",
    "op_return_nonstandard_output_count",
  ]
  |> string.join(with: "\t")
}

fn render_row(metrics: Metrics) -> String {
  let input = metrics.input_metrics
  let output = metrics.output_metrics
  let witness = metrics.witness_metrics

  [
    metrics.txid,
    metrics.computed_txid,
    metrics.computed_wtxid,
    bool_string(metrics.txid_matches),
    metrics.recorded_codes,
    string.join(metrics.derived_codes, with: ","),
    serialization_string(metrics.serialization),
    bool_string(metrics.context_free_valid),
    bool_string(metrics.coinbase_shape),
    int.to_string(metrics.version),
    int.to_string(metrics.lock_time),
    int.to_string(metrics.input_count),
    int.to_string(compact_size_width(metrics.input_count)),
    int.to_string(metrics.output_count),
    int.to_string(compact_size_width(metrics.output_count)),
    int.to_string(metrics.base_size),
    int.to_string(metrics.total_size),
    int.to_string(metrics.witness_size),
    int.to_string(metrics.weight),
    int.to_string(input.max_script_sig_length),
    int.to_string(input.script_sig_252_count),
    int.to_string(input.script_sig_253_count),
    int.to_string(input.near_policy_script_sig_count),
    int.to_string(output.max_script_pubkey_length),
    int.to_string(output.script_pubkey_252_count),
    int.to_string(output.script_pubkey_253_count),
    int.to_string(output.near_policy_script_pubkey_count),
    int.to_string(witness.empty_stack_count),
    int.to_string(witness.nonempty_stack_count),
    int.to_string(witness.max_stack_item_count),
    int.to_string(witness.stack_252_count),
    int.to_string(witness.stack_253_count),
    int.to_string(witness.max_stack_payload_size),
    int.to_string(witness.zero_length_item_count),
    int.to_string(witness.item_252_count),
    int.to_string(witness.item_253_count),
    int.to_string(witness.item_65_535_count),
    int.to_string(witness.item_65_536_count),
    int.to_string(witness.max_item_length),
    int.to_string(output.p2pk_output_count),
    int.to_string(output.p2pkh_output_count),
    int.to_string(output.p2sh_output_count),
    int.to_string(output.p2wpkh_output_count),
    int.to_string(output.p2wsh_output_count),
    int.to_string(output.p2tr_output_count),
    int.to_string(output.p2a_output_count),
    int.to_string(output.bare_multisig_output_count),
    int.to_string(output.null_data_output_count),
    int.to_string(output.other_witness_program_output_count),
    int.to_string(output.nonstandard_output_count),
    int.to_string(output.op_return_nonstandard_output_count),
  ]
  |> string.join(with: "\t")
}

fn compact_size_width(value: Int) -> Int {
  case value {
    v if v <= 252 -> 1
    v if v <= 65_535 -> 3
    v if v <= 4_294_967_295 -> 5
    _ -> 9
  }
}

fn serialization_string(serialization: Serialization) -> String {
  case serialization {
    LegacySerialization -> "legacy"
    SegwitSerialization -> "segwit"
  }
}

fn bool_string(value: Bool) -> String {
  value
  |> bool.to_string
  |> string.lowercase
}

fn bool_to_int(value: Bool) -> Int {
  case value {
    True -> 1
    False -> 0
  }
}
