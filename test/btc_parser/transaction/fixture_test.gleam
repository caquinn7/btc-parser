import btc_parser/transaction.{type Parsed, type Transaction}
import gleam/bit_array
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import simplifile
import support/bitcoin_wire.{get_display_hex}

type FixtureEncoding {
  LegacyEncoding
  SegwitEncoding
}

type FixtureExpectation {
  FixtureExpectation(
    file_name: String,
    byte_length: Int,
    version: Int,
    encoding: FixtureEncoding,
    input_count: Int,
    output_count: Int,
    lock_time: Int,
    display_txid_hex: String,
    display_wtxid_hex: Option(String),
  )
}

const legacy_v1_fixture = FixtureExpectation(
  file_name: "legacy-v1.hex",
  byte_length: 1279,
  version: 1,
  encoding: LegacyEncoding,
  input_count: 1,
  output_count: 33,
  lock_time: 939_066,
  display_txid_hex: "619122b4146f5edbf49f2e0aaa1380f2b7668cf9e9fc66fd788e791bf954d6da",
  display_wtxid_hex: None,
)

const legacy_v2_fixture = FixtureExpectation(
  file_name: "legacy-v2.hex",
  byte_length: 189,
  version: 2,
  encoding: LegacyEncoding,
  input_count: 1,
  output_count: 1,
  lock_time: 0,
  display_txid_hex: "05d350c8a65010bbe9d220b2accd7601b4c6541b7c6d7f5ad451efbcc07f8d66",
  display_wtxid_hex: None,
)

const segwit_v1_fixture = FixtureExpectation(
  file_name: "segwit-v1.hex",
  byte_length: 372,
  version: 1,
  encoding: SegwitEncoding,
  input_count: 2,
  output_count: 2,
  lock_time: 0,
  display_txid_hex: "632ac65a62740afbb69fdaee8da8cf12ed53e999b76f2713820937fe2ca2a7ff",
  display_wtxid_hex: Some(
    "3a6141f6c2c9f64d04f2b2819b2f40ae76ad9a46b541101da745c9056244eb0d",
  ),
)

const segwit_single_input_fixture = FixtureExpectation(
  file_name: "segwit-single-input.hex",
  byte_length: 225,
  version: 1,
  encoding: SegwitEncoding,
  input_count: 1,
  output_count: 2,
  lock_time: 0,
  display_txid_hex: "c06aaaa2753dc4e74dd4fe817522dc3c126fd71792dd9acfefdaff11f8ff954d",
  display_wtxid_hex: Some(
    "f12d56f2234e809129dbf59392961bbe7a89b6250651f6aea7852cc00ced63ff",
  ),
)

pub fn deserialize_legacy_v1_fixture_test() {
  assert_fixture_deserializes(legacy_v1_fixture)
}

pub fn deserialize_legacy_v2_fixture_test() {
  assert_fixture_deserializes(legacy_v2_fixture)
}

pub fn deserialize_segwit_v1_fixture_test() {
  assert_fixture_deserializes(segwit_v1_fixture)
}

pub fn deserialize_segwit_wtxid_vector_fixture_test() {
  assert_fixture_deserializes(segwit_single_input_fixture)
}

/// Deserialize a fixture and assert its structural fields match its expectation.
fn assert_fixture_deserializes(expectation: FixtureExpectation) -> Nil {
  let tx = deserialize_fixture(expectation)

  assert transaction.get_version(tx) == expectation.version
  assert transaction.get_input_count(tx) == expectation.input_count
  assert transaction.get_output_count(tx) == expectation.output_count
  assert transaction.get_lock_time(tx) == expectation.lock_time

  case expectation.encoding {
    LegacyEncoding -> {
      assert !transaction.is_segwit(tx)
      assert transaction.get_witnesses(tx) == Error(Nil)
    }
    SegwitEncoding -> {
      assert transaction.is_segwit(tx)
      let assert Ok(witnesses) = transaction.get_witnesses(tx)
      assert list.length(witnesses) == expectation.input_count
    }
  }
}

pub fn round_trip_legacy_v1_fixture_test() {
  assert_fixture_round_trips(legacy_v1_fixture)
}

pub fn round_trip_legacy_v2_fixture_test() {
  assert_fixture_round_trips(legacy_v2_fixture)
}

pub fn round_trip_segwit_v1_fixture_test() {
  assert_fixture_round_trips(segwit_v1_fixture)
}

pub fn round_trip_segwit_wtxid_vector_fixture_test() {
  assert_fixture_round_trips(segwit_single_input_fixture)
}

/// Serialize a fixture after deserialization and compare it with its source bytes.
fn assert_fixture_round_trips(expectation: FixtureExpectation) -> Nil {
  let fixture_hex = read_fixture_hex(expectation)
  let assert Ok(original_bytes) = bit_array.base16_decode(fixture_hex)
  let assert Ok(tx) = transaction.deserialize(original_bytes)

  assert transaction.serialize(tx) == original_bytes
}

pub fn compute_identifiers_legacy_v1_fixture_test() {
  assert_fixture_identifiers(legacy_v1_fixture)
}

pub fn compute_identifiers_legacy_v2_fixture_test() {
  assert_fixture_identifiers(legacy_v2_fixture)
}

pub fn compute_identifiers_segwit_v1_fixture_test() {
  assert_fixture_identifiers(segwit_v1_fixture)
}

pub fn compute_identifiers_segwit_wtxid_vector_fixture_test() {
  assert_fixture_identifiers(segwit_single_input_fixture)
}

/// Compute a fixture's identifiers and compare them with its display-hash vectors.
fn assert_fixture_identifiers(expectation: FixtureExpectation) -> Nil {
  let tx = deserialize_fixture(expectation)

  assert get_display_hex(transaction.compute_txid(tx))
    == expectation.display_txid_hex

  case expectation.display_wtxid_hex {
    None -> Nil
    Some(display_wtxid_hex) -> {
      assert get_display_hex(transaction.compute_wtxid(tx)) == display_wtxid_hex
    }
  }
}

pub fn validate_context_free_consensus_legacy_v1_fixture_test() {
  assert_fixture_validates_context_free(legacy_v1_fixture)
}

pub fn validate_context_free_consensus_segwit_v1_fixture_test() {
  assert_fixture_validates_context_free(segwit_v1_fixture)
}

/// Validate a fixture and ensure the phantom-state upgrade preserves serialization.
fn assert_fixture_validates_context_free(
  expectation: FixtureExpectation,
) -> Nil {
  let tx = deserialize_fixture(expectation)
  let serialized_before_validation = transaction.serialize(tx)
  let assert Ok(validated_tx) = transaction.validate_context_free_consensus(tx)

  assert transaction.serialize(validated_tx) == serialized_before_validation
}

/// Read and deserialize a transaction fixture into its parsed state.
fn deserialize_fixture(expectation: FixtureExpectation) -> Transaction(Parsed) {
  let fixture_hex = read_fixture_hex(expectation)
  let assert Ok(tx) = transaction.deserialize_hex(fixture_hex)
  tx
}

/// Read, trim, and size-check a fixture's hexadecimal wire encoding.
fn read_fixture_hex(expectation: FixtureExpectation) -> String {
  let assert Ok(fixture_hex) =
    simplifile.read(
      "test/btc_parser/transaction/fixtures/" <> expectation.file_name,
    )
  let fixture_hex = string.trim(fixture_hex)

  assert string.length(fixture_hex) == expectation.byte_length * 2
  fixture_hex
}
