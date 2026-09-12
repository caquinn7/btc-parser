//// JSON encoders for metrics calculated by the examples project.

import btc_parser_examples/metrics
import gleam/json.{type Json}

pub fn block_metrics(value: metrics.BlockMetrics) -> Json {
  json.object([
    #("transaction_count", json.int(value.transaction_count)),
    #("legacy_transaction_count", json.int(value.legacy_transaction_count)),
    #("segwit_transaction_count", json.int(value.segwit_transaction_count)),
    #("input_count", json.int(value.input_count)),
    #("output_count", json.int(value.output_count)),
    #("null_outpoint_input_count", json.int(value.null_outpoint_input_count)),
    #("total_output_satoshis", json.int(value.total_output_satoshis)),
    #("input_script_bytes", json.int(value.input_script_bytes)),
    #("output_script_bytes", json.int(value.output_script_bytes)),
    #("witness_stack_count", json.int(value.witness_stack_count)),
    #(
      "non_empty_witness_stack_count",
      json.int(value.non_empty_witness_stack_count),
    ),
    #("witness_item_count", json.int(value.witness_item_count)),
    #("witness_payload_bytes", json.int(value.witness_payload_bytes)),
    #("base_size_bytes", json.int(value.base_size_bytes)),
    #("total_size_bytes", json.int(value.total_size_bytes)),
    #("witness_size_bytes", json.int(value.witness_size_bytes)),
    #("weight_units", json.int(value.weight_units)),
    #("virtual_size_bytes", json.int(value.virtual_size_bytes)),
    #("output_scripts", output_script_counts(value.output_scripts)),
  ])
}

fn output_script_counts(value: metrics.OutputScriptCounts) -> Json {
  json.object([
    #("p2pk", json.int(value.p2pk)),
    #("p2pkh", json.int(value.p2pkh)),
    #("p2sh", json.int(value.p2sh)),
    #("p2wpkh", json.int(value.p2wpkh)),
    #("p2wsh", json.int(value.p2wsh)),
    #("p2tr", json.int(value.p2tr)),
    #("p2a", json.int(value.p2a)),
    #("bare_multisig", json.int(value.bare_multisig)),
    #("null_data", json.int(value.null_data)),
    #("other_witness_program", json.int(value.other_witness_program)),
    #("non_standard", json.int(value.non_standard)),
  ])
}
