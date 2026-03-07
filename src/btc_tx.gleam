//// Parse, inspect, and validate Bitcoin transactions.
////
//// This module provides type-safe facilities for working with Bitcoin transaction
//// data, supporting both legacy and SegWit transaction formats. It includes
//// safe parsing with configurable resource limits, comprehensive error reporting,
//// and consensus validation.
////
//// ## Quick Start
////
//// ```gleam
//// import btc_tx
////
//// // Decode from hex
//// case btc_tx.decode_hex("0100000001...") {
////   Ok(tx) -> {
////     // Inspect transaction
////     let version = btc_tx.get_version(tx)
////     let inputs = btc_tx.get_inputs(tx)
////     let outputs = btc_tx.get_outputs(tx)
////
////     // Validate consensus rules
////     case btc_tx.validate_consensus(tx) {
////       Ok(validated_tx) -> // Transaction is consensus-valid
////       Error(errors) -> // Handle validation failures
////     }
////   }
////   Error(btc_tx.ParseFailed(err)) -> // Handle parse error
////   Error(btc_tx.HexToBytesFailed(err)) -> // Handle hex error
//// }
//// ```
////
//// ## Key Features
////
//// - **Safe parsing**: Configurable resource limits protect against malicious
////   inputs (see `DecodePolicy` and `decode_with_policy`)
//// - **Format detection**: Automatically distinguishes legacy and SegWit transactions
//// - **Rich error context**: Detailed parse errors with byte offsets and context stacks
//// - **Consensus validation**: Check transactions against Bitcoin's consensus rules
//// - **Type safety**: Phantom types distinguish validated from unvalidated transactions
//// - **Script classification**: Identify P2PKH, P2SH, P2WPKH, P2WSH, P2TR, and other
////   standard output script templates (see `classify_output_script`)
//// - **Transaction IDs**: Compute txid and wtxid for validated transactions
////   (see `compute_txid` and `compute_wtxid`)
////
//// ## Main Entry Points
////
//// - `decode` / `decode_hex` - Parse transaction data
//// - `validate_consensus` - Validate against consensus rules
//// - `get_inputs`, `get_outputs`, etc. - Access transaction components
//// - `is_segwit`, `is_coinbase` - Query transaction properties
//// - `classify_output_script` - Classify an output's `script_pubkey` type
//// - `compute_txid` / `compute_wtxid` - Compute transaction identifiers

import gleam/bit_array
import gleam/bool
import gleam/crypto.{Sha256}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/pair
import gleam/result
import internal/compact_size
import internal/fixed_int/int64
import internal/fixed_int/uint64.{type Uint64}
import internal/hash32.{type Hash32}
import internal/parser.{type Parser}
import internal/reader.{type Reader}

// ==============================================================================
// Transaction types
// ==============================================================================

/// Phantom type indicating a transaction that has been successfully
/// parsed but has not yet been validated against Bitcoin consensus rules.
pub type Unvalidated

/// Phantom type indicating a transaction that has passed Bitcoin
/// consensus validation.
pub type Validated

/// A Bitcoin transaction.
///
/// A transaction transfers value by consuming previously created outputs
/// (inputs) and creating new outputs. Transactions are either legacy
/// (pre-SegWit) or SegWit, which affects whether witness data is present
/// in the serialized structure.
pub opaque type Transaction(validation_state) {
  /// A legacy (non-SegWit) transaction.
  ///
  /// Legacy transactions serialize all fields in a single flat structure
  /// with no witness data.
  Legacy(
    /// The transaction version number.
    /// 
    /// Unknown or future version values are permitted by Bitcoin consensus
    /// rules and are therefore not rejected by the decoder.
    version: Int,
    /// The list of transaction inputs.
    inputs: List(TxIn),
    /// The list of transaction outputs.
    outputs: List(TxOut),
    /// The transaction lock time.
    lock_time: Int,
  )

  /// A SegWit transaction.
  ///
  /// SegWit transactions extend the legacy format with a separate witness
  /// data section, keeping witness items out of the main serialization.
  SegWit(
    /// The transaction version number.
    /// 
    /// Unknown or future version values are permitted by Bitcoin consensus
    /// rules and are therefore not rejected by the decoder.
    version: Int,
    /// The list of transaction inputs.
    inputs: List(TxIn),
    /// The list of transaction outputs.
    outputs: List(TxOut),
    /// The transaction lock time.
    lock_time: Int,
    /// The witness stack for each input, indexed by input position.
    witnesses: List(WitnessStack),
  )
}

/// Get the version number from a transaction.
///
/// The version number indicates the transaction format and rules that apply.
/// Common versions are:
/// - Version 1: Original Bitcoin transaction format
/// - Version 2: Introduced with BIP 68 (relative lock-time using sequence numbers)
///
/// Unknown or future version values are permitted by Bitcoin consensus rules,
/// so the decoder does not reject transactions with unrecognized versions.
pub fn get_version(tx: Transaction(v)) -> Int {
  tx.version
}

/// Check whether a transaction uses the SegWit format.
///
/// SegWit (Segregated Witness) transactions separate witness data from the main
/// transaction structure, enabling features like improved scalability and
/// transaction malleability fixes. This function distinguishes between legacy
/// (pre-SegWit) transactions and SegWit transactions.
///
/// Returns `True` for SegWit transactions, `False` for legacy transactions.
pub fn is_segwit(tx: Transaction(v)) -> Bool {
  case tx {
    Legacy(..) -> False
    SegWit(..) -> True
  }
}

/// Check whether a transaction has a coinbase input marker (structural check).
///
/// This function performs a **structural check only**, determining whether any
/// input has the coinbase marker (null previous outpoint). It does not verify
/// that the transaction satisfies coinbase consensus rules.
///
/// A transaction may have a coinbase input but fail validation due to:
/// - Having multiple inputs (coinbase transactions must have exactly one input)
/// - Invalid scriptSig length (must be 2-100 bytes for coinbase)
///
/// For a consensus-validated check, use `is_coinbase` after calling
/// `validate_consensus`.
///
/// Returns `True` if any input has a coinbase marker, `False` otherwise.
pub fn has_coinbase_marker(tx: Transaction(v)) -> Bool {
  list.any(tx.inputs, fn(txin) { prev_out_is_coinbase_marker(txin.prev_out) })
}

/// Check whether a transaction is a valid coinbase transaction.
///
/// This function returns `True` only for transactions that have been validated
/// against Bitcoin consensus rules and confirmed to be valid coinbase transactions.
///
/// A coinbase transaction is the first transaction in a block, which creates new
/// bitcoins as a block reward and does not spend any previous outputs. Valid
/// coinbase transactions must:
/// - Have exactly one input with a coinbase marker (null previous outpoint)
/// - Have a scriptSig between 2 and 100 bytes in length
///
/// **Requires validation**: This function accepts only `Transaction(Validated)`,
/// ensuring the transaction has passed all consensus checks via `validate_consensus`.
///
/// For a structural check without validation, use `has_coinbase_marker`.
///
/// Returns `True` if this is a valid coinbase transaction, `False` otherwise.
pub fn is_coinbase(tx: Transaction(Validated)) -> Bool {
  has_coinbase_marker(tx)
}

/// Get the transaction inputs.
///
/// Returns the inputs in the same order they appear in the transaction serialization.
pub fn get_inputs(tx: Transaction(v)) -> List(TxIn) {
  tx.inputs
}

/// Get the transaction outputs.
///
/// Returns the outputs in the same order they appear in the transaction serialization.
pub fn get_outputs(tx: Transaction(v)) -> List(TxOut) {
  tx.outputs
}

/// Get the lock time from a transaction.
///
/// Lock time specifies when this transaction is valid:
/// - Values less than 500,000,000 are interpreted as block heights
/// - Values greater than or equal to 500,000,000 are interpreted as Unix timestamps
/// - A value of 0 means the transaction is valid immediately
pub fn get_lock_time(tx: Transaction(v)) -> Int {
  tx.lock_time
}

/// Get the witness stacks from a SegWit transaction.
///
/// Returns `Ok(witnesses)` if the transaction uses SegWit format, or `Error(Nil)`
/// if it's a legacy transaction (which has no witness data).
///
/// The witness stacks are returned in order, corresponding 1-to-1 with the
/// transaction inputs by position (witness stack at index N corresponds to
/// input at index N).
pub fn get_witnesses(tx: Transaction(v)) -> Result(List(WitnessStack), Nil) {
  case tx {
    SegWit(witnesses:, ..) -> Ok(witnesses)
    Legacy(..) -> Error(Nil)
  }
}

/// A transaction input.
///
/// An input references a previous transaction output and provides the data
/// required to satisfy that output’s spending conditions.
pub opaque type TxIn {
  TxIn(
    /// The previous output being spent, or a coinbase marker.
    prev_out: PrevOut,
    /// The unlocking script (scriptSig) for this input.
    ///
    /// This script is evaluated together with the referenced output’s
    /// scriptPubKey during script execution.
    script_sig: ScriptBytes(InputScript),
    /// The sequence number associated with this input.
    ///
    /// Sequence numbers are used for relative lock-time semantics and
    /// transaction replacement rules.
    sequence: Int,
  )
}

/// Get the previous output reference from an input.
pub fn get_input_prev_out(input: TxIn) -> PrevOut {
  input.prev_out
}

/// Get the sequence number from an input.
pub fn get_input_sequence(input: TxIn) -> Int {
  input.sequence
}

/// Get the scriptSig from an input.
pub fn get_input_script_sig(input: TxIn) -> ScriptBytes(InputScript) {
  input.script_sig
}

/// A reference to a previous transaction output.
///
/// This identifies the output being consumed by a transaction input.
pub opaque type PrevOut {
  /// A special marker used by coinbase transactions.
  ///
  /// Coinbase inputs do not reference a previous transaction output.
  NullOutPoint

  /// A reference to a specific output of a previous transaction.
  ///
  /// `txid` identifies the transaction, and `vout` is the zero-based index
  /// of the output within that transaction.
  OutPoint(txid: Hash32, vout: Int)
}

/// Get the transaction ID from a previous output reference.
///
/// Returns the 32 bytes of the txid in little-endian byte order.
/// For coinbase inputs (which don't reference a previous output), returns an all-zero hash.
pub fn get_prev_out_txid(prev_out: PrevOut) -> BitArray {
  case prev_out {
    NullOutPoint -> <<0:256>>
    OutPoint(txid:, ..) -> hash32.to_bytes_le(txid)
  }
}

/// Get the output index from a previous output reference.
///
/// Returns the zero-based index of the output within the referenced transaction.
/// For coinbase inputs (which don't reference a previous output), returns `0xFFFFFFFF`,
/// a special sentinel value indicating no previous output.
pub fn get_prev_out_vout(prev_out: PrevOut) -> Int {
  case prev_out {
    NullOutPoint -> 0xFFFFFFFF
    OutPoint(vout:, ..) -> vout
  }
}

/// Check whether a previous output reference is a coinbase marker.
fn prev_out_is_coinbase_marker(prev_out: PrevOut) -> Bool {
  case prev_out {
    NullOutPoint -> True
    OutPoint(..) -> False
  }
}

/// A witness stack for a single transaction input.
///
/// Each SegWit input has an associated witness stack containing the items
/// needed to satisfy its spending conditions. The number and interpretation
/// of these items depends on the witness program being executed.
pub opaque type WitnessStack {
  WitnessStack(List(WitnessItem))
}

/// Get the witness items from a witness stack.
///
/// Returns the witness items in order as they appear in the serialization.
pub fn get_witness_items(stack: WitnessStack) -> List(WitnessItem) {
  let WitnessStack(items) = stack
  items
}

/// A single item from a witness stack.
///
/// Witness items are arbitrary byte sequences (e.g., public keys, signatures,
/// or script data) whose meaning is determined by the witness program.
pub opaque type WitnessItem {
  WitnessItem(BitArray)
}

/// Get the raw bytes from a witness item.
pub fn get_witness_item_bytes(item: WitnessItem) -> BitArray {
  let WitnessItem(bytes) = item
  bytes
}

/// A transaction output.
///
/// An output assigns a value and specifies the conditions under which that
/// value may be spent in the future.
pub opaque type TxOut {
  TxOut(
    /// The number of satoshis assigned to this output.
    value: Int,
    /// The locking script (scriptPubKey) defining the spending conditions.
    script_pubkey: ScriptBytes(OutputScript),
  )
}

/// Get the value assigned to a transaction output.
///
/// Returns the number of satoshis that will be available to spend if the
/// output's spending conditions (specified by scriptPubKey) are satisfied.
pub fn get_output_value(output: TxOut) -> Int {
  output.value
}

/// Get the locking script from a transaction output.
///
/// Returns the scriptPubKey that defines the conditions under which this
/// output may be spent. The script is interpreted together with a spending
/// input's scriptSig during script validation.
pub fn get_output_script_pubkey(output: TxOut) -> ScriptBytes(OutputScript) {
  output.script_pubkey
}

/// Phantom type tag for `ScriptBytes` — marks a scriptSig (input unlocking script).
pub type InputScript

/// Phantom type tag for `ScriptBytes` — marks a scriptPubKey (output locking script).
pub type OutputScript

/// Raw Bitcoin script bytes.
///
/// The `kind` type parameter is a phantom tag distinguishing input scripts
/// (`ScriptBytes(InputScript)`) from output scripts (`ScriptBytes(OutputScript)`).
/// It carries no runtime representation.
///
/// This type represents an uninterpreted script as it appears on the wire.
/// No validation or opcode parsing is performed at this level.
pub opaque type ScriptBytes(kind) {
  ScriptBytes(BitArray)
}

/// Get the raw bytes from a `ScriptBytes`.
pub fn get_raw_script_bytes(script: ScriptBytes(k)) -> BitArray {
  let ScriptBytes(bytes) = script
  bytes
}

pub fn get_script_length(script: ScriptBytes(k)) -> Int {
  script
  |> get_raw_script_bytes
  |> bit_array.byte_size
}

// ==============================================================================
// Output script classification
// ==============================================================================

/// The recognised script type of a transaction output's locking script.
///
/// Identifies which standard Bitcoin script template a `script_pubkey` matches,
/// enabling type-safe dispatch when inspecting or spending outputs.
pub type OutputScriptType {
  /// Pay-to-public-key. The script directly commits to a public key and uses
  /// `OP_CHECKSIG` for validation. Accepts both compressed (33-byte) and
  /// uncompressed (65-byte) public keys.
  P2PK

  /// Pay-to-public-key-hash. The most common legacy output type.
  P2PKH

  /// Pay-to-script-hash. The hash of the redeem script is embedded in the
  /// `scriptPubKey`; the actual spending conditions are revealed in the input's
  /// `scriptSig`.
  P2SH

  /// Pay-to-witness-public-key-hash. SegWit v0 output for single-key spends.
  P2WPKH

  /// Pay-to-witness-script-hash. SegWit v0 output for script-based spends.
  P2WSH

  /// Pay-to-taproot. SegWit v1 output supporting key-path and script-path spends.
  P2TR

  /// Bare m-of-n multisig. Uses `OP_CHECKMULTISIG` directly in the
  /// `scriptPubKey`. Bitcoin Core allows 1–3 keys and 1–3 required signatures.
  Multisig

  /// Standard null-data output as defined by Bitcoin Core's standardness rules.
  ///
  /// Matches scripts that begin with `OP_RETURN`, are followed only by push
  /// opcodes, and have a total size of at most 83 bytes. The size limit is a
  /// Bitcoin Core relay policy constraint, not a consensus rule — this variant
  /// intentionally mirrors the standard template definition rather than the
  /// looser structural shape of "any push-only `OP_RETURN` script".
  ///
  /// An `OP_RETURN` script that is push-only but exceeds 83 bytes, or that
  /// contains non-push opcodes after `OP_RETURN`, will classify as
  /// `NonStandard` instead.
  NullData

  /// A well-formed witness program whose version (1–16) does not map to a
  /// named script type. `version` is the decoded witness version number
  /// (1–16 — note version 1 with a 32-byte program is `P2TR` and never
  /// appears here). Forward-compatible; should not be treated the same as
  /// `NonStandard`.
  UnknownWitness(version: Int)

  /// Does not match any recognized standard output template.
  NonStandard
}

/// Classify the script type of a transaction output's locking script.
///
/// Matches `script_pubkey` bytes against known Bitcoin script templates and
/// returns the corresponding `OutputScriptType`.
///
/// ## Classification
///
/// ```
/// ├─ 76 A9 14 [×20] 88 AC                  → P2PKH
/// ├─ A9 14 [×20] 87                        → P2SH
/// ├─ 00 14 [×20]                           → P2WPKH
/// ├─ 00 20 [×32]                           → P2WSH
/// ├─ 51 20 [×32]                           → P2TR
/// ├─ 21 [×33] AC                           → P2PK (compressed)
/// ├─ 41 [×65] AC                           → P2PK (uncompressed)
/// ├─ 6A …                                  (OP_RETURN prefix)
/// │   ├─ total ≤ 83 bytes AND push-only    → NullData
/// │   └─ otherwise                         → NonStandard
/// └─ (none matched)
///     ├─ [51–60] [02–28] [×push_len]       → UnknownWitness(version)
///     └─ valid m-of-n (1≤m≤n≤3)
///         ├─ AND pubkey count matches n    → Multisig
///         └─ otherwise                     → NonStandard
/// ```
///
/// ## Examples
///
/// ```gleam
/// let script_pubkey = get_output_script_pubkey(output)
/// case classify_output_script(script_pubkey) {
///   P2PKH       -> // legacy single-sig pay-to-pubkey-hash
///   P2WPKH      -> // native SegWit single-sig
///   P2TR        -> // taproot
///   NonStandard -> // no matching template
///   _           -> // other standard type
/// }
/// ```
pub fn classify_output_script(
  script: ScriptBytes(OutputScript),
) -> OutputScriptType {
  let script_bytes = get_raw_script_bytes(script)
  case script_bytes {
    // P2PKH: OP_DUP OP_HASH160 OP_DATA_20 <20-byte hash> OP_EQUALVERIFY OP_CHECKSIG
    <<0x76, 0xA9, 0x14, _:bytes-size(20), 0x88, 0xAC>> -> P2PKH

    // P2SH: OP_HASH160 OP_DATA_20 <20-byte hash> OP_EQUAL
    <<0xA9, 0x14, _:bytes-size(20), 0x87>> -> P2SH

    // P2WPKH: OP_0 OP_DATA_20 <20-byte witness program>
    <<0x00, 0x14, _:bytes-size(20)>> -> P2WPKH

    // P2WSH: OP_0 OP_DATA_32 <32-byte witness program>
    <<0x00, 0x20, _:bytes-size(32)>> -> P2WSH

    // P2TR: OP_1 OP_DATA_32 <32-byte x-only pubkey>
    <<0x51, 0x20, _:bytes-size(32)>> -> P2TR

    // P2PK: OP_DATA_33 <compressed pubkey> OP_CHECKSIG
    <<0x21, _:bytes-size(33), 0xAC>> -> P2PK

    // P2PK: OP_DATA_65 <uncompressed pubkey> OP_CHECKSIG
    <<0x41, _:bytes-size(65), 0xAC>> -> P2PK

    // NullData: OP_RETURN + push-only data, total ≤ 83 bytes (Bitcoin Core standard template).
    <<0x6A, rest:bits>> ->
      case bit_array.byte_size(script_bytes) <= 83 && do_is_push_only(rest) {
        True -> NullData
        False -> NonStandard
      }

    _ -> do_classify_non_template(script_bytes)
  }
}

/// Classify scripts that did not match any fixed-length template.
/// Checks for future witness versions and bare multisig.
fn do_classify_non_template(script_bytes: BitArray) -> OutputScriptType {
  case script_bytes {
    // UnknownWitness: OP_1–OP_16 followed by a 2–40 byte witness program.
    // OP_0 (P2WPKH/P2WSH) is already handled above.
    // OP_1 with a 32-byte program is already handled above as P2TR.
    <<version, push_len, _:bytes-size(push_len)>>
      if version >= 0x51 && version <= 0x60 && push_len >= 2 && push_len <= 40
    -> UnknownWitness(version: decode_small_int_opcode(version))

    _ ->
      case do_is_standard_multisig(script_bytes) {
        True -> Multisig
        False -> NonStandard
      }
  }
}

/// Return `True` if every opcode in `bytes` is a push opcode.
/// Handles `OP_0`, `OP_1NEGATE`, `OP_1`–`OP_16`, direct pushes (1–75 bytes),
/// `OP_PUSHDATA1`, `OP_PUSHDATA2`, and `OP_PUSHDATA4`.
fn do_is_push_only(bytes: BitArray) -> Bool {
  case bytes {
    <<>> -> True
    // OP_0: pushes empty array
    <<0x00, rest:bits>> -> do_is_push_only(rest)

    // OP_1NEGATE: pushes -1
    <<0x4F, rest:bits>> -> do_is_push_only(rest)

    // OP_1..OP_16: small integer pushes
    <<opcode, rest:bits>> if opcode >= 0x51 && opcode <= 0x60 ->
      do_is_push_only(rest)

    // Direct push: 1–75 bytes follow immediately
    <<push_len, rest:bits>> if push_len >= 0x01 && push_len <= 0x4B ->
      case rest {
        <<_:bytes-size(push_len), remainder:bits>> -> do_is_push_only(remainder)
        _ -> False
      }

    // OP_PUSHDATA1: next byte is length, then data
    <<0x4C, len, rest:bits>> ->
      case rest {
        <<_:bytes-size(len), remainder:bits>> -> do_is_push_only(remainder)
        _ -> False
      }

    // OP_PUSHDATA2: next 2 bytes (LE) are length, then data
    <<0x4D, len:little-size(16), rest:bits>> ->
      case rest {
        <<_:bytes-size(len), remainder:bits>> -> do_is_push_only(remainder)
        _ -> False
      }

    // OP_PUSHDATA4: next 4 bytes (LE) are length, then data
    <<0x4E, len:little-size(32), rest:bits>> ->
      case rest {
        <<_:bytes-size(len), remainder:bits>> -> do_is_push_only(remainder)
        _ -> False
      }

    // Anything else is a non-push opcode
    _ -> False
  }
}

/// Return `True` if `bytes` is a standard bare multisig script:
/// `OP_m { OP_DATA_33 <pubkey> | OP_DATA_65 <pubkey> }... OP_n OP_CHECKMULTISIG`
/// where 1 ≤ m ≤ n ≤ 3.
fn do_is_standard_multisig(bytes: BitArray) -> Bool {
  // OP_m + (OP_DATA_33 + 33 bytes) + OP_n + OP_CHECKMULTISIG = 37 bytes
  let multisig_min_bytes = 37
  let total = bit_array.byte_size(bytes)

  use <- bool.guard(total < multisig_min_bytes, False)

  let check = {
    use #(_, pubkey_count) <- result.try(read_multisig_header(bytes, total))
    use pubkey_section <- result.try(bit_array.slice(bytes, 1, total - 3))
    Ok(do_count_multisig_pubkeys(pubkey_section, 0) == pubkey_count)
  }

  result.unwrap(check, False)
}

/// Extract and validate the m, n opcodes and OP_CHECKMULTISIG trailer.
/// Returns Ok(#(min_sigs, pubkey_count)) where both are decoded integer values (1–3).
fn read_multisig_header(bytes: BitArray, total: Int) -> Result(#(Int, Int), Nil) {
  // the first byte
  let m_byte = bit_array.slice(bytes, 0, 1)
  // the second-to-last byte
  let n_byte = bit_array.slice(bytes, total - 2, 1)
  // the last byte
  let trailer_byte = bit_array.slice(bytes, total - 1, 1)

  case m_byte, n_byte, trailer_byte {
    Ok(<<m_opcode>>), Ok(<<n_opcode>>), Ok(<<trailer>>) -> {
      let op_checkmultisig = 0xAE
      use <- bool.guard(trailer != op_checkmultisig, Error(Nil))

      let min_sigs = decode_small_int_opcode(m_opcode)
      let pubkey_count = decode_small_int_opcode(n_opcode)

      case
        1 <= min_sigs
        && min_sigs <= 3
        && 1 <= pubkey_count
        && pubkey_count <= 3
        && min_sigs <= pubkey_count
      {
        True -> Ok(#(min_sigs, pubkey_count))
        False -> Error(Nil)
      }
    }

    _, _, _ -> Error(Nil)
  }
}

/// Count valid pubkey pushes in a bare multisig pubkey section.
/// Returns -1 if the data contains anything other than valid pubkey pushes.
fn do_count_multisig_pubkeys(bytes: BitArray, count: Int) -> Int {
  case bytes {
    <<>> -> count

    // Compressed pubkey: OP_DATA_33 <33 bytes>
    <<0x21, _:bytes-size(33), rest:bits>> ->
      do_count_multisig_pubkeys(rest, count + 1)

    // Uncompressed pubkey: OP_DATA_65 <65 bytes>
    <<0x41, _:bytes-size(65), rest:bits>> ->
      do_count_multisig_pubkeys(rest, count + 1)

    _ -> -1
  }
}

/// Decode a Bitcoin small-integer opcode (`OP_1`–`OP_16`) to its integer value (1–16).
/// The caller is responsible for ensuring `opcode` is in the range `0x51`–`0x60`.
fn decode_small_int_opcode(opcode: Int) -> Int {
  opcode - 0x50
}

// ==============================================================================
// Error handling
// ==============================================================================

/// An error that occurred while decoding a Bitcoin transaction.
///
/// This error type distinguishes between failures that occur during hex-to-bytes
/// conversion and failures that occur during transaction parsing.
pub type DecodeError {
  /// The hexadecimal string could not be converted to bytes.
  ///
  /// This occurs before any transaction parsing begins, typically due to an
  /// odd-length hex string or the presence of invalid hexadecimal characters.
  HexToBytesFailed

  /// The byte sequence could not be parsed as a Bitcoin transaction.
  ///
  /// This wraps a `ParseError` containing details about what went wrong during
  /// the transaction parsing phase.
  ParseFailed(ParseError)
}

/// An error that occurred while parsing a Bitcoin transaction.
///
/// This opaque type contains details about what went wrong during parsing,
/// including the byte offset where the error occurred, the kind of error,
/// and the parsing context (which fields or structures were being parsed).
pub opaque type ParseError {
  ParseError(offset: Int, kind: ParseErrorKind, ctx: List(ParseContext))
}

/// The specific kind of error that occurred during parsing.
///
/// This type categorizes parsing failures into distinct categories.
pub type ParseErrorKind {
  /// The input ended before enough bytes could be read.
  ///
  /// `bytes_needed` is the number of bytes the parser required, and `remaining`
  /// is the number of bytes actually available at that point.
  UnexpectedEof(bytes_needed: Int, remaining: Int)

  /// A CompactSize-encoded integer used a non-minimal encoding.
  ///
  /// Bitcoin's serialization rules require CompactSize integers to use the
  /// shortest possible encoding. This error occurs when a value could have
  /// been encoded in fewer bytes than were used.
  ///
  /// `encoded` is the length of the encoded CompactSize in bytes,
  /// and `value` is the decoded integer value.
  NonMinimalCompactSize(encoded: Int, value: Int)

  /// An error variant indicating that an invalid SegWit marker flag was encountered.
  InvalidSegWitMarkerFlag(marker: Int, flag: Int)

  /// A claimed or required length exceeds structural limits.
  ///
  /// This error occurs when a length field or count field implies more bytes or items
  /// than are structurally available in the input buffer. This is distinct from
  /// `PolicyLimitExceeded`, which enforces parser-defined limits for protection.
  ///
  /// Examples:
  /// - A script length field claims 1000 bytes, but only 100 bytes remain
  /// - An item count implies at least 500 bytes needed, but only 200 remain
  ///
  /// `claimed` represents bytes needed, `remaining` is what's available.
  /// `claimed` may be a conservative estimate (e.g., `remaining + 1`) rather than
  /// the exact number of bytes to avoid integer overflow on the JavaScript target.
  InsufficientBytes(claimed: Int, remaining: Int)

  /// A decoded 64-bit integer value exceeds the range representable by the runtime.
  ///
  /// The original value is preserved as a string for diagnostics.
  IntegerOutOfRange(String)

  /// A policy limit was exceeded.
  ///
  /// This occurs when either an individual field value or cumulative metric exceeds
  /// a policy-defined limit, such as maximum script size, witness item count, or
  /// total witness payload bytes.
  ///
  /// `value` is the offending value, and `max` is the policy limit.
  PolicyLimitExceeded(value: Int, max: Int)

  /// The transaction was successfully parsed, but extra bytes remain in the input.
  ///
  /// This indicates the input buffer contains more data than a single valid transaction.
  /// The wrapped `Int` is the count of trailing bytes that were not consumed.
  TrailingBytes(Int)

  /// A catch-all error for unexpected or internal parsing failures that do not
  /// fit any of the structured error categories.
  Other(String)
}

/// Contextual information about where in the transaction structure a parsing error occurred.
pub type ParseContext {
  /// The error occurred while parsing the top-level transaction structure.
  ///
  /// This is typically added once at the outermost decode layer.
  InTransaction

  /// The error occurred while parsing the transaction’s input vector
  /// (the `vin_count`, `vin` fields).
  InInputs

  /// The error occurred while parsing a specific input within the input vector.
  ///
  /// The wrapped `Int` is the zero-based index of the input being parsed.
  AtInput(Int)

  /// The error occurred while parsing the transaction’s output vector
  /// (the `vout_count`, `vout` fields).
  InOutputs

  /// The error occurred while parsing a specific output within the output vector.
  ///
  /// The wrapped `Int` is the zero-based index of the output being parsed.
  AtOutput(Int)

  /// The error occurred while parsing witness data for a specific input.
  ///
  /// The wrapped `Int` is the zero-based index of the input whose witness
  /// stack was being parsed.
  AtWitnessStack(Int)

  /// The error occurred while parsing a specific item within a witness stack.
  ///
  /// The wrapped `Int` is the zero-based index of the witness item being parsed.
  AtWitnessItem(Int)

  /// The error occurred while parsing a specific named field.
  ///
  /// The wrapped `Field` identifies which transaction field was being parsed
  /// when the error occurred, such as the version, lock time, an input's
  /// script signature, or an output's value.
  AtField(Field)
}

/// A named field within a Bitcoin transaction.
///
/// This type enumerates all the distinct fields that can be parsed from
/// a Bitcoin transaction's serialized format. Fields are used in error
/// reporting to indicate which part of the transaction was being parsed
/// when an error occurred.
pub type Field {
  // Top-level transaction fields
  Version
  LockTime

  // SegWit marker/flag detection
  SegwitDiscriminator
  SegwitMarker

  // Input-related fields
  VinCount
  PrevTxId
  Vout
  ScriptSig
  ScriptSigLength
  Sequence

  // Output-related fields
  VoutCount
  Value
  ScriptPubKey
  ScriptPubKeyLength

  // Witness-related fields
  WitnessStackLength
  WitnessItemLength
  WitnessStackTotalPayloadBytes
}

/// Get the byte offset where a parsing error occurred.
///
/// The offset is a zero-based position into the input buffer, indicating
/// where the parser was reading when it encountered the error. This is useful
/// for debugging and error reporting.
///
/// ## Examples
///
/// ```gleam
/// case decode(malformed_bytes) {
///   Error(ParseFailed(err)) -> {
///     let offset = parse_error_offset(err)
///     // offset: 42 (error occurred at byte position 42)
///   }
///   _ -> // ...
/// }
/// ```
pub fn parse_error_offset(err: ParseError) -> Int {
  err.offset
}

/// Get the specific kind of parsing error that occurred.
///
/// Returns the `ParseErrorKind` variant that categorizes what went wrong,
/// such as `UnexpectedEof`, `NonMinimalCompactSize`, `PolicyLimitExceeded`, etc.
/// This allows you to handle different error types differently.
///
/// ## Examples
///
/// ```gleam
/// case decode(bytes) {
///   Error(ParseFailed(err)) -> {
///     case parse_error_kind(err) {
///       PolicyLimitExceeded(value, max) -> 
///         // Handle resource limit violation
///       InsufficientBytes(claimed, remaining) -> 
///         // Handle truncated input
///       _ -> // Handle other errors
///     }
///   }
///   _ -> // ...
/// }
/// ```
pub fn parse_error_kind(err: ParseError) -> ParseErrorKind {
  err.kind
}

/// Get the parsing context stack for an error.
///
/// Returns a list of `ParseContext` values showing where in the transaction
/// structure the error occurred. The list is ordered from least specific (outermost)
/// to most specific (innermost), providing a "stack trace" through the parsing
/// process.
///
/// ## Examples
///
/// ```gleam
/// case decode(malformed_bytes) {
///   Error(ParseFailed(err)) -> {
///     let ctx = parse_error_ctx(err)
///     // ctx: [InTransaction, InInputs, AtInput(2), AtField(ScriptSigLength)]
///     // Means: error in the scriptSig_len field of input #2
///   }
///   _ -> // ...
/// }
/// ```
pub fn parse_error_ctx(err: ParseError) -> List(ParseContext) {
  err.ctx
}

fn new_parse_error(kind: ParseErrorKind, offset: Int) -> ParseError {
  ParseError(offset:, kind:, ctx: [])
}

fn with_contexts(err: ParseError, ctxs: List(ParseContext)) -> ParseError {
  list.fold(ctxs, err, fn(err, ctx) { ParseError(..err, ctx: [ctx, ..err.ctx]) })
}

/// Build a DecodeError factory function for a specific field at a given offset.
///
/// Returns a function that takes a ParseErrorKind and produces a DecodeError
/// with the field context already applied. The offset parameter allows you to
/// point the error to a specific byte location, such as the start of a field,
/// rather than the current reader position.
fn make_field_error(
  field: Field,
  offset: Int,
  ctx: List(ParseContext),
) -> fn(ParseErrorKind) -> DecodeError {
  fn(kind) {
    kind
    |> new_parse_error(offset)
    |> with_contexts([AtField(field), ..ctx])
    |> ParseFailed
  }
}

/// Maps an internal `ReaderError` to a public `ParseErrorKind`.
///
/// `InvalidReadCount` is an internal invariant violation (a library bug) and
/// is never triggered by user-supplied data, so it is treated as a panic.
fn reader_error_to_kind(err: reader.ReaderError) -> ParseErrorKind {
  case err {
    reader.InvalidReadCount(i) ->
      panic as {
        "tried to read an invalid number of bytes: " <> int.to_string(i) <> "."
      }

    reader.UnexpectedEof(bytes_needed:, remaining:) ->
      UnexpectedEof(bytes_needed:, remaining:)
  }
}

// ==============================================================================
// Decoding
// ==============================================================================

/// Configuration policy for transaction decoding limits.
///
/// This type controls resource constraints during transaction parsing to protect
/// against malicious inputs that could cause excessive memory allocation or
/// processing time. All limits are enforced during parsing, failing with
/// `PolicyLimitExceeded` if exceeded.
///
/// ## See Also
///
/// - `default_policy` for the standard parsing limits
/// - `decode_with_policy` to apply a custom policy
pub type DecodePolicy {
  DecodePolicy(
    /// Maximum number of transaction inputs allowed. Exceeding
    /// this causes the parser to reject the transaction before allocating memory
    /// for the inputs.
    max_vin_count: Int,
    /// Maximum number of transaction outputs allowed. Exceeding
    /// this causes the parser to reject the transaction before allocating memory
    /// for the outputs.
    max_vout_count: Int,
    /// Maximum size in bytes for any individual script (both
    /// input scriptSig and output scriptPubKey). This prevents unbounded memory
    /// allocation when reading scripts.
    max_script_size: Int,
    /// Policy controlling witness data parsing limits. Only
    /// applied to SegWit transactions.
    witness_policy: WitnessPolicy,
  )
}

/// Configuration policy for SegWit witness data parsing limits.
///
/// This type controls resource constraints when parsing witness stacks in SegWit
/// transactions. Witness data can be arbitrarily large in the general case, so
/// these limits protect against resource exhaustion.
pub type WitnessPolicy {
  WitnessPolicy(
    /// Maximum size in bytes for any individual witness stack
    /// item. Standard transactions typically use items under 80 bytes (e.g.,
    /// signatures and public keys), but larger items are consensus-valid.
    max_item_size: Int,
    /// Maximum number of witness stack items allowed for
    /// any single input. Complex scripts may require many stack items.
    max_items_per_input: Int,
    /// Maximum total bytes across all witness
    /// items for a single input. This provides a cap on total witness data per
    /// input, even if individual items are small.
    max_stack_payload_bytes_per_input: Int,
  )
}

/// The default witness data parsing policy.
///
/// This policy provides reasonable limits for witness data in SegWit transactions,
/// balancing protection against resource exhaustion with support for legitimate
/// use cases. These limits are applied automatically when using `decode` or
/// `decode_hex`.
///
/// ## Default Values
/// 
/// - `max_item_size`: 100 bytes - Accommodates standard witness items like
///   signatures (~72 bytes) and public keys (~33 bytes), with room for slightly
///   larger items.
/// - `max_items_per_input`: 10,000 items - Allows complex scripts while preventing
///   unbounded memory allocation.
/// - `max_stack_payload_bytes_per_input`: 100,000 bytes - Caps total witness data
///   per input, protecting against excessive witness payloads.
pub const default_witness_policy = WitnessPolicy(
  max_item_size: 100,
  max_items_per_input: 10_000,
  max_stack_payload_bytes_per_input: 100_000,
)

/// The default transaction parsing policy.
///
/// This policy provides reasonable resource limits for transaction decoding that
/// protect against malicious inputs while supporting legitimate Bitcoin transactions.
/// These limits are applied automatically when using `decode` or `decode_hex`.
///
/// ## Default Values
///
/// - `max_vin_count`: 100,000 inputs - Substantially higher than typical transactions
///   (which usually have 1-10 inputs) but prevents unbounded memory allocation.
/// - `max_vout_count`: 100,000 outputs - Similarly generous for outputs.
/// - `max_script_size`: 10,000 bytes - Accommodates standard scripts (typically
///   25-35 bytes for P2PKH/P2WPKH, ~34 bytes for P2SH) with significant headroom
///   for complex or non-standard scripts.
/// - `witness_policy`: Uses `default_witness_policy` for SegWit witness data.
pub const default_policy = DecodePolicy(
  max_vin_count: 100_000,
  max_vout_count: 100_000,
  max_script_size: 10_000,
  witness_policy: default_witness_policy,
)

/// Decode a Bitcoin transaction from its binary representation.
///
/// This is the standard entry point for parsing Bitcoin transaction data
/// serialized in the Bitcoin network protocol format. It automatically detects
/// whether the transaction is legacy or SegWit by inspecting the marker bytes.
///
/// This function applies `default_policy` to protect against malicious inputs
/// by enforcing reasonable limits on input/output counts, script
/// sizes, and witness data.
/// 
/// For custom parsing limits, use `decode_with_policy` instead.
///
/// The decoded transaction is marked as `Unvalidated`, meaning it has been
/// successfully parsed but has not been checked against Bitcoin consensus rules.
///
/// ## Returns
///
/// - `Ok(Transaction(Unvalidated))`: Successfully decoded transaction.
/// - `Error(DecodeError)`: The bytes could not be parsed as a valid transaction.
///   This includes malformed data, unexpected end of input, or violations of
///   the policy limits.
///
/// ## Examples
///
/// ```gleam
/// let tx_bytes = <<0x01, 0x00, 0x00, 0x00, ...>>
/// case decode(tx_bytes) {
///   Ok(tx) -> // Transaction successfully parsed
///   Error(ParseFailed(err)) -> // Handle parse error
///   Error(HexToBytesFailed(err)) -> // Won't occur with direct bytes
/// }
/// ```
pub fn decode(bytes: BitArray) -> Result(Transaction(Unvalidated), DecodeError) {
  decode_with_policy(bytes, default_policy)
}

/// Decode a Bitcoin transaction with custom parsing limits.
///
/// This function provides fine-grained control over the parser's resource limits
/// when decoding transaction data. Use this when you need different constraints
/// than `default_policy`, such as when processing known-safe data, implementing
/// strict validation, or defending against resource exhaustion attacks.
///
/// The policy controls maximum values for:
/// - Input count (`max_vin_count`)
/// - Output count (`max_vout_count`)
/// - Script sizes (`max_script_size`)
/// - Witness data (`witness_policy` controls item size, item count, and total bytes)
///
/// When a transaction exceeds these limits, decoding fails with a
/// `PolicyLimitExceeded` error rather than consuming excessive resources.
///
/// ## Returns
///
/// - `Ok(Transaction(Unvalidated))`: Successfully decoded transaction within policy limits.
/// - `Error(DecodeError)`: The bytes could not be parsed or exceeded policy limits.
///
/// ## Examples
///
/// ```gleam
/// // Strict policy for untrusted input
/// let strict_policy = DecodePolicy(
///   max_vin_count: 100,
///   max_vout_count: 100,
///   max_script_size: 1_000,
///   witness_policy: WitnessPolicy(
///     max_item_size: 80,
///     max_items_per_input: 100,
///     max_stack_payload_bytes_per_input: 10_000,
///   ),
/// )
///
/// case decode_with_policy(untrusted_bytes, strict_policy) {
///   Ok(tx) -> // Transaction parsed and within limits
///   Error(ParseFailed(err)) -> // Parse error or limit exceeded
///   Error(HexToBytesFailed(_)) -> // Not possible with BitArray input
/// }
/// ```
pub fn decode_with_policy(
  bytes: BitArray,
  policy: DecodePolicy,
) -> Result(Transaction(Unvalidated), DecodeError) {
  let tx_parser = {
    use version <- parser.then(read_field(Version, reader.read_i32_le))
    use is_segwit <- parser.then(detect_segwit())
    use inputs <- parser.then(parser.with_context(
      read_inputs(policy.max_vin_count, policy.max_script_size),
      InInputs,
    ))
    use outputs <- parser.then(parser.with_context(
      read_outputs(policy.max_vout_count, policy.max_script_size),
      InOutputs,
    ))
    use witnesses <- parser.then(case is_segwit {
      True ->
        list.length(inputs)
        |> read_witnesses(policy.witness_policy)
        |> parser.map(Some)

      False -> parser.return(None)
    })
    use lock_time <- parser.then(read_field(LockTime, reader.read_u32_le))

    parser.try_with_reader(parser.return(Nil), fn(_, reader, ctx) {
      let tx = case witnesses {
        Some(witnesses) ->
          SegWit(version:, inputs:, outputs:, lock_time:, witnesses:)

        None -> Legacy(version:, inputs:, outputs:, lock_time:)
      }

      case reader.bytes_remaining(reader) {
        0 -> Ok(tx)

        byte_count ->
          byte_count
          |> TrailingBytes
          |> new_parse_error(reader.get_offset(reader))
          |> with_contexts(ctx)
          |> ParseFailed
          |> Error
      }
    })
  }

  bytes
  |> reader.new
  |> parser.run(tx_parser, _, [InTransaction])
  |> result.map(pair.second)
}

/// Decode a Bitcoin transaction from its hexadecimal string representation.
///
/// This is a convenience function that combines hex-to-bytes conversion with
/// transaction decoding. It's useful when working with transaction data in
/// hexadecimal format, such as from block explorers, RPC responses, or test
/// vectors.
///
/// This function applies `default_policy` for parsing limits.
/// For custom parsing limits, use `decode_with_policy` instead.
///
/// ## Returns
///
/// - `Ok(Transaction(Unvalidated))`: Successfully decoded transaction.
/// - `Error(HexToBytesFailed(_))`: The hex string was invalid (odd length or
///   invalid characters).
/// - `Error(ParseFailed(_))`: The bytes could not be parsed as a valid transaction.
///
/// ## Examples
///
/// ```gleam
/// let hex = "0100000001..."
/// case decode_hex(hex) {
///   Ok(tx) -> // Transaction successfully parsed
///   Error(HexToBytesFailed(err)) -> // Invalid hex string
///   Error(ParseFailed(err)) -> // Valid hex but invalid transaction
/// }
/// ```
pub fn decode_hex(hex: String) -> Result(Transaction(Unvalidated), DecodeError) {
  hex
  |> hex_to_bytes
  |> result.try(decode)
}

/// Decode a Bitcoin transaction from hexadecimal with custom parsing limits.
///
/// This function combines hex-to-bytes conversion with policy-based transaction
/// parsing, providing both the convenience of hexadecimal input and fine-grained
/// control over resource limits. Use this when working with hex-encoded transaction
/// data that requires custom parsing constraints.
///
/// ## Returns
///
/// - `Ok(Transaction(Unvalidated))`: Successfully decoded transaction within policy limits.
/// - `Error(HexToBytesFailed(_))`: The hex string was invalid (odd length or
///   invalid characters).
/// - `Error(ParseFailed(_))`: The bytes could not be parsed or exceeded policy limits.
pub fn decode_hex_with_policy(
  hex: String,
  policy: DecodePolicy,
) -> Result(Transaction(Unvalidated), DecodeError) {
  hex
  |> hex_to_bytes
  |> result.try(decode_with_policy(_, policy))
}

fn hex_to_bytes(hex: String) -> Result(BitArray, DecodeError) {
  hex
  |> bit_array.base16_decode
  |> result.replace_error(HexToBytesFailed)
}

/// Lift a reader operation into a Parser, adding error mapping and context wrapping.
fn read_field(
  field: Field,
  read_fn: fn(Reader) -> Result(#(Reader, a), reader.ReaderError),
) -> Parser(ParseContext, a, DecodeError) {
  parser.new(fn(reader, ctx) {
    reader
    |> read_fn
    |> result.map_error(fn(err) {
      err
      |> reader_error_to_kind
      |> make_field_error(field, reader.get_offset(reader), ctx)
    })
  })
}

/// Lift a compact_size read into a Parser, adding error mapping and context wrapping.
fn read_compact_size(field: Field) -> Parser(ParseContext, Uint64, DecodeError) {
  parser.new(fn(reader, ctx) {
    reader
    |> compact_size.read
    |> result.map_error(fn(err) {
      case err {
        compact_size.ReaderError(re) -> reader_error_to_kind(re)
        compact_size.NonMinimalCompactSize(encoded:, value:) ->
          NonMinimalCompactSize(encoded:, value:)
      }
      |> make_field_error(field, reader.get_offset(reader), ctx)
    })
  })
}

/// Read a CompactSize value and convert it to `Int` with appropriate error handling.
///
/// This wraps `read_compact_size` and handles the common pattern of converting
/// the `Uint64` result to `Int`, mapping conversion failures to `IntegerOutOfRange` errors.
fn read_compact_size_as_int(
  field: Field,
) -> Parser(ParseContext, Int, DecodeError) {
  field
  |> read_compact_size
  |> parser.try_with_start_offset(fn(value_u64, start_offset, _, ctx) {
    value_u64
    |> uint64.to_int
    |> result.map_error(fn(_) {
      value_u64
      |> uint64.to_string
      |> IntegerOutOfRange
      |> make_field_error(field, start_offset, ctx)
    })
  })
}

/// Detect whether this transaction uses SegWit format by peeking at the marker/flag bytes.
///
/// Returns `True` if the marker/flag bytes (0x00, 0x01) are present, `False` otherwise.
/// Side effect: consumes the marker/flag bytes if present.
fn detect_segwit() -> Parser(ParseContext, Bool, DecodeError) {
  peek_segwit()
  |> parser.then(fn(is_segwit) {
    case is_segwit {
      True ->
        is_segwit
        |> parser.return
        |> parser.keep_left(skip_marker_bytes())

      False -> parser.return(is_segwit)
    }
  })
}

/// Peek ahead at the next two bytes to check for SegWit marker/flag.
///
/// Returns `True` if next bytes are 0x00 0x01 (SegWit marker/flag), `False` if they don't
/// start with 0x00 or on EOF. Returns an error if the first byte is 0x00 but the flag
/// byte is invalid.
fn peek_segwit() -> Parser(ParseContext, Bool, DecodeError) {
  // Uses `parser.new` directly due to special peek semantics and EOF error recovery.
  parser.new(fn(reader, ctx) {
    let field_err =
      make_field_error(SegwitDiscriminator, reader.get_offset(reader), ctx)

    case reader.peek_bytes(reader, 2) {
      Ok(bytes) -> {
        let assert <<marker, flag>> = bytes
        case marker, flag {
          0x00, 0x01 -> Ok(#(reader, True))
          0x00, _ ->
            InvalidSegWitMarkerFlag(marker, flag)
            |> field_err
            |> Error
          _, _ -> Ok(#(reader, False))
        }
      }

      Error(err) -> {
        // Panic on InvalidReadCount (library bug); silently treat UnexpectedEof
        // as non-SegWit. We can't peek, so we fall through and let the
        // subsequent field parsers produce a more contextual EOF error.
        let _ = reader_error_to_kind(err)
        Ok(#(reader, False))
      }
    }
  })
}

/// Helper parser that consumes the 2-byte segwit discriminator
fn skip_marker_bytes() -> Parser(ParseContext, Nil, DecodeError) {
  read_field(SegwitMarker, fn(reader) {
    reader
    |> reader.skip_bytes(2)
    |> result.map(pair.new(_, Nil))
  })
}

fn read_inputs(
  max_vin_count_policy: Int,
  max_script_size_policy: Int,
) -> Parser(ParseContext, List(TxIn), DecodeError) {
  max_vin_count_policy
  |> read_vin_count
  |> parser.then(read_tx_ins(_, max_script_size_policy))
}

/// Validate and convert the vin_count from Uint64 to Int, checking structural and policy limits.
fn read_vin_count(
  max_vin_count_policy: Int,
) -> Parser(ParseContext, Int, DecodeError) {
  VinCount
  |> read_compact_size_as_int
  |> parser.try_with_start_offset(fn(vin_count_int, start_offset, reader, ctx) {
    let on_invalid = fn(kind) {
      kind
      |> make_field_error(VinCount, start_offset, ctx)
      |> Error
    }
    validate_vin_count(vin_count_int, reader, max_vin_count_policy, on_invalid)
  })
}

fn validate_vin_count(
  vin_count_int: Int,
  reader: Reader,
  max_vin_count_policy: Int,
  on_invalid: fn(ParseErrorKind) -> Result(Int, DecodeError),
) -> Result(Int, DecodeError) {
  let min_txin_size = 41
  let remaining = reader.bytes_remaining(reader)
  // Upper bound implied by remaining bytes (each input is at least 41 bytes)
  let max_inputs_by_bytes = remaining / min_txin_size

  case
    vin_count_int > max_inputs_by_bytes,
    vin_count_int > max_vin_count_policy
  {
    // Structural limit: count exceeds what remaining bytes can accommodate
    True, _ ->
      InsufficientBytes(claimed: remaining + 1, remaining:)
      |> on_invalid

    // Policy limit: count exceeds configured maximum
    _, True ->
      PolicyLimitExceeded(vin_count_int, max_vin_count_policy)
      |> on_invalid

    _, _ -> Ok(vin_count_int)
  }
}

fn read_tx_ins(
  vin_count: Int,
  max_script_size_policy: Int,
) -> Parser(ParseContext, List(TxIn), DecodeError) {
  // vin_count
  // ├─ TxIn #0
  // │    ├─ prev_txid (32 bytes)
  // │    ├─ vout (4 bytes)
  // │    ├─ scriptSig_len (CompactSize)
  // │    ├─ scriptSig bytes
  // │    └─ sequence (4 bytes)
  // ├─ TxIn #1
  // │    ├─ ...
  // └─ TxIn #(vin_count - 1)
  parser.indexed_repeat(vin_count, read_tx_in(max_script_size_policy), AtInput)
}

fn read_tx_in(
  max_script_size_policy: Int,
) -> Parser(ParseContext, TxIn, DecodeError) {
  // │ prev_txid (32 bytes)
  // │ vout (4 bytes)
  // │ scriptSig_len (CompactSize)
  // │ scriptSig bytes
  // │ sequence (4 bytes)
  parser.map3(
    read_prev_out(),
    read_script_sig(max_script_size_policy),
    read_field(Sequence, reader.read_u32_le),
    TxIn,
  )
}

fn read_prev_out() -> Parser(ParseContext, PrevOut, DecodeError) {
  parser.map2(
    read_field(PrevTxId, reader.read_bytes(_, 32)),
    read_field(Vout, reader.read_u32_le),
    fn(prev_txid_bytes, vout) {
      case prev_txid_bytes, vout {
        <<0:256>>, 0xFFFFFFFF -> NullOutPoint

        _, _ -> {
          // Safe: read_bytes(_, 32) guarantees exactly 32 bytes on success
          let assert Ok(hash32) = hash32.from_bytes_le(prev_txid_bytes)
          OutPoint(hash32, vout)
        }
      }
    },
  )
}

fn read_outputs(
  max_vout_count_policy: Int,
  max_script_size_policy: Int,
) -> Parser(ParseContext, List(TxOut), DecodeError) {
  max_vout_count_policy
  |> read_vout_count
  |> parser.then(read_tx_outs(_, max_script_size_policy))
}

/// Validate and convert the vout_count from Uint64 to Int, checking structural and policy limits.
fn read_vout_count(
  max_vout_count_policy: Int,
) -> Parser(ParseContext, Int, DecodeError) {
  VoutCount
  |> read_compact_size_as_int
  |> parser.try_with_start_offset(fn(vout_count_int, start_offset, reader, ctx) {
    let on_invalid = fn(kind) {
      kind
      |> make_field_error(VoutCount, start_offset, ctx)
      |> Error
    }
    validate_vout_count(
      vout_count_int,
      reader,
      max_vout_count_policy,
      on_invalid,
    )
  })
}

fn validate_vout_count(
  vout_count_int: Int,
  reader: Reader,
  max_vout_count_policy: Int,
  on_invalid: fn(ParseErrorKind) -> Result(Int, DecodeError),
) -> Result(Int, DecodeError) {
  let min_txout_size = 9
  let remaining = reader.bytes_remaining(reader)
  // Upper bound implied by remaining bytes (each output is at least 9 bytes)
  let max_outputs_by_bytes = remaining / min_txout_size

  case
    vout_count_int > max_outputs_by_bytes,
    vout_count_int > max_vout_count_policy
  {
    // Structural limit: count exceeds what remaining bytes can accommodate
    True, _ ->
      InsufficientBytes(claimed: remaining + 1, remaining:)
      |> on_invalid

    // Policy limit: count exceeds configured maximum
    _, True ->
      PolicyLimitExceeded(vout_count_int, max_vout_count_policy)
      |> on_invalid

    _, _ -> Ok(vout_count_int)
  }
}

fn read_tx_outs(
  vout_count: Int,
  max_script_size_policy: Int,
) -> Parser(ParseContext, List(TxOut), DecodeError) {
  // vout_count
  // ├─ TxOut #0
  // │    ├─ value (8 bytes)
  // │    ├─ scriptPubKey_len (CompactSize)
  // │    └─ scriptPubKey bytes
  // ├─ TxOut #1
  // │    ├─ ...
  // └─ TxOut #(vout_count - 1)
  parser.indexed_repeat(
    vout_count,
    read_tx_out(max_script_size_policy),
    AtOutput,
  )
}

fn read_tx_out(
  max_script_size_policy: Int,
) -> Parser(ParseContext, TxOut, DecodeError) {
  // | value (8 bytes)
  // | scriptPubKey_len (CompactSize)
  // | scriptPubKey bytes
  parser.map2(
    read_satoshis(),
    read_script_pubkey(max_script_size_policy),
    TxOut,
  )
}

fn read_satoshis() -> Parser(ParseContext, Int, DecodeError) {
  Value
  |> read_field(reader.read_bytes(_, 8))
  |> parser.map(fn(value_bytes) {
    let assert Ok(value_i64) = int64.from_bytes_le(value_bytes)
    value_i64
  })
  |> parser.try_with_start_offset(fn(value_i64, start_offset, _, ctx) {
    // This should never happen.
    // The max possible amount of satoshis 2_100_000_000_000_000 (2.1 quadrillion)
    // is less than JavaScript's Number.MAX_SAFE_INTEGER
    value_i64
    |> int64.to_int
    |> result.map_error(fn(_) {
      value_i64
      |> int64.to_string
      |> IntegerOutOfRange
      |> make_field_error(Value, start_offset, ctx)
    })
  })
}

fn read_script_sig(
  max_script_size_policy: Int,
) -> Parser(ParseContext, ScriptBytes(InputScript), DecodeError) {
  ScriptSigLength
  |> read_script_length(max_script_size_policy)
  |> parser.then(fn(script_len) {
    read_field(ScriptSig, reader.read_bytes(_, script_len))
  })
  |> parser.map(ScriptBytes)
}

fn read_script_pubkey(
  max_script_size_policy: Int,
) -> Parser(ParseContext, ScriptBytes(OutputScript), DecodeError) {
  ScriptPubKeyLength
  |> read_script_length(max_script_size_policy)
  |> parser.then(fn(script_len) {
    read_field(ScriptPubKey, reader.read_bytes(_, script_len))
  })
  |> parser.map(ScriptBytes)
}

/// Read and validate a script length field.
///
/// Reads a CompactSize length, converts it to Int, validates it against
/// max_script_size_policy, and ensures sufficient bytes remain.
fn read_script_length(
  field: Field,
  max_script_size_policy: Int,
) -> Parser(ParseContext, Int, DecodeError) {
  field
  |> read_compact_size_as_int
  |> parser.try_with_start_offset(fn(script_len_int, start_offset, reader, ctx) {
    let on_invalid = fn(kind) {
      kind
      |> make_field_error(field, start_offset, ctx)
      |> Error
    }
    validate_script_length(
      script_len_int,
      reader,
      max_script_size_policy,
      on_invalid,
    )
  })
}

fn validate_script_length(
  script_len_int: Int,
  reader: Reader,
  max_script_size_policy: Int,
  on_invalid: fn(ParseErrorKind) -> Result(Int, DecodeError),
) -> Result(Int, DecodeError) {
  let remaining = reader.bytes_remaining(reader)

  case script_len_int > remaining, script_len_int > max_script_size_policy {
    // Structural limit: length exceeds remaining bytes
    True, _ ->
      InsufficientBytes(claimed: script_len_int, remaining:)
      |> on_invalid

    // Policy limit: length exceeds configured maximum
    _, True ->
      PolicyLimitExceeded(script_len_int, max_script_size_policy)
      |> on_invalid

    _, _ -> Ok(script_len_int)
  }
}

fn read_witnesses(
  vin_count: Int,
  policy: WitnessPolicy,
) -> Parser(ParseContext, List(WitnessStack), DecodeError) {
  parser.indexed_repeat(vin_count, read_witness(policy), AtWitnessStack)
}

fn read_witness(
  policy: WitnessPolicy,
) -> Parser(ParseContext, WitnessStack, DecodeError) {
  // WitnessStack for one input:
  // ├─ stack_len (CompactSize) - number of witness items
  // ├─ WitnessItem #0
  // │    ├─ item_len (CompactSize)
  // │    └─ item bytes
  // ├─ WitnessItem #1
  // │    ├─ ...
  // └─ WitnessItem #(stack_len - 1)
  policy.max_items_per_input
  |> read_witness_stack_length
  |> parser.then(fn(stack_len) {
    read_witness_items_with_byte_tracking(
      stack_len,
      policy.max_item_size,
      policy.max_stack_payload_bytes_per_input,
    )
  })
  |> parser.map(WitnessStack)
}

/// Read and validate a witness stack length field.
///
/// Reads a CompactSize length, converts it to Int, and validates it against
/// max_items_per_input policy.
fn read_witness_stack_length(
  max_items_per_input_policy: Int,
) -> Parser(ParseContext, Int, DecodeError) {
  WitnessStackLength
  |> read_compact_size_as_int
  |> parser.try_with_start_offset(fn(stack_len, start_offset, _, ctx) {
    let on_invalid = fn(kind) {
      kind
      |> make_field_error(WitnessStackLength, start_offset, ctx)
      |> Error
    }
    validate_witness_stack_length(
      stack_len,
      max_items_per_input_policy,
      on_invalid,
    )
  })
}

fn validate_witness_stack_length(
  stack_len: Int,
  max_items_per_input_policy: Int,
  on_invalid: fn(ParseErrorKind) -> Result(Int, DecodeError),
) -> Result(Int, DecodeError) {
  case stack_len > max_items_per_input_policy {
    True ->
      PolicyLimitExceeded(stack_len, max_items_per_input_policy)
      |> on_invalid

    False -> Ok(stack_len)
  }
}

/// Read witness items while tracking cumulative payload bytes and failing fast
/// if the total exceeds max_stack_payload_bytes_per_input.
fn read_witness_items_with_byte_tracking(
  count: Int,
  max_item_size: Int,
  max_total_bytes: Int,
) -> Parser(ParseContext, List(WitnessItem), DecodeError) {
  parser.indexed_repeat_with_limit(
    count,
    read_witness_item_with_size(max_item_size),
    AtWitnessItem,
    max_total_bytes,
    fn(exceeded_val, start_offset, ctx) {
      PolicyLimitExceeded(exceeded_val, max_total_bytes)
      |> make_field_error(WitnessStackTotalPayloadBytes, start_offset, ctx)
    },
  )
}

/// Read a witness item and return it along with its byte size.
fn read_witness_item_with_size(
  max_item_size: Int,
) -> Parser(ParseContext, #(WitnessItem, Int), DecodeError) {
  max_item_size
  |> read_witness_item
  |> parser.map(fn(item) {
    let WitnessItem(bytes) = item
    let byte_size = bit_array.byte_size(bytes)
    #(item, byte_size)
  })
}

fn read_witness_item(
  max_item_size_policy: Int,
) -> Parser(ParseContext, WitnessItem, DecodeError) {
  max_item_size_policy
  |> read_witness_item_size
  |> parser.then(fn(length) {
    parser.new(fn(reader, ctx) {
      reader
      |> reader.read_bytes(length)
      |> result.map_error(fn(err) {
        err
        |> reader_error_to_kind
        |> new_parse_error(reader.get_offset(reader))
        |> with_contexts(ctx)
        |> ParseFailed
      })
    })
  })
  |> parser.map(WitnessItem)
}

fn read_witness_item_size(
  max_item_size_policy: Int,
) -> Parser(ParseContext, Int, DecodeError) {
  WitnessItemLength
  |> read_compact_size_as_int
  |> parser.try_with_start_offset(fn(length, start_offset, reader, ctx) {
    let on_invalid = fn(kind) {
      kind
      |> make_field_error(WitnessItemLength, start_offset, ctx)
      |> Error
    }
    validate_witness_item_size(length, reader, max_item_size_policy, on_invalid)
  })
}

fn validate_witness_item_size(
  length: Int,
  reader: Reader,
  max_item_size_policy: Int,
  on_invalid: fn(ParseErrorKind) -> Result(Int, DecodeError),
) -> Result(Int, DecodeError) {
  let remaining = reader.bytes_remaining(reader)

  case length > remaining, length > max_item_size_policy {
    // Structural limit: length exceeds remaining bytes
    True, _ ->
      InsufficientBytes(claimed: length, remaining:)
      |> on_invalid

    // Policy limit: length exceeds configured maximum
    _, True ->
      PolicyLimitExceeded(length, max_item_size_policy)
      |> on_invalid

    _, _ -> Ok(length)
  }
}

// ==============================================================================
// Consensus Validation
// ==============================================================================

/// An error that occurred during consensus validation of a Bitcoin transaction.
///
/// These errors represent violations of Bitcoin's consensus rules that would
/// cause a transaction to be rejected by the network.
pub type ValidationError {
  /// The transaction has no inputs.
  ///
  /// Every Bitcoin transaction must contain at least one input.
  /// Transactions with zero inputs are invalid under consensus rules.
  NoInputs

  /// The transaction has no outputs.
  ///
  /// Every Bitcoin transaction must contain at least one output.
  /// Transactions with zero outputs are invalid under consensus rules.
  NoOutputs

  /// An output value is outside the valid money range.
  ///
  /// Consensus requires each output value to satisfy:
  ///
  ///     0 <= value <= MAX_MONEY
  ///
  /// where MAX_MONEY is 21,000,000 BTC expressed in satoshis.
  ///
  /// The `index` field indicates the zero-based position of the output,
  /// and `value` is the invalid amount.
  OutputValueOutOfRange(index: Int, value: Int)

  /// The cumulative sum of output values exceeds the valid money range.
  ///
  /// During validation, Bitcoin nodes maintain a running total of all
  /// output values and require that the cumulative sum never exceed MAX_MONEY.
  ///
  /// The `index` field indicates the zero-based position of the output
  /// at which the running total first exceeded MAX_MONEY.
  ///
  /// The `total` field is the cumulative output value at that point.
  TotalOutputValueOutOfRange(index: Int, total: Int)

  /// A transaction identified as a coinbase transaction contains
  /// more than one input.
  ///
  /// A coinbase transaction is defined as a transaction whose single
  /// input has a null prevout. Under consensus rules, such a transaction
  /// must contain exactly one input.
  CoinbaseWithMultipleInputs

  /// A coinbase transaction's scriptSig length is invalid.
  ///
  /// Coinbase scriptSig must be between 2 and 100 bytes (inclusive).
  InvalidCoinbaseScriptSigLength
}

/// Validate a transaction against selected Bitcoin consensus rules.
///
/// This function performs structural and monetary checks that are
/// required for a transaction to be considered valid by fully
/// validating Bitcoin nodes.
///
/// The following consensus rules are enforced:
///
///   - At least one input
///   - At least one output
///   - Output values satisfy MoneyRange (0 <= value <= MAX_MONEY)
///   - Cumulative output value does not exceed MAX_MONEY
///   - Coinbase transactions contain exactly one input
///   - Coinbase scriptSig length is 2–100 bytes (inclusive)
///
/// This function does not perform script execution, signature
/// verification, or input-spend validation.
pub fn validate_consensus(
  tx: Transaction(Unvalidated),
) -> Result(Transaction(Validated), List(ValidationError)) {
  let validators = [
    validate_at_least_one_input,
    validate_at_least_one_output,
    validate_output_values,
    validate_coinbase_structure,
    validate_coinbase_script_sig_length,
  ]

  let errors =
    list.filter_map(validators, fn(validator) {
      case validator(tx) {
        Ok(_) -> Error(Nil)
        Error(err) -> Ok(err)
      }
    })

  case errors {
    [] ->
      // Change phantom type to Validated by reconstructing with identical data
      Ok(case tx {
        Legacy(v, i, o, l) -> Legacy(v, i, o, l)
        SegWit(v, i, o, l, w) -> SegWit(v, i, o, l, w)
      })

    _ -> Error(errors)
  }
}

fn validate_at_least_one_input(
  tx: Transaction(Unvalidated),
) -> Result(Nil, ValidationError) {
  case tx.inputs {
    [] -> Error(NoInputs)
    _ -> Ok(Nil)
  }
}

fn validate_at_least_one_output(
  tx: Transaction(Unvalidated),
) -> Result(Nil, ValidationError) {
  case tx.outputs {
    [] -> Error(NoOutputs)
    _ -> Ok(Nil)
  }
}

fn validate_output_values(
  tx: Transaction(Unvalidated),
) -> Result(Nil, ValidationError) {
  // 2.1 quadrillion (21_000_000 Bitcoins * 100_000_000 Satoshis in a Bitcoin)
  let max_satoshis = 21_000_000 * 100_000_000
  validate_output_values_loop(tx.outputs, 0, 0, max_satoshis)
}

fn validate_output_values_loop(
  outputs: List(TxOut),
  index: Int,
  sum: Int,
  max_satoshis: Int,
) -> Result(Nil, ValidationError) {
  case outputs {
    [] -> Ok(Nil)

    [output, ..rest] ->
      case output.value {
        v if v < 0 -> Error(OutputValueOutOfRange(index, v))
        v if v > max_satoshis -> Error(OutputValueOutOfRange(index, v))
        v -> {
          let sum = sum + v
          case sum > max_satoshis {
            True -> Error(TotalOutputValueOutOfRange(index, sum))
            False ->
              validate_output_values_loop(rest, index + 1, sum, max_satoshis)
          }
        }
      }
  }
}

fn validate_coinbase_structure(
  tx: Transaction(Unvalidated),
) -> Result(Nil, ValidationError) {
  case has_coinbase_marker(tx) {
    True ->
      case tx.inputs {
        [_] -> Ok(Nil)
        _ -> Error(CoinbaseWithMultipleInputs)
      }
    False -> Ok(Nil)
  }
}

fn validate_coinbase_script_sig_length(
  tx: Transaction(Unvalidated),
) -> Result(Nil, ValidationError) {
  case tx.inputs {
    [] -> Ok(Nil)

    [input] ->
      case prev_out_is_coinbase_marker(input.prev_out) {
        True -> {
          let script_len = get_script_length(input.script_sig)
          case 2 <= script_len && script_len <= 100 {
            True -> Ok(Nil)
            False -> Error(InvalidCoinbaseScriptSigLength)
          }
        }

        False -> Ok(Nil)
      }

    _ -> Ok(Nil)
  }
}

// ==============================================================================
// Serialization
// ==============================================================================

/// Compute the transaction identifier (txid) for a validated transaction.
///
/// Returns the 32 bytes of the txid in little-endian byte order, as they
/// appear in Bitcoin transactions and on the wire.
///
/// **Requires validation**: Accepts only `Transaction(Validated)` to ensure
/// the transaction has passed consensus checks via `validate_consensus`.
pub fn compute_txid(tx: Transaction(Validated)) -> BitArray {
  // safe: input/output counts are non-negative Ints parsed from the wire,
  // so they fit within Uint64 (and within JS safe integer bounds)
  let assert Ok(vin_count) = uint64.from_int(list.length(tx.inputs))
  let assert Ok(vout_count) = uint64.from_int(list.length(tx.outputs))

  let assert <<_:256-bits>> =
    dsha256(<<
      tx.version:32-little,
      compact_size.write(vin_count):bits,
      serialize_inputs(tx.inputs):bits,
      compact_size.write(vout_count):bits,
      serialize_outputs(tx.outputs):bits,
      tx.lock_time:32-little,
    >>)
}

/// Compute the witness transaction identifier (wtxid) for a validated transaction.
///
/// Returns the 32 bytes of the wtxid in little-endian byte order, as they
/// appear in Bitcoin transactions and on the wire. For legacy transactions,
/// the wtxid is identical to the txid.
///
/// **Requires validation**: Accepts only `Transaction(Validated)` to ensure
/// the transaction has passed consensus checks via `validate_consensus`.
pub fn compute_wtxid(tx: Transaction(Validated)) -> BitArray {
  // safe: input/output counts are non-negative Ints parsed from the wire,
  // so they fit within Uint64 (and within JS safe integer bounds)
  let assert Ok(vin_count) = uint64.from_int(list.length(tx.inputs))
  let assert Ok(vout_count) = uint64.from_int(list.length(tx.outputs))

  let #(segwit_discriminator, witnesses) = case tx {
    Legacy(..) -> #(<<>>, <<>>)
    SegWit(witnesses:, ..) -> #(<<0x00, 0x01>>, serialize_witnesses(witnesses))
  }

  let assert <<_:256-bits>> =
    dsha256(<<
      tx.version:32-little,
      segwit_discriminator:bits,
      compact_size.write(vin_count):bits,
      serialize_inputs(tx.inputs):bits,
      compact_size.write(vout_count):bits,
      serialize_outputs(tx.outputs):bits,
      witnesses:bits,
      tx.lock_time:32-little,
    >>)
}

fn serialize_inputs(inputs: List(TxIn)) -> BitArray {
  inputs
  |> list.map(serialize_tx_in)
  |> bit_array.concat
}

fn serialize_tx_in(txin: TxIn) -> BitArray {
  let prev_out_bytes = serialize_prev_out(txin.prev_out)

  let script_sig_len_bytes = {
    let assert Ok(len_u64) =
      txin.script_sig
      |> get_script_length
      |> uint64.from_int

    compact_size.write(len_u64)
  }

  <<
    prev_out_bytes:bits,
    script_sig_len_bytes:bits,
    get_raw_script_bytes(txin.script_sig):bits,
    txin.sequence:32-little,
  >>
}

fn serialize_prev_out(prev_out: PrevOut) -> BitArray {
  <<
    get_prev_out_txid(prev_out):bits,
    get_prev_out_vout(prev_out):32-little,
  >>
}

fn serialize_outputs(outputs: List(TxOut)) -> BitArray {
  outputs
  |> list.map(serialize_tx_out)
  |> bit_array.concat
}

fn serialize_tx_out(txout: TxOut) -> BitArray {
  let assert Ok(satoshis_bytes) = int64.int_to_bytes_le(txout.value)

  let script_pubkey_len_bytes = {
    let assert Ok(len_u64) =
      txout.script_pubkey
      |> get_script_length
      |> uint64.from_int

    compact_size.write(len_u64)
  }

  <<
    satoshis_bytes:bits,
    script_pubkey_len_bytes:bits,
    get_raw_script_bytes(txout.script_pubkey):bits,
  >>
}

fn serialize_witnesses(witnesses: List(WitnessStack)) -> BitArray {
  witnesses
  |> list.map(serialize_witness)
  |> bit_array.concat
}

fn serialize_witness(witness: WitnessStack) -> BitArray {
  let witness_items = get_witness_items(witness)

  let assert Ok(stack_len) =
    witness_items
    |> list.length
    |> uint64.from_int

  <<
    compact_size.write(stack_len):bits,
    serialize_witness_items(witness_items):bits,
  >>
}

fn serialize_witness_items(witness_items: List(WitnessItem)) -> BitArray {
  witness_items
  |> list.map(serialize_witness_item)
  |> bit_array.concat
}

fn serialize_witness_item(witness_item: WitnessItem) -> BitArray {
  let witness_item_bytes = get_witness_item_bytes(witness_item)

  let assert Ok(item_len) =
    witness_item_bytes
    |> bit_array.byte_size
    |> uint64.from_int

  <<
    compact_size.write(item_len):bits,
    witness_item_bytes:bits,
  >>
}

fn dsha256(bytes: BitArray) -> BitArray {
  bytes
  |> crypto.hash(Sha256, _)
  |> crypto.hash(Sha256, _)
}
