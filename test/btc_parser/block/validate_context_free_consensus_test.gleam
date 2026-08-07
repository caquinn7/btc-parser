import btc_parser/block.{
  type PowLimit, BaseSizeLimitExceeded, ImpossiblyLargeTransactionCount,
  InvalidProofOfWork, InvalidTransaction, LegacySigOpLimitExceeded,
  MerkleRootMismatch, MissingCoinbase, MutatedMerkleTree, NoTransactions,
  UnexpectedCoinbase, WeightLimitExceeded,
}
import btc_parser/transaction.{
  CoinbaseWithMultipleInputs, InvalidCoinbaseScriptSigLength, NoInputs,
  NoOutputs,
}
import gleam/bit_array
import gleam/crypto.{Sha256}
import gleam/int
import gleam/list
import support/bitcoin_wire.{compact_size}
import support/transaction_wire.{
  assemble_segwit_transaction_bytes, build_input_bytes, build_output_bytes,
  repeat_byte,
}

const regtest_pow_limit_bytes = <<
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0x7F,
>>

const mainnet_pow_limit_bytes = <<
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0x00,
  0x00,
  0x00,
  0x00,
>>

const regtest_compact_target = 0x207FFFFF

// `regtest_compact_target` expands to 29 low-order zero bytes followed by its
// three-byte coefficient in little-endian order.
const regtest_compact_target_bytes = <<0:size(232), 0xFF, 0xFF, 0x7F>>

fn regtest_pow_limit() -> PowLimit {
  let assert Ok(pow_limit) = block.new_pow_limit(regtest_pow_limit_bytes)
  pow_limit
}

fn mainnet_pow_limit() -> PowLimit {
  let assert Ok(pow_limit) = block.new_pow_limit(mainnet_pow_limit_bytes)
  pow_limit
}

// ============================================================================
// Proof of work
// ============================================================================

pub fn validate_context_free_consensus_rejects_negative_pow_target_test() {
  let block_bytes =
    assemble_block_bytes_with_compact_target(
      [build_valid_coinbase_legacy_transaction_bytes(1)],
      0x20800001,
    )
  let assert Ok(parsed_block) = block.deserialize(block_bytes)

  assert block.validate_context_free_consensus(
      parsed_block,
      regtest_pow_limit(),
    )
    == Error([InvalidProofOfWork])
}

pub fn validate_context_free_consensus_rejects_zero_pow_target_before_block_size_checks_test() {
  let block_bytes = assemble_block_bytes_with_compact_target([], 0)
  let assert Ok(parsed_block) = block.deserialize(block_bytes)

  assert block.validate_context_free_consensus(
      parsed_block,
      regtest_pow_limit(),
    )
    == Error([InvalidProofOfWork])
}

pub fn validate_context_free_consensus_rejects_overflowing_pow_target_test() {
  let block_bytes =
    assemble_block_bytes_with_compact_target(
      [build_valid_coinbase_legacy_transaction_bytes(1)],
      0x23010000,
    )
  let assert Ok(parsed_block) = block.deserialize(block_bytes)

  assert block.validate_context_free_consensus(
      parsed_block,
      regtest_pow_limit(),
    )
    == Error([InvalidProofOfWork])
}

pub fn validate_context_free_consensus_rejects_pow_target_above_supplied_limit_test() {
  let block_bytes =
    assemble_block_bytes_with_compact_target(
      [build_valid_coinbase_legacy_transaction_bytes(1)],
      regtest_compact_target,
    )
  let assert Ok(parsed_block) = block.deserialize(block_bytes)

  assert block.validate_context_free_consensus(
      parsed_block,
      mainnet_pow_limit(),
    )
    == Error([InvalidProofOfWork])
}

pub fn validate_context_free_consensus_accepts_pow_target_equal_to_supplied_limit_test() {
  let block_bytes =
    assemble_block_bytes([build_valid_coinbase_legacy_transaction_bytes(1)])
  let assert Ok(parsed_block) = block.deserialize(block_bytes)
  let assert Ok(pow_limit) = block.new_pow_limit(regtest_compact_target_bytes)

  assert parsed_block
    |> block.get_header
    |> block.get_header_target
    == regtest_compact_target

  let assert Ok(_) =
    block.validate_context_free_consensus(parsed_block, pow_limit)
}

pub fn validate_context_free_consensus_rejects_header_hash_above_pow_target_test() {
  let block_bytes =
    assemble_block_bytes_with_compact_target(
      [build_valid_coinbase_legacy_transaction_bytes(1)],
      0x03000001,
    )
  let assert Ok(parsed_block) = block.deserialize(block_bytes)
  let block_hash = block.compute_block_hash(parsed_block)

  assert block_hash != <<0:256>>
  assert block_hash != <<1, 0:size(248)>>
  assert block.validate_context_free_consensus(
      parsed_block,
      mainnet_pow_limit(),
    )
    == Error([InvalidProofOfWork])
}

// ============================================================================
// Block size-limit guards
// ============================================================================

pub fn validate_context_free_consensus_rejects_empty_block_test() {
  let block_bytes = assemble_block_bytes([])
  let assert Ok(parsed_block) =
    deserialize_with_limits(block_bytes, bit_array.byte_size(block_bytes), 0)

  assert block.validate_context_free_consensus(
      parsed_block,
      regtest_pow_limit(),
    )
    == Error([
      NoTransactions,
    ])
}

pub fn validate_context_free_consensus_rejects_impossibly_large_transaction_count_test() {
  let tx_count = 1_000_001
  let tx_bytes = build_invalid_legacy_transaction_bytes(0)
  let tx_payload = bit_array.concat(list.repeat(tx_bytes, tx_count))
  let block_bytes =
    assemble_block_from_transaction_payload_bytes(
      tx_count,
      <<0:256>>,
      tx_payload,
    )

  assert bit_array.byte_size(tx_bytes) == 10
  assert bit_array.byte_size(tx_payload) == 10_000_010
  let assert Ok(parsed_block) =
    deserialize_with_limits(
      block_bytes,
      bit_array.byte_size(block_bytes),
      tx_count,
    )

  assert block.validate_context_free_consensus(
      parsed_block,
      regtest_pow_limit(),
    )
    == Error([
      ImpossiblyLargeTransactionCount,
    ])
}

pub fn validate_context_free_consensus_accepts_block_at_base_size_and_weight_limits_test() {
  let block_bytes = build_base_size_boundary_block_bytes(17)

  assert bit_array.byte_size(block_bytes) == 1_000_000
  let assert Ok(parsed_block) =
    deserialize_with_limits(
      block_bytes,
      bit_array.byte_size(block_bytes),
      16_665,
    )

  assert block.compute_base_size(parsed_block) == 1_000_000
  assert block.compute_weight(parsed_block) == 4_000_000
  let assert Ok(_) =
    block.validate_context_free_consensus(parsed_block, regtest_pow_limit())
}

pub fn validate_context_free_consensus_prioritizes_base_size_over_weight_limit_test() {
  let block_bytes = build_base_size_boundary_block_bytes(18)

  assert bit_array.byte_size(block_bytes) == 1_000_001
  let assert Ok(parsed_block) =
    deserialize_with_limits(
      block_bytes,
      bit_array.byte_size(block_bytes),
      16_665,
    )

  assert block.compute_base_size(parsed_block) == 1_000_001
  assert block.compute_weight(parsed_block) == 4_000_004
  assert block.validate_context_free_consensus(
      parsed_block,
      regtest_pow_limit(),
    )
    == Error([
      BaseSizeLimitExceeded(1_000_001),
    ])
}

pub fn validate_context_free_consensus_rejects_block_over_weight_limit_and_below_base_size_limit_test() {
  let witness_item_size = 3_999_429
  let witness_item = <<0:size({ witness_item_size * 8 })>>
  let input = build_input_bytes(<<1, 0:size(248)>>, 0, <<>>, 0)
  let output = build_output_bytes(<<0:little-size(64)>>, <<>>)
  let witness_stack = <<
    compact_size(1):bits,
    compact_size(witness_item_size):bits,
    witness_item:bits,
  >>
  let tx = assemble_segwit_transaction_bytes([input], [output], [witness_stack])
  let block_bytes =
    assemble_block_from_transaction_payload_bytes(1, <<0:256>>, tx)

  let assert Ok(parsed_block) =
    deserialize_with_limits(block_bytes, bit_array.byte_size(block_bytes), 1)

  assert block.compute_base_size(parsed_block) == 141
  assert block.compute_total_size(parsed_block) == 3_999_578
  assert block.compute_weight(parsed_block) == 4_000_001
  assert block.validate_context_free_consensus(
      parsed_block,
      regtest_pow_limit(),
    )
    == Error([
      WeightLimitExceeded(4_000_001),
    ])
}

// ============================================================================
// Merkle-root validation
// ============================================================================

pub fn validate_context_free_consensus_rejects_mismatched_merkle_root_test() {
  let txs = [
    build_valid_coinbase_legacy_transaction_bytes(1),
    build_valid_legacy_transaction_bytes(2, <<>>),
  ]
  let header_merkle_root = <<0:256>>
  let computed_merkle_root = compute_transaction_merkle_root(txs)
  let block_bytes =
    assemble_block_bytes_with_merkle_root(txs, header_merkle_root)

  assert header_merkle_root != computed_merkle_root
  let assert Ok(parsed_block) =
    deserialize_with_limits(block_bytes, bit_array.byte_size(block_bytes), 2)

  assert block.validate_context_free_consensus(
      parsed_block,
      regtest_pow_limit(),
    )
    == Error([
      MerkleRootMismatch(
        actual: header_merkle_root,
        expected: computed_merkle_root,
      ),
    ])
}

pub fn validate_context_free_consensus_rejects_mutated_merkle_tree_test() {
  let txs = build_mutated_transactions()
  let block_bytes = assemble_block_bytes(txs)

  let assert Ok(parsed_block) =
    deserialize_with_limits(block_bytes, bit_array.byte_size(block_bytes), 4)

  assert block.validate_context_free_consensus(
      parsed_block,
      regtest_pow_limit(),
    )
    == Error([
      MutatedMerkleTree,
    ])
}

pub fn validate_context_free_consensus_prioritizes_merkle_root_mismatch_over_mutated_tree_test() {
  let txs = build_mutated_transactions()
  let header_merkle_root = <<0:256>>
  let computed_merkle_root = compute_transaction_merkle_root(txs)
  let block_bytes =
    assemble_block_bytes_with_merkle_root(txs, header_merkle_root)

  assert header_merkle_root != computed_merkle_root
  let assert Ok(parsed_block) =
    deserialize_with_limits(block_bytes, bit_array.byte_size(block_bytes), 4)

  assert block.validate_context_free_consensus(
      parsed_block,
      regtest_pow_limit(),
    )
    == Error([
      MerkleRootMismatch(
        actual: header_merkle_root,
        expected: computed_merkle_root,
      ),
    ])
}

// ============================================================================
// Coinbase placement
// ============================================================================

pub fn validate_context_free_consensus_accepts_coinbase_at_first_and_only_position_test() {
  let txs = [
    build_valid_coinbase_legacy_transaction_bytes(1),
    build_valid_legacy_transaction_bytes(2, <<>>),
    build_valid_legacy_transaction_bytes(3, <<>>),
  ]
  let block_bytes = assemble_block_bytes(txs)

  let assert Ok(parsed_block) =
    deserialize_with_limits(block_bytes, bit_array.byte_size(block_bytes), 3)

  let assert Ok(_) =
    block.validate_context_free_consensus(parsed_block, regtest_pow_limit())
}

pub fn validate_context_free_consensus_rejects_block_without_coinbase_test() {
  let txs = [
    build_valid_legacy_transaction_bytes(1, <<>>),
    build_valid_legacy_transaction_bytes(2, <<>>),
  ]
  let block_bytes = assemble_block_bytes(txs)

  let assert Ok(parsed_block) =
    deserialize_with_limits(block_bytes, bit_array.byte_size(block_bytes), 2)

  assert block.validate_context_free_consensus(
      parsed_block,
      regtest_pow_limit(),
    )
    == Error([
      MissingCoinbase,
    ])
}

pub fn validate_context_free_consensus_prioritizes_missing_first_coinbase_over_later_coinbase_test() {
  let txs = [
    build_valid_legacy_transaction_bytes(1, <<>>),
    build_valid_coinbase_legacy_transaction_bytes(2),
  ]
  let block_bytes = assemble_block_bytes(txs)

  let assert Ok(parsed_block) =
    deserialize_with_limits(block_bytes, bit_array.byte_size(block_bytes), 2)

  assert block.validate_context_free_consensus(
      parsed_block,
      regtest_pow_limit(),
    )
    == Error([
      MissingCoinbase,
    ])
}

pub fn validate_context_free_consensus_rejects_additional_coinbase_at_its_wire_index_test() {
  let txs = [
    build_valid_coinbase_legacy_transaction_bytes(1),
    build_valid_legacy_transaction_bytes(2, <<>>),
    build_valid_coinbase_legacy_transaction_bytes(3),
  ]
  let block_bytes = assemble_block_bytes(txs)

  let assert Ok(parsed_block) =
    deserialize_with_limits(block_bytes, bit_array.byte_size(block_bytes), 3)

  assert block.validate_context_free_consensus(
      parsed_block,
      regtest_pow_limit(),
    )
    == Error([
      UnexpectedCoinbase(2),
    ])
}

pub fn validate_context_free_consensus_reports_first_of_multiple_additional_coinbases_test() {
  let txs = [
    build_valid_coinbase_legacy_transaction_bytes(1),
    build_valid_legacy_transaction_bytes(2, <<>>),
    build_valid_coinbase_legacy_transaction_bytes(3),
    build_valid_coinbase_legacy_transaction_bytes(4),
  ]
  let block_bytes = assemble_block_bytes(txs)

  let assert Ok(parsed_block) =
    deserialize_with_limits(block_bytes, bit_array.byte_size(block_bytes), 4)

  assert block.validate_context_free_consensus(
      parsed_block,
      regtest_pow_limit(),
    )
    == Error([
      UnexpectedCoinbase(2),
    ])
}

pub fn validate_context_free_consensus_does_not_treat_multi_input_null_outpoint_tx_as_coinbase_test() {
  let invalid_tx =
    build_invalid_coinbase_with_multiple_inputs_transaction_bytes(2)
  let txs = [
    build_valid_coinbase_legacy_transaction_bytes(1),
    invalid_tx,
  ]
  let block_bytes = assemble_block_bytes(txs)

  let assert Ok(parsed_block) =
    deserialize_with_limits(block_bytes, bit_array.byte_size(block_bytes), 2)

  assert block.validate_context_free_consensus(
      parsed_block,
      regtest_pow_limit(),
    )
    == Error([
      InvalidTransaction(1, [CoinbaseWithMultipleInputs]),
    ])
}

pub fn validate_context_free_consensus_counts_invalid_coinbase_scriptsig_as_first_coinbase_test() {
  let invalid_coinbase =
    build_coinbase_legacy_transaction_bytes(1, <<0x01>>, <<>>)
  let txs = [
    invalid_coinbase,
    build_valid_legacy_transaction_bytes(2, <<>>),
  ]
  let block_bytes = assemble_block_bytes(txs)

  let assert Ok(parsed_block) =
    deserialize_with_limits(block_bytes, bit_array.byte_size(block_bytes), 2)

  assert block.validate_context_free_consensus(
      parsed_block,
      regtest_pow_limit(),
    )
    == Error([
      InvalidTransaction(0, [InvalidCoinbaseScriptSigLength]),
    ])
}

// ============================================================================
// Legacy signature-operation limit
// ============================================================================

pub fn validate_context_free_consensus_accepts_twenty_thousand_legacy_sigops_test() {
  let txs = build_legacy_sigop_boundary_transactions(0)
  let block_bytes = assemble_block_bytes(txs)

  let assert Ok(parsed_block) =
    deserialize_with_limits(block_bytes, bit_array.byte_size(block_bytes), 2)

  assert block.compute_base_size(parsed_block) < 1_000_000
  assert block.compute_weight(parsed_block) < 4_000_000
  let assert Ok(_) =
    block.validate_context_free_consensus(parsed_block, regtest_pow_limit())
}

pub fn validate_context_free_consensus_rejects_twenty_thousand_and_one_legacy_sigops_test() {
  let txs = build_legacy_sigop_boundary_transactions(1)
  let block_bytes = assemble_block_bytes(txs)

  let assert Ok(parsed_block) =
    deserialize_with_limits(block_bytes, bit_array.byte_size(block_bytes), 2)

  assert block.validate_context_free_consensus(
      parsed_block,
      regtest_pow_limit(),
    )
    == Error([
      LegacySigOpLimitExceeded(20_001),
    ])
}

pub fn validate_context_free_consensus_ignores_sigops_in_witness_data_test() {
  let witness_item = repeat_byte(0xAC, 20_001)
  let witness_stack = <<
    compact_size(1):bits,
    compact_size(bit_array.byte_size(witness_item)):bits,
    witness_item:bits,
  >>
  let segwit_tx =
    assemble_segwit_transaction_bytes(
      [build_input_bytes(repeat_byte(1, 32), 0, <<>>, 0)],
      [build_output_bytes(<<0:little-size(64)>>, <<>>)],
      [witness_stack],
    )
  let block_bytes =
    assemble_block_bytes([
      build_valid_coinbase_legacy_transaction_bytes(1),
      segwit_tx,
    ])

  let assert Ok(parsed_block) =
    deserialize_with_limits(block_bytes, bit_array.byte_size(block_bytes), 2)

  let assert Ok(_) =
    block.validate_context_free_consensus(parsed_block, regtest_pow_limit())
}

pub fn validate_context_free_consensus_collects_all_violations_in_validation_order_test() {
  let ten_thousand_sigops = repeat_byte(0xAC, 10_000)
  let invalid_tx = build_invalid_legacy_transaction_bytes(3)
  let txs = [
    build_valid_legacy_transaction_bytes(1, ten_thousand_sigops),
    build_legacy_transaction_bytes(2, <<0xAC>>, ten_thousand_sigops),
    invalid_tx,
  ]
  let header_merkle_root = <<0:256>>
  let computed_merkle_root = compute_transaction_merkle_root(txs)
  let block_bytes =
    assemble_block_bytes_with_merkle_root(txs, header_merkle_root)

  assert header_merkle_root != computed_merkle_root
  let assert Ok(parsed_block) =
    deserialize_with_limits(block_bytes, bit_array.byte_size(block_bytes), 3)

  assert block.validate_context_free_consensus(
      parsed_block,
      regtest_pow_limit(),
    )
    == Error([
      MerkleRootMismatch(
        actual: header_merkle_root,
        expected: computed_merkle_root,
      ),
      MissingCoinbase,
      LegacySigOpLimitExceeded(20_001),
      InvalidTransaction(2, [NoInputs, NoOutputs]),
    ])
}

// ============================================================================
// Contained transaction validation
// ============================================================================

pub fn validate_context_free_consensus_collects_transaction_violations_in_wire_order_test() {
  let invalid_first = build_invalid_legacy_transaction_bytes(1)
  let valid_middle = build_valid_legacy_transaction_bytes(2, <<>>)
  let invalid_last = build_invalid_legacy_transaction_bytes(3)
  let block_bytes =
    assemble_block_bytes([
      build_valid_coinbase_legacy_transaction_bytes(0),
      invalid_first,
      valid_middle,
      invalid_last,
    ])

  let assert Ok(parsed_block) =
    deserialize_with_limits(block_bytes, bit_array.byte_size(block_bytes), 4)

  assert block.validate_context_free_consensus(
      parsed_block,
      regtest_pow_limit(),
    )
    == Error([
      InvalidTransaction(1, [NoInputs, NoOutputs]),
      InvalidTransaction(3, [NoInputs, NoOutputs]),
    ])
}

pub fn validate_context_free_consensus_collects_merkle_root_mismatch_before_transaction_violations_test() {
  let coinbase = build_valid_coinbase_legacy_transaction_bytes(1)
  let invalid_tx = build_invalid_legacy_transaction_bytes(2)
  let txs = [coinbase, invalid_tx]
  let header_merkle_root = <<0:256>>
  let computed_merkle_root = compute_transaction_merkle_root(txs)
  let block_bytes =
    assemble_block_bytes_with_merkle_root(txs, header_merkle_root)

  assert header_merkle_root != computed_merkle_root
  let assert Ok(parsed_block) =
    deserialize_with_limits(block_bytes, bit_array.byte_size(block_bytes), 2)

  assert block.validate_context_free_consensus(
      parsed_block,
      regtest_pow_limit(),
    )
    == Error([
      MerkleRootMismatch(
        actual: header_merkle_root,
        expected: computed_merkle_root,
      ),
      InvalidTransaction(1, [NoInputs, NoOutputs]),
    ])
}

// ============================================================================
// Validated-state upgrade
// ============================================================================

pub fn validate_context_free_consensus_upgrades_valid_transactions_and_preserves_wire_order_test() {
  let coinbase_tx = build_valid_coinbase_legacy_transaction_bytes(1)
  let regular_tx = build_valid_legacy_transaction_bytes(2, <<>>)
  let block_bytes = assemble_block_bytes([coinbase_tx, regular_tx])

  let assert Ok(parsed_block) =
    deserialize_with_limits(block_bytes, bit_array.byte_size(block_bytes), 2)
  let assert Ok(validated_block) =
    block.validate_context_free_consensus(parsed_block, regtest_pow_limit())
  let assert [validated_coinbase, validated_regular] =
    block.get_transactions(validated_block)

  assert block.get_transaction_count(validated_block) == 2
  assert transaction.get_version(validated_coinbase) == 1
  assert transaction.get_version(validated_regular) == 2
  assert transaction.serialize(validated_coinbase) == coinbase_tx
  assert transaction.serialize(validated_regular) == regular_tx
  assert block.serialize(validated_block) == block_bytes

  // This requires Transaction(ContextFreeValidated), so it also demonstrates
  // that the block upgrade carries through to its contained transactions.
  assert transaction.has_coinbase_shape(validated_coinbase)
  assert !transaction.has_coinbase_shape(validated_regular)
}

// ============================================================================
// Helpers
// ============================================================================

fn build_block_header_bytes(merkle_root: BitArray) -> BitArray {
  build_mined_regtest_header_bytes(merkle_root, 0)
}

fn build_mined_regtest_header_bytes(
  merkle_root: BitArray,
  nonce: Int,
) -> BitArray {
  let header =
    build_block_header_bytes_with_compact_target(
      merkle_root,
      regtest_compact_target,
      nonce,
    )
  let header_hash = dsha256(header)
  let assert <<_:bytes-size(31), most_significant_byte>> = header_hash

  case most_significant_byte < 0x7F {
    True -> header
    False -> build_mined_regtest_header_bytes(merkle_root, nonce + 1)
  }
}

fn build_block_header_bytes_with_compact_target(
  merkle_root: BitArray,
  compact_target: Int,
  nonce: Int,
) -> BitArray {
  let assert <<_:256-bits>> = merkle_root
  <<
    0:little-size(32),
    0:size(256),
    merkle_root:bits,
    0:little-size(32),
    compact_target:little-size(32),
    nonce:little-size(32),
  >>
}

fn assemble_block_bytes_with_compact_target(
  transactions: List(BitArray),
  compact_target: Int,
) -> BitArray {
  let merkle_root = compute_transaction_merkle_root(transactions)

  <<
    build_block_header_bytes_with_compact_target(merkle_root, compact_target, 0):bits,
    compact_size(list.length(transactions)):bits,
    bit_array.concat(transactions):bits,
  >>
}

fn assemble_block_bytes(transactions: List(BitArray)) -> BitArray {
  let merkle_root = compute_transaction_merkle_root(transactions)

  assemble_block_bytes_with_merkle_root(transactions, merkle_root)
}

fn assemble_block_bytes_with_merkle_root(
  transactions: List(BitArray),
  merkle_root: BitArray,
) -> BitArray {
  assemble_block_from_transaction_payload_bytes(
    list.length(transactions),
    merkle_root,
    bit_array.concat(transactions),
  )
}

fn build_mutated_transactions() -> List(BitArray) {
  let coinbase = build_valid_coinbase_legacy_transaction_bytes(1)
  let tx_a = build_valid_legacy_transaction_bytes(2, <<>>)
  let tx_b = build_valid_legacy_transaction_bytes(3, <<>>)

  [coinbase, tx_a, tx_b, tx_b]
}

fn assemble_block_from_transaction_payload_bytes(
  transaction_count: Int,
  merkle_root: BitArray,
  transaction_payload: BitArray,
) -> BitArray {
  <<
    build_block_header_bytes(merkle_root):bits,
    compact_size(transaction_count):bits,
    transaction_payload:bits,
  >>
}

fn compute_transaction_merkle_root(transactions: List(BitArray)) -> BitArray {
  transactions
  |> list.map(fn(bytes) {
    let assert Ok(tx) = transaction.deserialize(bytes)
    transaction.compute_txid(tx)
  })
  |> compute_merkle_root_from_hashes
}

fn compute_merkle_root_from_hashes(hashes: List(BitArray)) -> BitArray {
  case hashes {
    [] -> <<0:256>>
    [hash] -> hash
    _ ->
      hashes
      |> list.sized_chunk(2)
      |> list.map(fn(pair) {
        case pair {
          [left, right] -> dsha256(bit_array.append(left, right))
          [hash] -> dsha256(bit_array.append(hash, hash))
          _ -> panic as "expected one or two hashes"
        }
      })
      |> compute_merkle_root_from_hashes
  }
}

fn dsha256(bytes: BitArray) -> BitArray {
  bytes
  |> crypto.hash(Sha256, _)
  |> crypto.hash(Sha256, _)
}

fn build_valid_legacy_transaction_bytes(
  version: Int,
  output_script: BitArray,
) -> BitArray {
  build_legacy_transaction_bytes(version, <<>>, output_script)
}

fn build_legacy_transaction_bytes(
  version: Int,
  script_sig: BitArray,
  script_pubkey: BitArray,
) -> BitArray {
  let input = build_input_bytes(<<1, 0:size(248)>>, 0, script_sig, 0)
  let output = build_output_bytes(<<0:little-size(64)>>, script_pubkey)

  <<
    version:little-size(32),
    compact_size(1):bits,
    input:bits,
    compact_size(1):bits,
    output:bits,
    0:little-size(32),
  >>
}

fn build_valid_coinbase_legacy_transaction_bytes(version: Int) -> BitArray {
  build_coinbase_legacy_transaction_bytes(version, <<0, 1>>, <<>>)
}

fn build_coinbase_legacy_transaction_bytes(
  version: Int,
  script_sig: BitArray,
  script_pubkey: BitArray,
) -> BitArray {
  let input = build_input_bytes(<<0:size(256)>>, 0xFFFFFFFF, script_sig, 0)
  let output = build_output_bytes(<<0:little-size(64)>>, script_pubkey)

  <<
    version:little-size(32),
    compact_size(1):bits,
    input:bits,
    compact_size(1):bits,
    output:bits,
    0:little-size(32),
  >>
}

fn build_legacy_sigop_boundary_transactions(
  extra_sigops: Int,
) -> List(BitArray) {
  let ten_thousand_sigops = repeat_byte(0xAC, 10_000)

  [
    build_coinbase_legacy_transaction_bytes(1, <<0, 1>>, ten_thousand_sigops),
    build_legacy_transaction_bytes(
      2,
      repeat_byte(0xAC, extra_sigops),
      ten_thousand_sigops,
    ),
  ]
}

fn build_invalid_coinbase_with_multiple_inputs_transaction_bytes(
  version: Int,
) -> BitArray {
  let coinbase_input =
    build_input_bytes(<<0:size(256)>>, 0xFFFFFFFF, <<0, 1>>, 0)
  let regular_input = build_input_bytes(<<1, 0:size(248)>>, 0, <<>>, 0)
  let output = build_output_bytes(<<0:little-size(64)>>, <<>>)

  <<
    version:little-size(32),
    compact_size(2):bits,
    coinbase_input:bits,
    regular_input:bits,
    compact_size(1):bits,
    output:bits,
    0:little-size(32),
  >>
}

fn build_invalid_legacy_transaction_bytes(version: Int) -> BitArray {
  <<version:little-size(32), 0, 0, 0:little-size(32)>>
}

fn build_base_size_boundary_block_bytes(
  output_script_padding: Int,
) -> BitArray {
  let tx_count = 16_665

  let coinbase_tx = build_valid_coinbase_legacy_transaction_bytes(0)

  // The coinbase is two bytes larger than a minimal regular transaction, so
  // reduce the existing output-script padding by two to preserve the boundary.
  let adjusted_output_script_padding = output_script_padding - 2
  let padded_tx =
    build_valid_legacy_transaction_bytes(1, <<
      0:size({ adjusted_output_script_padding * 8 }),
    >>)

  // Distinct versions preserve the fixed transaction size while producing
  // distinct txids, avoiding equal Merkle-tree siblings and mutation errors.
  let normal_txs =
    int.range(tx_count - 1, 1, [], fn(txs, version) {
      [build_valid_legacy_transaction_bytes(version, <<>>), ..txs]
    })

  let txs = [coinbase_tx, padded_tx, ..normal_txs]
  assemble_block_bytes(txs)
}

fn deserialize_with_limits(
  bytes: BitArray,
  max_block_size: Int,
  max_transaction_count: Int,
) {
  let policy =
    block.default_decode_policy()
    |> block.decode_policy_with_max_block_size(max_block_size)
    |> block.decode_policy_with_max_tx_count(max_transaction_count)

  block.deserialize_with_policy(bytes, policy)
}
