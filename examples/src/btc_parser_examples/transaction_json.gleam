//// JSON-friendly structural transaction view.

import btc_parser/transaction
import btc_parser_examples/display
import gleam/bit_array
import gleam/int
import gleam/json.{type Json}
import gleam/list

/// Encode a parsed or context-free validated transaction as JSON.
pub fn encode(tx: transaction.Transaction(state)) -> Json {
  let witnesses = case transaction.get_witnesses(tx) {
    Ok(stacks) -> stacks
    Error(_) -> []
  }

  json.object([
    #("txid", json.string(display.hash(transaction.compute_txid(tx)))),
    #("wtxid", json.string(display.hash(transaction.compute_wtxid(tx)))),
    #("version", json.int(transaction.get_version(tx))),
    #("input_count", json.int(transaction.get_input_count(tx))),
    #("inputs", json.array(transaction.get_inputs(tx), input)),
    #("output_count", json.int(transaction.get_output_count(tx))),
    #("outputs", json.array(transaction.get_outputs(tx), output)),
    #("lock_time", json.int(transaction.get_lock_time(tx))),
    #("is_segwit", json.bool(transaction.is_segwit(tx))),
    #("witnesses", json.array(witnesses, witness_stack)),
  ])
}

fn input(value: transaction.Input) -> Json {
  let outpoint = transaction.get_input_outpoint(value)
  let script_sig = transaction.get_input_script_sig(value)

  json.object([
    #(
      "outpoint",
      json.object([
        #(
          "txid",
          json.string(display.hash(transaction.get_outpoint_txid(outpoint))),
        ),
        #("vout", json.int(transaction.get_outpoint_vout(outpoint))),
        #("is_null", json.bool(transaction.is_null_outpoint(outpoint))),
      ]),
    ),
    #("script_sig", script(script_sig)),
    #("sequence", json.int(transaction.get_input_sequence(value))),
  ])
}

fn output(value: transaction.Output) -> Json {
  let script_pubkey = transaction.get_output_script_pubkey(value)

  json.object([
    #("value_satoshis", json.int(transaction.get_output_value(value))),
    #(
      "script_pubkey",
      json.object([
        #("size", json.int(transaction.get_script_size(script_pubkey))),
        #(
          "hex",
          json.string(
            display.hex(transaction.get_raw_script_bytes(script_pubkey)),
          ),
        ),
        #(
          "classification",
          json.string(
            classification(transaction.classify_output_script(script_pubkey)),
          ),
        ),
      ]),
    ),
  ])
}

fn script(value: transaction.ScriptBytes(kind)) -> Json {
  let bytes = transaction.get_raw_script_bytes(value)

  json.object([
    #("size", json.int(bit_array.byte_size(bytes))),
    #("hex", json.string(display.hex(bytes))),
  ])
}

fn witness_stack(value: transaction.WitnessStack) -> Json {
  let items = transaction.get_witness_items(value)

  json.object([
    #("item_count", json.int(list.length(items))),
    #("items", json.array(items, witness_item)),
  ])
}

fn witness_item(value: transaction.WitnessItem) -> Json {
  let bytes = transaction.get_witness_item_bytes(value)

  json.object([
    #("size", json.int(bit_array.byte_size(bytes))),
    #("hex", json.string(display.hex(bytes))),
  ])
}

fn classification(value: transaction.OutputScriptType) -> String {
  case value {
    transaction.P2PK -> "p2pk"
    transaction.P2PKH -> "p2pkh"
    transaction.P2SH -> "p2sh"
    transaction.P2WPKH -> "p2wpkh"
    transaction.P2WSH -> "p2wsh"
    transaction.P2TR -> "p2tr"
    transaction.BareMultisig -> "bare_multisig"
    transaction.NullData -> "null_data"
    transaction.UnknownWitnessProgram(version) ->
      "unknown_witness_program_v" <> int.to_string(version)
    transaction.NonStandard -> "non_standard"
  }
}
