import btc_parser/block
import btc_parser/transaction.{type Transaction}
import gleam/bit_array
import gleam/list
import gleam/string
import simplifile

type FixtureExpectation {
  FixtureExpectation(
    file_name: String,
    byte_length: Int,
    version: Int,
    previous_block_hash_hex: String,
    merkle_root_hex: String,
    timestamp: Int,
    target: Int,
    nonce: Int,
    legacy_tx_count: Int,
    segwit_tx_count: Int,
  )
}

const mainnet_0_fixture = FixtureExpectation(
  file_name: "mainnet-0.hex",
  byte_length: 285,
  version: 1,
  previous_block_hash_hex: "0000000000000000000000000000000000000000000000000000000000000000",
  merkle_root_hex: "3ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4a",
  timestamp: 1_231_006_505,
  target: 486_604_799,
  nonce: 2_083_236_893,
  legacy_tx_count: 1,
  segwit_tx_count: 0,
)

const mainnet_170_fixture = FixtureExpectation(
  file_name: "mainnet-170.hex",
  byte_length: 490,
  version: 1,
  previous_block_hash_hex: "55bd840a78798ad0da853f68974f3d183e2bd1db6a842c1feecf222a00000000",
  merkle_root_hex: "ff104ccb05421ab93e63f8c3ce5c2c2e9dbb37de2764b3a3175c8166562cac7d",
  timestamp: 1_231_731_025,
  target: 486_604_799,
  nonce: 1_889_418_792,
  legacy_tx_count: 2,
  segwit_tx_count: 0,
)

const mainnet_519311_fixture = FixtureExpectation(
  file_name: "mainnet-519311.hex",
  byte_length: 22_884,
  version: 536_870_912,
  previous_block_hash_hex: "90e82ac51d6b37446dc3e6ade48e387a46bcc0b454e126000000000000000000",
  merkle_root_hex: "1ca2e4bd9b9a855e21e53f9b238a6a0065ec8d4417d8140ce3354159c583ea69",
  timestamp: 1_524_344_449,
  target: 390_680_589,
  nonce: 2_903_091_924,
  legacy_tx_count: 18,
  segwit_tx_count: 15,
)

pub fn decode_mainnet_0_fixture_test() {
  assert_fixture_decodes(mainnet_0_fixture)
}

pub fn decode_mainnet_170_fixture_test() {
  assert_fixture_decodes(mainnet_170_fixture)
}

pub fn decode_mainnet_519311_fixture_test() {
  assert_fixture_decodes(mainnet_519311_fixture)
}

fn assert_fixture_decodes(expectation: FixtureExpectation) -> Nil {
  let FixtureExpectation(
    file_name:,
    byte_length: expected_byte_length,
    version: expected_version,
    previous_block_hash_hex:,
    merkle_root_hex:,
    timestamp: expected_timestamp,
    target: expected_target,
    nonce: expected_nonce,
    legacy_tx_count: expected_legacy_count,
    segwit_tx_count: expected_segwit_count,
  ) = expectation

  let assert Ok(fixture_hex) =
    simplifile.read("test/btc_parser/block/fixtures/" <> file_name)
  let fixture_hex = string.trim(fixture_hex)

  assert string.length(fixture_hex) == expected_byte_length * 2

  let assert Ok(decoded_block) = block.decode_hex(fixture_hex)
  let header = block.get_header(decoded_block)

  assert block.get_header_version(header) == expected_version
  assert block.get_header_previous_block_hash(header)
    == decode_fixture_hash(previous_block_hash_hex)
  assert block.get_header_merkle_root(header)
    == decode_fixture_hash(merkle_root_hex)
  assert block.get_header_timestamp(header) == expected_timestamp
  assert block.get_header_target(header) == expected_target
  assert block.get_header_nonce(header) == expected_nonce

  let txs = block.get_transactions(decoded_block)

  assert count_transaction_encodings(txs)
    == #(expected_legacy_count, expected_segwit_count)
  assert list.length(txs) == expected_legacy_count + expected_segwit_count
}

fn decode_fixture_hash(hex: String) -> BitArray {
  let assert Ok(hash) = bit_array.base16_decode(hex)
  hash
}

fn count_transaction_encodings(
  transactions: List(Transaction(s)),
) -> #(Int, Int) {
  list.fold(transactions, #(0, 0), fn(counts, tx) {
    let #(legacy_count, segwit_count) = counts

    case transaction.is_segwit(tx) {
      True -> #(legacy_count, segwit_count + 1)
      False -> #(legacy_count + 1, segwit_count)
    }
  })
}
