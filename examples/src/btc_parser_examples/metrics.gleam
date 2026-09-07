//// Aggregate metrics built exclusively from btc_parser's public accessors.

import btc_parser/block
import btc_parser/transaction
import gleam/bit_array
import gleam/list

pub type OutputScriptCounts {
  OutputScriptCounts(
    p2pk: Int,
    p2pkh: Int,
    p2sh: Int,
    p2wpkh: Int,
    p2wsh: Int,
    p2tr: Int,
    bare_multisig: Int,
    null_data: Int,
    unknown_witness_program: Int,
    non_standard: Int,
  )
}

pub type TransactionMetrics {
  TransactionMetrics(
    version: Int,
    is_segwit: Bool,
    input_count: Int,
    output_count: Int,
    lock_time: Int,
    null_outpoint_input_count: Int,
    total_output_satoshis: Int,
    input_script_bytes: Int,
    output_script_bytes: Int,
    witness_stack_count: Int,
    non_empty_witness_stack_count: Int,
    witness_item_count: Int,
    witness_payload_bytes: Int,
    base_size_bytes: Int,
    total_size_bytes: Int,
    witness_size_bytes: Int,
    weight_units: Int,
    virtual_size_bytes: Int,
    output_scripts: OutputScriptCounts,
  )
}

pub type BlockMetrics {
  BlockMetrics(
    transaction_count: Int,
    legacy_transaction_count: Int,
    segwit_transaction_count: Int,
    input_count: Int,
    output_count: Int,
    null_outpoint_input_count: Int,
    total_output_satoshis: Int,
    input_script_bytes: Int,
    output_script_bytes: Int,
    witness_stack_count: Int,
    non_empty_witness_stack_count: Int,
    witness_item_count: Int,
    witness_payload_bytes: Int,
    base_size_bytes: Int,
    total_size_bytes: Int,
    witness_size_bytes: Int,
    weight_units: Int,
    virtual_size_bytes: Int,
    output_scripts: OutputScriptCounts,
  )
}

pub fn transaction_metrics(
  tx: transaction.Transaction(state),
) -> TransactionMetrics {
  let input_metrics = input_metrics(transaction.get_inputs(tx))
  let output_metrics = output_metrics(transaction.get_outputs(tx))
  let witness_metrics = witness_metrics(tx)
  let base_size_bytes = transaction.compute_base_size(tx)
  let total_size_bytes = transaction.compute_total_size(tx)
  let weight_units = transaction.compute_weight(tx)

  TransactionMetrics(
    version: transaction.get_version(tx),
    is_segwit: transaction.is_segwit(tx),
    input_count: transaction.get_input_count(tx),
    output_count: transaction.get_output_count(tx),
    lock_time: transaction.get_lock_time(tx),
    null_outpoint_input_count: input_metrics.null_outpoint_input_count,
    total_output_satoshis: output_metrics.total_output_satoshis,
    input_script_bytes: input_metrics.script_bytes,
    output_script_bytes: output_metrics.script_bytes,
    witness_stack_count: witness_metrics.stack_count,
    non_empty_witness_stack_count: witness_metrics.non_empty_stack_count,
    witness_item_count: witness_metrics.item_count,
    witness_payload_bytes: witness_metrics.payload_bytes,
    base_size_bytes:,
    total_size_bytes:,
    witness_size_bytes: total_size_bytes - base_size_bytes,
    weight_units:,
    virtual_size_bytes: virtual_size(weight_units),
    output_scripts: output_metrics.script_counts,
  )
}

pub fn block_metrics(block_value: block.Block(state)) -> BlockMetrics {
  let totals =
    block_value
    |> block.get_transactions
    |> list.fold(empty_block_totals(), fn(totals, tx) {
      add_transaction_metrics(totals, transaction_metrics(tx))
    })
  let base_size_bytes = block.compute_base_size(block_value)
  let total_size_bytes = block.compute_total_size(block_value)
  let weight_units = block.compute_weight(block_value)

  BlockMetrics(
    transaction_count: block.get_transaction_count(block_value),
    legacy_transaction_count: totals.legacy_transaction_count,
    segwit_transaction_count: totals.segwit_transaction_count,
    input_count: totals.input_count,
    output_count: totals.output_count,
    null_outpoint_input_count: totals.null_outpoint_input_count,
    total_output_satoshis: totals.total_output_satoshis,
    input_script_bytes: totals.input_script_bytes,
    output_script_bytes: totals.output_script_bytes,
    witness_stack_count: totals.stack_count,
    non_empty_witness_stack_count: totals.non_empty_stack_count,
    witness_item_count: totals.item_count,
    witness_payload_bytes: totals.payload_bytes,
    base_size_bytes:,
    total_size_bytes:,
    witness_size_bytes: total_size_bytes - base_size_bytes,
    weight_units:,
    virtual_size_bytes: virtual_size(weight_units),
    output_scripts: totals.output_scripts,
  )
}

type InputMetrics {
  InputMetrics(null_outpoint_input_count: Int, script_bytes: Int)
}

fn input_metrics(inputs: List(transaction.Input)) -> InputMetrics {
  list.fold(inputs, InputMetrics(0, 0), fn(metrics, input) {
    let script_bytes =
      input
      |> transaction.get_input_script_sig
      |> transaction.get_script_size

    InputMetrics(
      null_outpoint_input_count: metrics.null_outpoint_input_count
        + case transaction.input_has_null_outpoint(input) {
        True -> 1
        False -> 0
      },
      script_bytes: metrics.script_bytes + script_bytes,
    )
  })
}

type OutputMetrics {
  OutputMetrics(
    total_output_satoshis: Int,
    script_bytes: Int,
    script_counts: OutputScriptCounts,
  )
}

fn output_metrics(outputs: List(transaction.Output)) -> OutputMetrics {
  list.fold(
    outputs,
    OutputMetrics(0, 0, empty_output_script_counts()),
    fn(metrics, output) {
      let script = transaction.get_output_script_pubkey(output)

      OutputMetrics(
        total_output_satoshis: metrics.total_output_satoshis
          + transaction.get_output_value(output),
        script_bytes: metrics.script_bytes + transaction.get_script_size(script),
        script_counts: increment_script_count(
          metrics.script_counts,
          transaction.classify_output_script(script),
        ),
      )
    },
  )
}

type WitnessMetrics {
  WitnessMetrics(
    stack_count: Int,
    non_empty_stack_count: Int,
    item_count: Int,
    payload_bytes: Int,
  )
}

fn witness_metrics(tx: transaction.Transaction(state)) -> WitnessMetrics {
  case transaction.get_witnesses(tx) {
    Error(_) -> WitnessMetrics(0, 0, 0, 0)
    Ok(stacks) ->
      list.fold(stacks, WitnessMetrics(0, 0, 0, 0), fn(metrics, stack) {
        let items = transaction.get_witness_items(stack)
        let payload_bytes =
          list.fold(items, 0, fn(bytes, item) {
            let item_bytes =
              item
              |> transaction.get_witness_item_bytes
              |> bit_array.byte_size
            bytes + item_bytes
          })

        WitnessMetrics(
          stack_count: metrics.stack_count + 1,
          non_empty_stack_count: metrics.non_empty_stack_count
            + case transaction.is_witness_stack_empty(stack) {
            True -> 0
            False -> 1
          },
          item_count: metrics.item_count + list.length(items),
          payload_bytes: metrics.payload_bytes + payload_bytes,
        )
      })
  }
}

fn empty_output_script_counts() -> OutputScriptCounts {
  OutputScriptCounts(0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

fn increment_script_count(
  counts: OutputScriptCounts,
  script_type: transaction.OutputScriptType,
) -> OutputScriptCounts {
  case script_type {
    transaction.P2PK -> OutputScriptCounts(..counts, p2pk: counts.p2pk + 1)
    transaction.P2PKH -> OutputScriptCounts(..counts, p2pkh: counts.p2pkh + 1)
    transaction.P2SH -> OutputScriptCounts(..counts, p2sh: counts.p2sh + 1)
    transaction.P2WPKH ->
      OutputScriptCounts(..counts, p2wpkh: counts.p2wpkh + 1)
    transaction.P2WSH -> OutputScriptCounts(..counts, p2wsh: counts.p2wsh + 1)
    transaction.P2TR -> OutputScriptCounts(..counts, p2tr: counts.p2tr + 1)
    transaction.BareMultisig ->
      OutputScriptCounts(..counts, bare_multisig: counts.bare_multisig + 1)
    transaction.NullData ->
      OutputScriptCounts(..counts, null_data: counts.null_data + 1)
    transaction.UnknownWitnessProgram(_) ->
      OutputScriptCounts(
        ..counts,
        unknown_witness_program: counts.unknown_witness_program + 1,
      )
    transaction.NonStandard ->
      OutputScriptCounts(..counts, non_standard: counts.non_standard + 1)
  }
}

type BlockTotals {
  BlockTotals(
    legacy_transaction_count: Int,
    segwit_transaction_count: Int,
    input_count: Int,
    output_count: Int,
    null_outpoint_input_count: Int,
    total_output_satoshis: Int,
    input_script_bytes: Int,
    output_script_bytes: Int,
    stack_count: Int,
    non_empty_stack_count: Int,
    item_count: Int,
    payload_bytes: Int,
    output_scripts: OutputScriptCounts,
  )
}

fn empty_block_totals() -> BlockTotals {
  BlockTotals(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, empty_output_script_counts())
}

fn add_transaction_metrics(
  totals: BlockTotals,
  value: TransactionMetrics,
) -> BlockTotals {
  BlockTotals(
    legacy_transaction_count: totals.legacy_transaction_count
      + case value.is_segwit {
      True -> 0
      False -> 1
    },
    segwit_transaction_count: totals.segwit_transaction_count
      + case value.is_segwit {
      True -> 1
      False -> 0
    },
    input_count: totals.input_count + value.input_count,
    output_count: totals.output_count + value.output_count,
    null_outpoint_input_count: totals.null_outpoint_input_count
      + value.null_outpoint_input_count,
    total_output_satoshis: totals.total_output_satoshis
      + value.total_output_satoshis,
    input_script_bytes: totals.input_script_bytes + value.input_script_bytes,
    output_script_bytes: totals.output_script_bytes + value.output_script_bytes,
    stack_count: totals.stack_count + value.witness_stack_count,
    non_empty_stack_count: totals.non_empty_stack_count
      + value.non_empty_witness_stack_count,
    item_count: totals.item_count + value.witness_item_count,
    payload_bytes: totals.payload_bytes + value.witness_payload_bytes,
    output_scripts: add_output_script_counts(
      totals.output_scripts,
      value.output_scripts,
    ),
  )
}

fn add_output_script_counts(
  left: OutputScriptCounts,
  right: OutputScriptCounts,
) -> OutputScriptCounts {
  OutputScriptCounts(
    p2pk: left.p2pk + right.p2pk,
    p2pkh: left.p2pkh + right.p2pkh,
    p2sh: left.p2sh + right.p2sh,
    p2wpkh: left.p2wpkh + right.p2wpkh,
    p2wsh: left.p2wsh + right.p2wsh,
    p2tr: left.p2tr + right.p2tr,
    bare_multisig: left.bare_multisig + right.bare_multisig,
    null_data: left.null_data + right.null_data,
    unknown_witness_program: left.unknown_witness_program
      + right.unknown_witness_program,
    non_standard: left.non_standard + right.non_standard,
  )
}

fn virtual_size(weight_units: Int) -> Int {
  let rounded_weight_units = weight_units + 3
  rounded_weight_units / 4
}
