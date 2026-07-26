import btc_parser/block.{type Block, type Parsed}
import btc_parser/transaction
import gleam/bit_array
import gleam/crypto.{Sha256}
import gleam/list
import gleam/string
import simplifile
import support/bitcoin_wire.{compact_size}
import support/transaction_wire.{
  build_minimal_legacy_transaction_bytes, build_minimal_segwit_transaction_bytes,
}

// ============================================================================
// Core computation
// ============================================================================

pub fn compute_merkle_root_for_empty_block_is_zero_and_not_mutated_test() {
  let parsed_block = deserialize_zero_header_block([])

  assert_computed_merkle_root(parsed_block, <<0:256>>, False)
}

pub fn compute_merkle_root_for_single_legacy_transaction_is_its_txid_test() {
  let tx_bytes = build_minimal_legacy_transaction_bytes(1)
  let assert Ok(tx) = transaction.deserialize(tx_bytes)
  let parsed_block = deserialize_zero_header_block([tx_bytes])

  assert_computed_merkle_root(parsed_block, transaction.compute_txid(tx), False)
}

pub fn compute_merkle_root_for_single_segwit_transaction_uses_txid_not_wtxid_test() {
  let tx_bytes = build_minimal_segwit_transaction_bytes()
  let assert Ok(tx) = transaction.deserialize(tx_bytes)

  let txid = transaction.compute_txid(tx)
  let wtxid = transaction.compute_wtxid(tx)
  assert txid != wtxid

  let parsed_block = deserialize_zero_header_block([tx_bytes])

  assert_computed_merkle_root(parsed_block, txid, False)
}

pub fn compute_merkle_root_for_two_unique_transactions_hashes_their_txids_test() {
  let tx_a_bytes = build_minimal_legacy_transaction_bytes(1)
  let tx_b_bytes = build_minimal_legacy_transaction_bytes(2)

  let txid_a = compute_txid(tx_a_bytes)
  let txid_b = compute_txid(tx_b_bytes)

  let parsed_block = deserialize_zero_header_block([tx_a_bytes, tx_b_bytes])
  let expected_root = dsha256(bit_array.append(txid_a, txid_b))

  assert_computed_merkle_root(parsed_block, expected_root, False)
}

pub fn compute_merkle_root_for_three_unique_transactions_pads_without_mutation_test() {
  let tx_a_bytes = build_minimal_legacy_transaction_bytes(1)
  let tx_b_bytes = build_minimal_legacy_transaction_bytes(2)
  let tx_c_bytes = build_minimal_legacy_transaction_bytes(3)

  let txid_a = compute_txid(tx_a_bytes)
  let txid_b = compute_txid(tx_b_bytes)
  let txid_c = compute_txid(tx_c_bytes)

  let parsed_block =
    deserialize_zero_header_block([tx_a_bytes, tx_b_bytes, tx_c_bytes])

  let pair_ab = dsha256(bit_array.append(txid_a, txid_b))
  let padded_c = dsha256(bit_array.append(txid_c, txid_c))
  let expected_root = dsha256(bit_array.append(pair_ab, padded_c))

  assert_computed_merkle_root(parsed_block, expected_root, False)
}

// ============================================================================
// Mutation flag
// ============================================================================

pub fn compute_merkle_root_marks_an_actual_identical_leaf_pair_as_mutated_test() {
  let tx_a_bytes = build_minimal_legacy_transaction_bytes(1)
  let txid_a = compute_txid(tx_a_bytes)

  let parsed_block = deserialize_zero_header_block([tx_a_bytes, tx_a_bytes])
  let expected_root = dsha256(bit_array.append(txid_a, txid_a))

  assert_computed_merkle_root(parsed_block, expected_root, True)
}

pub fn compute_merkle_root_distinguishes_padding_from_an_identical_leaf_pair_test() {
  let tx_a_bytes = build_minimal_legacy_transaction_bytes(1)
  let tx_b_bytes = build_minimal_legacy_transaction_bytes(2)
  let tx_c_bytes = build_minimal_legacy_transaction_bytes(3)

  let txid_a = compute_txid(tx_a_bytes)
  let txid_b = compute_txid(tx_b_bytes)
  let txid_c = compute_txid(tx_c_bytes)

  let pair_ab = dsha256(bit_array.append(txid_a, txid_b))
  let pair_cc = dsha256(bit_array.append(txid_c, txid_c))
  let expected_root = dsha256(bit_array.append(pair_ab, pair_cc))

  let three_tx_block =
    deserialize_zero_header_block([tx_a_bytes, tx_b_bytes, tx_c_bytes])

  let four_tx_block =
    deserialize_zero_header_block([
      tx_a_bytes,
      tx_b_bytes,
      tx_c_bytes,
      tx_c_bytes,
    ])

  assert_computed_merkle_root(three_tx_block, expected_root, False)
  assert_computed_merkle_root(four_tx_block, expected_root, True)
}

pub fn compute_merkle_root_marks_identical_parent_hashes_as_mutated_test() {
  let tx_a_bytes = build_minimal_legacy_transaction_bytes(1)
  let tx_b_bytes = build_minimal_legacy_transaction_bytes(2)

  let txid_a = compute_txid(tx_a_bytes)
  let txid_b = compute_txid(tx_b_bytes)
  assert txid_a != txid_b

  let pair_ab = dsha256(bit_array.append(txid_a, txid_b))
  let expected_root = dsha256(bit_array.append(pair_ab, pair_ab))

  let parsed_block =
    deserialize_zero_header_block([
      tx_a_bytes,
      tx_b_bytes,
      tx_a_bytes,
      tx_b_bytes,
    ])

  assert_computed_merkle_root(parsed_block, expected_root, True)
}

// ============================================================================
// Mainnet vectors
// ============================================================================

type MainnetFixture {
  MainnetFixture(file_name: String, transaction_count: Int)
}

pub fn compute_merkle_root_matches_mainnet_header_vectors_test() {
  [
    MainnetFixture("mainnet-0.hex", 1),
    MainnetFixture("mainnet-170.hex", 2),
    MainnetFixture("mainnet-519311.hex", 33),
  ]
  |> list.each(assert_fixture_merkle_root)
}

fn assert_fixture_merkle_root(fixture: MainnetFixture) -> Nil {
  let MainnetFixture(file_name:, transaction_count:) = fixture

  let assert Ok(fixture_hex) =
    simplifile.read("test/btc_parser/block/fixtures/" <> file_name)

  let assert Ok(parsed_block) =
    fixture_hex
    |> string.trim
    |> block.deserialize_hex

  let header_merkle_root =
    parsed_block
    |> block.get_header
    |> block.get_header_merkle_root

  assert block.get_transaction_count(parsed_block) == transaction_count
  assert_computed_merkle_root(parsed_block, header_merkle_root, False)
}

// ============================================================================
// Helpers
// ============================================================================

fn deserialize_zero_header_block(
  transactions: List(BitArray),
) -> Block(Parsed) {
  let bytes = <<
    0:size(640),
    compact_size(list.length(transactions)):bits,
    bit_array.concat(transactions):bits,
  >>
  let assert Ok(parsed_block) = block.deserialize(bytes)

  parsed_block
}

fn compute_txid(bytes: BitArray) -> BitArray {
  let assert Ok(tx) = transaction.deserialize(bytes)
  transaction.compute_txid(tx)
}

fn assert_computed_merkle_root(
  parsed_block: Block(state),
  expected_root: BitArray,
  expected_mutated: Bool,
) -> Nil {
  let #(root, mutated) = block.compute_merkle_root(parsed_block)

  assert bit_array.byte_size(root) == 32
  assert root == expected_root
  assert mutated == expected_mutated
}

fn dsha256(bytes: BitArray) -> BitArray {
  bytes
  |> crypto.hash(Sha256, _)
  |> crypto.hash(Sha256, _)
}
