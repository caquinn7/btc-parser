//// Parse, inspect, and validate Bitcoin transactions.

import gleam/bit_array
import gleam/bool
import gleam/crypto.{Sha256}
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
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
/// decoded from bytes but has not yet been validated against Bitcoin
/// consensus rules.
pub type Parsed

/// Phantom type indicating a transaction that has passed the context-free
/// Bitcoin consensus checks performed by `validate_context_free_consensus`.
///
/// This does not indicate full transaction validity. Context-dependent checks
/// such as script execution, signature verification, and UTXO lookup are not
/// performed.
pub type ContextFreeValidated

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
  /// SegWit transactions extend the legacy format
  /// with a separate witness data section.
  Segwit(
    /// The transaction version number.
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
    Segwit(..) -> True
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
/// For a context-free-validated check, use `is_coinbase` after calling
/// `validate_context_free_consensus`.
///
/// Returns `True` if any input has a coinbase marker, `False` otherwise.
pub fn has_coinbase_marker(tx: Transaction(v)) -> Bool {
  list.any(tx.inputs, fn(txin) { prev_out_is_null_outpoint(txin.prev_out) })
}

/// Check whether a transaction is a valid coinbase transaction.
///
/// This function returns `True` only for transactions that have passed the
/// context-free Bitcoin consensus checks performed by
/// `validate_context_free_consensus` and have a valid transaction-local
/// coinbase shape.
///
/// A coinbase transaction is the first transaction in a block, which creates new
/// bitcoins as a block reward and does not spend any previous outputs. Valid
/// coinbase transactions must:
/// - Have exactly one input with a coinbase marker (null previous outpoint)
/// - Have a scriptSig between 2 and 100 bytes in length
///
/// **Requires validation**: This function accepts only
/// `Transaction(ContextFreeValidated)`, ensuring the transaction has passed the
/// context-free checks performed by `validate_context_free_consensus`.
///
/// For a structural check without validation, use `has_coinbase_marker`.
///
/// Returns `True` if this is a valid coinbase transaction, `False` otherwise.
pub fn is_coinbase(tx: Transaction(ContextFreeValidated)) -> Bool {
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
    Segwit(witnesses:, ..) -> Ok(witnesses)
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

/// Check whether a previous output reference is the null outpoint.
///
/// The null outpoint is the special previous output reference used as the
/// coinbase input marker: an all-zero txid with vout `0xFFFFFFFF`.
pub fn prev_out_is_null_outpoint(prev_out: PrevOut) -> Bool {
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

/// Check whether a witness stack contains no items.
///
/// A stack containing a zero-length item is not empty. Emptiness refers to the
/// number of items, not the number of bytes contained in those items.
pub fn witness_stack_is_empty(stack: WitnessStack) -> Bool {
  case get_witness_items(stack) {
    [] -> True
    _ -> False
  }
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

/// Get the byte size of a `ScriptBytes`.
///
/// The size is measured from the raw script bytes and excludes the CompactSize
/// length prefix used when the script is serialized in a transaction.
pub fn get_script_size(script: ScriptBytes(k)) -> Int {
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
/// enabling type-safe dispatch when inspecting outputs.
///
/// This type is intentionally classification-only. Its variants do not carry
/// embedded script data such as hashes, public keys, witness programs, multisig
/// parameters, or `OP_RETURN` payloads. Call `get_raw_script_bytes` when caller
/// code needs to perform additional script-specific analysis.
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

  /// Standard null-data output as defined by Bitcoin Core relay policy.
  ///
  /// This variant represents the standard null-data template, not every script
  /// that begins with `OP_RETURN`.
  ///
  /// Matches scripts that begin with `OP_RETURN`, are followed only by push
  /// opcodes, and have a total size of at most 83 bytes. The size limit is a
  /// relay policy constraint, not a consensus rule.
  ///
  /// An `OP_RETURN` script that is push-only but exceeds 83 bytes, or that
  /// contains non-push opcodes after `OP_RETURN`, will classify as
  /// `NonStandard` instead.
  NullData

  /// A well-formed witness program whose witness version is not assigned a named
  /// output type by this library.
  ///
  /// `version` is the decoded witness version (1–16). Version 1 with a
  /// 32-byte witness program is classified as `P2TR` and therefore never
  /// appears here.
  ///
  /// Forward-compatible. Do not treat this the same as `NonStandard`.
  UnknownWitness(version: Int)

  /// Does not match any recognized standard output template.
  NonStandard
}

/// Classify the script type of a transaction output's locking script.
///
/// Matches `script_pubkey` bytes against known Bitcoin script templates and
/// returns the corresponding `OutputScriptType`.
///
/// This function performs structural classification only. It does not extract,
/// decode, or interpret embedded hashes, public keys, witness programs, multisig
/// parameters, signatures, or data payloads. For caller-specific script
/// analysis, use `get_raw_script_bytes` on the original script.
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
///     ├─ [51–60] [02–28] [×push_length]    → UnknownWitness(version)
///     └─ valid m-of-n (1≤m≤n≤3)
///         ├─ AND pubkey count matches n    → Multisig
///         └─ otherwise                     → NonStandard
/// ```
///
/// ## Example
///
/// ```gleam
/// let script_pubkey = get_output_script_pubkey(output)
/// case classify_output_script(script_pubkey) {
///   P2WPKH | P2WSH | P2TR -> handle_native_segwit(output)
///   P2PKH | P2SH -> handle_legacy(output)
///   UnknownWitness(v) -> handle_future_witness(v, output)
///   _ -> handle_other(output)
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
    <<version, push_length, _:bytes-size(push_length)>>
      if version >= 0x51
      && version <= 0x60
      && push_length >= 2
      && push_length <= 40
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
    <<push_length, rest:bits>> if push_length >= 0x01 && push_length <= 0x4B ->
      case rest {
        <<_:bytes-size(push_length), remainder:bits>> ->
          do_is_push_only(remainder)

        _ -> False
      }

    // OP_PUSHDATA1: next byte is length, then data
    <<0x4C, push_length, rest:bits>> ->
      case rest {
        <<_:bytes-size(push_length), remainder:bits>> ->
          do_is_push_only(remainder)

        _ -> False
      }

    // OP_PUSHDATA2: next 2 bytes (LE) are length, then data
    <<0x4D, push_length:little-size(16), rest:bits>> ->
      case rest {
        <<_:bytes-size(push_length), remainder:bits>> ->
          do_is_push_only(remainder)

        _ -> False
      }

    // OP_PUSHDATA4: next 4 bytes (LE) are length, then data
    <<0x4E, push_length:little-size(32), rest:bits>> ->
      case rest {
        <<_:bytes-size(push_length), remainder:bits>> ->
          do_is_push_only(remainder)

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
fn read_multisig_header(
  bytes: BitArray,
  total: Int,
) -> Result(#(Int, Int), Nil) {
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

  /// The SegWit marker byte (0x00) was present but the flag byte was not 0x01.
  InvalidSegwitMarkerFlag(marker: Int, flag: Int)

  /// SegWit serialization was used, but every input witness stack was empty.
  ///
  /// Transactions without witness data must use legacy serialization. A witness
  /// stack containing a zero-length item is nonempty and does not trigger this
  /// error.
  SuperfluousWitnessRecord

  /// A length or count requires more bytes than remain in the input.
  ///
  /// Unlike `UnexpectedEof`, which reports a failed read, this error reports a
  /// decoded length or count that is known in advance not to fit in the remaining
  /// input. This is distinct from `PolicyLimitExceeded`, which enforces configured
  /// resource limits.
  ///
  /// Examples:
  /// - A scriptSig length claims a 100-byte script, but only 99 bytes remain.
  /// - An input count claims one input, whose smallest encoding is 41 bytes, but
  ///   only 40 bytes remain.
  ///
  /// `claimed` is the number of bytes required and `remaining` is the number
  /// available. `claimed` may be a conservative estimate, such as
  /// `remaining + 1`, rather than the exact requirement to avoid integer overflow
  /// on the JavaScript target.
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
}

/// Contextual information about where in the transaction structure a parsing error occurred.
pub type ParseContext {
  /// The error occurred while parsing the top-level transaction structure.
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
/// Most variants correspond directly to a field in the Bitcoin wire format
/// and are used in error reporting to indicate which field was being parsed
/// when an error occurred.
/// 
/// `WitnessItemsTotalBytes` is the exception: it is a
/// synthetic marker with no corresponding serialized field, used solely to
/// report when the cumulative witness payload byte limit is exceeded across
/// all items in a single input's witness stack.
pub type Field {
  // Top-level transaction fields
  Version
  LockTime

  // SegWit marker/flag detection
  SegwitMarkerAndFlag

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
  WitnessItemCount
  WitnessItemLength
  WitnessItemsTotalBytes
}

/// Get the byte offset where a parsing error occurred.
///
/// The offset is a zero-based position into the input buffer, indicating
/// where the parser was reading when it encountered the error. This is useful
/// for debugging and error reporting.
///
/// ## Example
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
/// ## Example
///
/// ```gleam
/// fn is_truncated(error: ParseError) -> Bool {
///  case parse_error_kind(error) {
///    UnexpectedEof(_, _) -> True
///    InsufficientBytes(_, _) -> True
///    _ -> False
///  }
///}
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
/// ## Example
///
/// ```gleam
/// case decode(malformed_bytes) {
///   Error(ParseFailed(err)) -> {
///     let ctx = parse_error_ctx(err)
///     // ctx: [InTransaction, InInputs, AtInput(2), AtField(ScriptSigLength)]
///     // Means: failed at the scriptSig length prefix of input #2 (zero-based)
///   }
///   _ -> // ...
/// }
/// ```
pub fn parse_error_ctx(err: ParseError) -> List(ParseContext) {
  err.ctx
}

fn parse_error(kind: ParseErrorKind, offset: Int) -> ParseError {
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
fn field_error(
  field: Field,
  offset: Int,
  ctx: List(ParseContext),
) -> fn(ParseErrorKind) -> DecodeError {
  fn(kind) {
    kind
    |> parse_error(offset)
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
/// processing time.
/// 
/// Limits are enforced during parsing. If a limit is exceeded,
/// decoding fails with `PolicyLimitExceeded`.
///
/// Optional limits are only enforced when `Some`; `None` disables the limit.
///
/// Builder functions do not validate whether custom limits are useful for
/// parsing consensus-valid transactions. Callers that override `default_decode_policy`
/// are responsible for choosing sensible values for their use case. Overly
/// strict or unusual values may simply cause decoding to fail with the existing
/// parse and policy errors.
///
/// ## See Also
///
/// - `default_decode_policy` for the standard parsing limits
/// - `decode_with_policy` to apply a custom policy
pub opaque type DecodePolicy {
  DecodePolicy(
    /// Maximum size in bytes of the serialized transaction.
    ///
    /// This is the primary resource constraint and is enforced before parsing begins.
    /// Transactions exceeding this size are rejected immediately to prevent excessive
    /// memory allocation and processing time.
    ///
    /// Some consensus-valid transactions exceed this limit.
    max_tx_size: Int,
    /// Maximum number of transaction inputs allowed.
    /// 
    /// Exceeding this causes the parser to reject the transaction
    /// before allocating storage for the full input list.
    max_vin_count: Int,
    /// Maximum number of transaction outputs allowed.
    /// 
    /// Exceeding this causes the parser to reject the transaction
    /// before allocating storage for the full output list.
    max_vout_count: Int,
    /// Maximum size in bytes for an individual transaction script
    /// (`scriptSig` or `scriptPubKey`).
    ///
    /// This limit applies per script and prevents unbounded memory
    /// allocation when reading script data.
    max_script_size: Int,
    /// Maximum number of witness stack items allowed for a single input.
    ///
    /// This limits the number of elements in the witness stack, preventing
    /// excessive iteration or allocation when processing inputs with many
    /// small items.
    /// 
    /// Set to `None` to disable this limit.
    max_witness_items_per_input: Option(Int),
    /// Maximum total size in bytes across all witness items for a single input.
    ///
    /// This is the sum of the byte lengths of all witness items and does not
    /// include length prefixes.
    ///
    /// This caps the total size of witness data per input,
    /// preventing many small items from accumulating into an excessively large total.
    ///
    /// Set to `None` to disable this limit.
    max_witness_size_per_input: Option(Int),
  )
}

/// The default transaction decoding policy.
///
/// Provides reasonable resource limits for transaction decoding, applied
/// automatically when using `decode` or `decode_hex`. These defaults protect
/// against malicious inputs while preventing excessive memory allocation and
/// processing time. As these are policy limits rather than consensus rules,
/// some valid Bitcoin transactions may be rejected by this configuration.
/// 
/// The overall transaction size limit (`max_tx_size`) serves as the primary
/// resource constraint. Witness-related limits are optional and may be enabled
/// by callers who wish to impose additional per-input constraints.
///
/// ## Default Values
///
/// - `max_tx_size`: 400,000 bytes - Primary resource constraint, enforced before
///   parsing begins.
/// - `max_vin_count`: 100,000 inputs - Substantially higher than typical transactions
///   but prevents unbounded memory allocation for input lists.
/// - `max_vout_count`: 100,000 outputs - Similarly generous for outputs.
/// - `max_script_size`: 10,000 bytes - Accommodates common transaction scripts
///   (e.g., P2PKH, P2SH, P2WPKH, P2WSH, P2TR) with significant headroom for
///   complex or non-standard scripts.
/// - `max_witness_items_per_input`: `None` - No limit on witness stack item count.
/// - `max_witness_size_per_input`: `None` - No limit on total witness data bytes per input.
pub fn default_decode_policy() -> DecodePolicy {
  DecodePolicy(
    max_tx_size: 400_000,
    max_vin_count: 100_000,
    max_vout_count: 100_000,
    max_script_size: 10_000,
    max_witness_items_per_input: None,
    max_witness_size_per_input: None,
  )
}

/// Return a policy with a custom maximum serialized transaction size.
pub fn decode_policy_with_max_tx_size(
  policy: DecodePolicy,
  max_tx_size: Int,
) -> DecodePolicy {
  DecodePolicy(..policy, max_tx_size:)
}

/// Return a policy with a custom maximum transaction input count.
pub fn decode_policy_with_max_vin_count(
  policy: DecodePolicy,
  max_vin_count: Int,
) -> DecodePolicy {
  DecodePolicy(..policy, max_vin_count:)
}

/// Return a policy with a custom maximum transaction output count.
pub fn decode_policy_with_max_vout_count(
  policy: DecodePolicy,
  max_vout_count: Int,
) -> DecodePolicy {
  DecodePolicy(..policy, max_vout_count:)
}

/// Return a policy with a custom maximum script size.
///
/// This limit applies to each `scriptSig` and `scriptPubKey`.
pub fn decode_policy_with_max_script_size(
  policy: DecodePolicy,
  max_script_size: Int,
) -> DecodePolicy {
  DecodePolicy(..policy, max_script_size:)
}

/// Return a policy with a custom witness item count limit per input.
///
/// Set to `None` to disable this limit.
pub fn decode_policy_with_max_witness_items_per_input(
  policy: DecodePolicy,
  max_witness_items_per_input: Option(Int),
) -> DecodePolicy {
  DecodePolicy(..policy, max_witness_items_per_input:)
}

/// Return a policy with a custom witness payload size limit per input.
///
/// This limit is the total number of bytes across all witness items for a
/// single input. Set to `None` to disable this limit.
pub fn decode_policy_with_max_witness_size_per_input(
  policy: DecodePolicy,
  max_witness_size_per_input: Option(Int),
) -> DecodePolicy {
  DecodePolicy(..policy, max_witness_size_per_input:)
}

/// Get the maximum serialized transaction size.
pub fn decode_policy_max_tx_size(policy: DecodePolicy) -> Int {
  policy.max_tx_size
}

/// Get the maximum transaction input count.
pub fn decode_policy_max_vin_count(policy: DecodePolicy) -> Int {
  policy.max_vin_count
}

/// Get the maximum transaction output count.
pub fn decode_policy_max_vout_count(policy: DecodePolicy) -> Int {
  policy.max_vout_count
}

/// Get the maximum script size.
pub fn decode_policy_max_script_size(policy: DecodePolicy) -> Int {
  policy.max_script_size
}

/// Get the maximum witness item count per input.
pub fn decode_policy_max_witness_items_per_input(
  policy: DecodePolicy,
) -> Option(Int) {
  policy.max_witness_items_per_input
}

/// Get the maximum witness payload size per input.
pub fn decode_policy_max_witness_size_per_input(
  policy: DecodePolicy,
) -> Option(Int) {
  policy.max_witness_size_per_input
}

/// Decode a Bitcoin transaction from its binary representation.
///
/// This is the standard entry point for parsing Bitcoin transaction data
/// serialized in the Bitcoin network protocol format.
///
/// This function applies `default_decode_policy` to protect against malicious inputs
/// by enforcing reasonable limits on transaction size, input/output counts, script
/// sizes, and witness data.
/// 
/// For custom parsing limits, use `decode_with_policy` instead.
///
/// The decoded transaction is marked as `Parsed`, meaning it has been
/// successfully decoded from bytes but has not yet been checked against
/// Bitcoin consensus rules.
///
/// ## Returns
///
/// - `Ok(Transaction(Parsed))`: Successfully decoded transaction.
/// - `Error(DecodeError)`: The bytes could not be parsed as a valid transaction.
///   This includes malformed data, unexpected end of input, or violations of
///   the policy limits.
///
/// ## Example
///
/// ```gleam
/// let tx_bytes = <<0x01, 0x00, 0x00, 0x00, ...>>
/// case decode(tx_bytes) {
///   Ok(tx) -> // Transaction successfully parsed
///   Error(ParseFailed(err)) -> // Handle parse error
///   Error(HexToBytesFailed) -> // Won't occur with direct bytes
/// }
/// ```
pub fn decode(bytes: BitArray) -> Result(Transaction(Parsed), DecodeError) {
  decode_with_policy(bytes, default_decode_policy())
}

/// Decode a Bitcoin transaction with custom parsing limits.
///
/// Like `decode`, but accepts a `DecodePolicy` to override the resource limits
/// applied during parsing. Use `default_decode_policy` and the `decode_policy_with_*`
/// builder functions to construct custom policies. Limits that are exceeded
/// produce a `PolicyLimitExceeded` error. See `DecodePolicy` and
/// `default_decode_policy` for available options and defaults.
///
/// ## Returns
///
/// - `Ok(Transaction(Parsed))`: Successfully decoded transaction within policy limits.
/// - `Error(DecodeError)`: The bytes could not be parsed or exceeded policy limits.
pub fn decode_with_policy(
  bytes: BitArray,
  policy: DecodePolicy,
) -> Result(Transaction(Parsed), DecodeError) {
  let tx_size = bit_array.byte_size(bytes)
  use <- bool.guard(
    tx_size > policy.max_tx_size,
    PolicyLimitExceeded(tx_size, policy.max_tx_size)
      |> parse_error(0)
      |> with_contexts([InTransaction])
      |> ParseFailed
      |> Error,
  )

  bytes
  |> reader.new
  |> parser.run(tx_parser(policy), _, [InTransaction])
  |> result.map(pair.second)
}

fn tx_parser(
  policy: DecodePolicy,
) -> Parser(ParseContext, Transaction(Parsed), DecodeError) {
  use version <- parser.then(field_parser(Version, reader.read_i32_le))
  use is_segwit <- parser.then(segwit_detection_parser())
  use inputs <- parser.then(parser.with_context(
    inputs_parser(policy.max_vin_count, policy.max_script_size),
    InInputs,
  ))
  use outputs <- parser.then(parser.with_context(
    outputs_parser(policy.max_vout_count, policy.max_script_size),
    InOutputs,
  ))
  use witnesses <- parser.then(witnesses_if_segwit_parser(
    is_segwit,
    list.length(inputs),
    policy,
  ))
  use lock_time <- parser.then(field_parser(LockTime, reader.read_u32_le))
  use _ <- parser.then(end_of_input_parser())

  parser.return(case witnesses {
    Some(witnesses) ->
      Segwit(version:, inputs:, outputs:, lock_time:, witnesses:)

    None -> Legacy(version:, inputs:, outputs:, lock_time:)
  })
}

/// Decode a Bitcoin transaction from its hexadecimal string representation.
///
/// This is a convenience function that combines hex-to-bytes conversion with
/// transaction decoding. It's useful when working with transaction data in
/// hexadecimal format, such as from block explorers, RPC responses, or test
/// vectors.
///
/// This function applies `default_decode_policy` for parsing limits.
/// For custom parsing limits, use `decode_with_policy` instead.
///
/// ## Returns
///
/// - `Ok(Transaction(Parsed))`: Successfully decoded transaction.
/// - `Error(HexToBytesFailed)`: The hex string was invalid (odd length or
///   invalid characters).
/// - `Error(ParseFailed(_))`: The bytes could not be parsed as a valid transaction.
///
/// ## Example
///
/// ```gleam
/// let hex = "0100000001..."
/// case decode_hex(hex) {
///   Ok(tx) -> // Transaction successfully parsed
///   Error(HexToBytesFailed) -> // Invalid hex string
///   Error(ParseFailed(err)) -> // Valid hex but invalid transaction
/// }
/// ```
pub fn decode_hex(hex: String) -> Result(Transaction(Parsed), DecodeError) {
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
/// - `Ok(Transaction(Parsed))`: Successfully decoded transaction within policy limits.
/// - `Error(HexToBytesFailed)`: The hex string was invalid (odd length or
///   invalid characters).
/// - `Error(ParseFailed(_))`: The bytes could not be parsed or exceeded policy limits.
pub fn decode_hex_with_policy(
  hex: String,
  policy: DecodePolicy,
) -> Result(Transaction(Parsed), DecodeError) {
  hex
  |> hex_to_bytes
  |> result.try(decode_with_policy(_, policy))
}

fn hex_to_bytes(hex: String) -> Result(BitArray, DecodeError) {
  hex
  |> bit_array.base16_decode
  |> result.replace_error(HexToBytesFailed)
}

/// Construct a parser for a field, adding error mapping and context wrapping.
fn field_parser(
  field: Field,
  read_fn: fn(Reader) -> Result(#(Reader, a), reader.ReaderError),
) -> Parser(ParseContext, a, DecodeError) {
  parser.new(fn(reader, ctx) {
    reader
    |> read_fn
    |> result.map_error(fn(err) {
      err
      |> reader_error_to_kind
      |> field_error(field, reader.get_offset(reader), ctx)
    })
  })
}

/// Construct a CompactSize parser with error mapping and context wrapping.
fn compact_size_parser(
  field: Field,
) -> Parser(ParseContext, Uint64, DecodeError) {
  parser.new(fn(reader, ctx) {
    reader
    |> compact_size.read
    |> result.map_error(fn(err) {
      case err {
        compact_size.ReaderError(re) -> reader_error_to_kind(re)
        compact_size.NonMinimalCompactSize(encoded:, value:) ->
          NonMinimalCompactSize(encoded:, value:)
      }
      |> field_error(field, reader.get_offset(reader), ctx)
    })
  })
}

/// Construct a parser for a CompactSize value converted to `Int`.
///
/// This wraps `compact_size_parser` and handles the common pattern of converting
/// the `Uint64` result to `Int`, mapping conversion failures to `IntegerOutOfRange` errors.
fn compact_size_int_parser(
  field: Field,
) -> Parser(ParseContext, Int, DecodeError) {
  field
  |> compact_size_parser
  |> parser.try_with_start_offset(fn(value_u64, start_offset, _, ctx) {
    value_u64
    |> uint64.to_int
    |> result.map_error(fn(_) {
      value_u64
      |> uint64.to_string
      |> IntegerOutOfRange
      |> field_error(field, start_offset, ctx)
    })
  })
}

/// Construct a parser that detects whether a transaction uses SegWit format.
///
/// Returns `True` if the marker/flag bytes (0x00, 0x01) are present, `False` otherwise.
/// When run, the parser consumes the marker/flag bytes if present.
fn segwit_detection_parser() -> Parser(ParseContext, Bool, DecodeError) {
  segwit_lookahead_parser()
  |> parser.then(fn(is_segwit) {
    case is_segwit {
      True ->
        is_segwit
        |> parser.return
        |> parser.keep_left(segwit_marker_and_flag_parser())

      False -> parser.return(is_segwit)
    }
  })
}

/// Construct a parser that inspects the next two bytes for a SegWit marker/flag.
///
/// This parser never consumes input, regardless of whether it succeeds or
/// returns an error.
///
/// `segwit_detection_parser` consumes the marker and flag bytes after this
/// parser recognizes 0x00 0x01.
fn segwit_lookahead_parser() -> Parser(ParseContext, Bool, DecodeError) {
  // Uses `parser.new` directly due to special peek semantics and EOF error recovery.
  parser.new(fn(reader, ctx) {
    case reader.peek_bytes(reader, 2) {
      Ok(bytes) -> {
        let assert <<marker, flag>> = bytes
        case marker, flag {
          0x00, 0x01 -> Ok(#(reader, True))

          0x00, 0x00 -> Ok(#(reader, False))

          0x00, _ ->
            InvalidSegwitMarkerFlag(marker, flag)
            |> field_error(SegwitMarkerAndFlag, reader.get_offset(reader), ctx)
            |> Error

          _, _ -> Ok(#(reader, False))
        }
      }

      Error(err) -> {
        // Panic on InvalidReadCount and silently treat UnexpectedEof as non-SegWit.
        let _ = reader_error_to_kind(err)
        // We can't peek, so we fall through and let the subsequent field parsers
        // produce a more contextual EOF error.
        Ok(#(reader, False))
      }
    }
  })
}

/// Construct a parser that consumes the SegWit marker and flag bytes when run.
fn segwit_marker_and_flag_parser() -> Parser(ParseContext, Nil, DecodeError) {
  field_parser(SegwitMarkerAndFlag, fn(reader) {
    reader
    |> reader.skip_bytes(2)
    |> result.map(pair.new(_, Nil))
  })
}

fn inputs_parser(
  max_vin_count_policy: Int,
  max_script_size_policy: Int,
) -> Parser(ParseContext, List(TxIn), DecodeError) {
  max_vin_count_policy
  |> vin_count_parser
  |> parser.then(txin_list_parser(_, max_script_size_policy))
}

/// Validate and convert the vin_count from Uint64 to Int, checking structural and policy limits.
fn vin_count_parser(
  max_vin_count_policy: Int,
) -> Parser(ParseContext, Int, DecodeError) {
  VinCount
  |> compact_size_int_parser
  |> parser.try_with_start_offset(fn(vin_count_int, start_offset, reader, ctx) {
    let on_invalid = fn(kind) {
      kind
      |> field_error(VinCount, start_offset, ctx)
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

fn txin_list_parser(
  vin_count: Int,
  max_script_size_policy: Int,
) -> Parser(ParseContext, List(TxIn), DecodeError) {
  // vin_count
  // ├─ TxIn #0
  // │    ├─ prev_txid (32 bytes)
  // │    ├─ vout (4 bytes)
  // │    ├─ scriptSig length (CompactSize)
  // │    ├─ scriptSig bytes
  // │    └─ sequence (4 bytes)
  // ├─ TxIn #1
  // │    ├─ ...
  // └─ TxIn #(vin_count - 1)
  parser.indexed_repeat(vin_count, txin_parser(max_script_size_policy), AtInput)
}

fn txin_parser(
  max_script_size_policy: Int,
) -> Parser(ParseContext, TxIn, DecodeError) {
  // │ prev_txid (32 bytes)
  // │ vout (4 bytes)
  // │ scriptSig length (CompactSize)
  // │ scriptSig bytes
  // │ sequence (4 bytes)
  parser.map3(
    prev_out_parser(),
    script_sig_parser(max_script_size_policy),
    field_parser(Sequence, reader.read_u32_le),
    TxIn,
  )
}

fn prev_out_parser() -> Parser(ParseContext, PrevOut, DecodeError) {
  parser.map2(
    field_parser(PrevTxId, reader.read_bytes(_, 32)),
    field_parser(Vout, reader.read_u32_le),
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

fn outputs_parser(
  max_vout_count_policy: Int,
  max_script_size_policy: Int,
) -> Parser(ParseContext, List(TxOut), DecodeError) {
  max_vout_count_policy
  |> vout_count_parser
  |> parser.then(txout_list_parser(_, max_script_size_policy))
}

/// Validate and convert the vout_count from Uint64 to Int, checking structural and policy limits.
fn vout_count_parser(
  max_vout_count_policy: Int,
) -> Parser(ParseContext, Int, DecodeError) {
  VoutCount
  |> compact_size_int_parser
  |> parser.try_with_start_offset(fn(vout_count_int, start_offset, reader, ctx) {
    let on_invalid = fn(kind) {
      kind
      |> field_error(VoutCount, start_offset, ctx)
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

fn txout_list_parser(
  vout_count: Int,
  max_script_size_policy: Int,
) -> Parser(ParseContext, List(TxOut), DecodeError) {
  // vout_count
  // ├─ TxOut #0
  // │    ├─ value (8 bytes)
  // │    ├─ scriptPubKey length (CompactSize)
  // │    └─ scriptPubKey bytes
  // ├─ TxOut #1
  // │    ├─ ...
  // └─ TxOut #(vout_count - 1)
  parser.indexed_repeat(
    vout_count,
    txout_parser(max_script_size_policy),
    AtOutput,
  )
}

fn txout_parser(
  max_script_size_policy: Int,
) -> Parser(ParseContext, TxOut, DecodeError) {
  // | value (8 bytes)
  // | scriptPubKey length (CompactSize)
  // | scriptPubKey bytes
  parser.map2(
    satoshis_parser(),
    script_pubkey_parser(max_script_size_policy),
    TxOut,
  )
}

fn satoshis_parser() -> Parser(ParseContext, Int, DecodeError) {
  Value
  |> field_parser(reader.read_bytes(_, 8))
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
      |> field_error(Value, start_offset, ctx)
    })
  })
}

fn script_sig_parser(
  max_script_size_policy: Int,
) -> Parser(ParseContext, ScriptBytes(InputScript), DecodeError) {
  ScriptSigLength
  |> script_length_parser(max_script_size_policy)
  |> parser.then(fn(script_length) {
    field_parser(ScriptSig, reader.read_bytes(_, script_length))
  })
  |> parser.map(ScriptBytes)
}

fn script_pubkey_parser(
  max_script_size_policy: Int,
) -> Parser(ParseContext, ScriptBytes(OutputScript), DecodeError) {
  ScriptPubKeyLength
  |> script_length_parser(max_script_size_policy)
  |> parser.then(fn(script_length) {
    field_parser(ScriptPubKey, reader.read_bytes(_, script_length))
  })
  |> parser.map(ScriptBytes)
}

/// Construct a parser for a validated script length field.
///
/// When run, it parses a CompactSize length, converts it to `Int`, validates it
/// against `max_script_size_policy`, and ensures sufficient bytes remain.
fn script_length_parser(
  field: Field,
  max_script_size_policy: Int,
) -> Parser(ParseContext, Int, DecodeError) {
  field
  |> compact_size_int_parser
  |> parser.try_with_start_offset(fn(script_length, start_offset, reader, ctx) {
    let on_invalid = fn(kind) {
      kind
      |> field_error(field, start_offset, ctx)
      |> Error
    }
    validate_script_length(
      script_length,
      reader,
      max_script_size_policy,
      on_invalid,
    )
  })
}

fn validate_script_length(
  script_length: Int,
  reader: Reader,
  max_script_size_policy: Int,
  on_invalid: fn(ParseErrorKind) -> Result(Int, DecodeError),
) -> Result(Int, DecodeError) {
  let remaining = reader.bytes_remaining(reader)

  case script_length > remaining, script_length > max_script_size_policy {
    // Structural limit: length exceeds remaining bytes
    True, _ ->
      InsufficientBytes(claimed: script_length, remaining:)
      |> on_invalid

    // Policy limit: length exceeds configured maximum
    _, True ->
      PolicyLimitExceeded(script_length, max_script_size_policy)
      |> on_invalid

    _, _ -> Ok(script_length)
  }
}

fn witnesses_if_segwit_parser(
  is_segwit: Bool,
  vin_count: Int,
  policy: DecodePolicy,
) -> Parser(ParseContext, Option(List(WitnessStack)), DecodeError) {
  case is_segwit {
    True ->
      vin_count
      |> witnesses_parser(
        policy.max_witness_items_per_input,
        policy.max_witness_size_per_input,
      )
      |> parser.map(Some)

    False -> parser.return(None)
  }
}

fn witnesses_parser(
  vin_count: Int,
  max_items_per_input: Option(Int),
  max_size_per_input: Option(Int),
) -> Parser(ParseContext, List(WitnessStack), DecodeError) {
  vin_count
  |> parser.indexed_repeat(
    witness_parser(max_items_per_input, max_size_per_input),
    AtWitnessStack,
  )
  |> parser.try_with_start_offset(fn(witnesses, start_offset, _reader, ctx) {
    case list.all(witnesses, witness_stack_is_empty) {
      True ->
        SuperfluousWitnessRecord
        |> parse_error(start_offset)
        |> with_contexts(ctx)
        |> ParseFailed
        |> Error

      False -> Ok(witnesses)
    }
  })
}

fn witness_parser(
  max_items_per_input: Option(Int),
  max_size_per_input: Option(Int),
) -> Parser(ParseContext, WitnessStack, DecodeError) {
  // WitnessStack for one input:
  // ├─ item count (CompactSize)
  // ├─ WitnessItem #0
  // │    ├─ item length (CompactSize)
  // │    └─ item bytes
  // ├─ WitnessItem #1
  // │    ├─ ...
  // └─ WitnessItem #(item_count - 1)
  max_items_per_input
  |> witness_item_count_parser
  |> parser.then(fn(item_count) {
    case max_size_per_input {
      Some(max_size) -> tracked_witness_items_parser(item_count, max_size)
      None -> witness_items_parser(item_count)
    }
  })
  |> parser.map(WitnessStack)
}

/// Construct a parser for a validated witness item count field.
///
/// When run, it parses a CompactSize count, converts it to `Int`, and validates
/// it against the `max_items_per_input` policy.
fn witness_item_count_parser(
  max_items_per_input_policy: Option(Int),
) -> Parser(ParseContext, Int, DecodeError) {
  WitnessItemCount
  |> compact_size_int_parser
  |> parser.try_with_start_offset(fn(item_count, start_offset, _reader, ctx) {
    case max_items_per_input_policy {
      Some(max_items) if item_count > max_items ->
        PolicyLimitExceeded(item_count, max_items)
        |> field_error(WitnessItemCount, start_offset, ctx)
        |> Error

      _ -> Ok(item_count)
    }
  })
}

fn witness_items_parser(
  item_count: Int,
) -> Parser(ParseContext, List(WitnessItem), DecodeError) {
  parser.indexed_repeat(item_count, witness_item_parser(), AtWitnessItem)
}

/// Construct a witness-items parser that tracks cumulative payload bytes.
///
/// When run, it fails fast if the total exceeds `max_total_bytes`.
fn tracked_witness_items_parser(
  item_count: Int,
  max_total_bytes: Int,
) -> Parser(ParseContext, List(WitnessItem), DecodeError) {
  parser.indexed_repeat_with_limit(
    item_count,
    sized_witness_item_parser(),
    AtWitnessItem,
    max_total_bytes,
    fn(exceeded_val, start_offset, ctx) {
      PolicyLimitExceeded(exceeded_val, max_total_bytes)
      |> field_error(WitnessItemsTotalBytes, start_offset, ctx)
    },
  )
}

/// Construct a parser that returns a witness item with its byte size.
fn sized_witness_item_parser() -> Parser(
  ParseContext,
  #(WitnessItem, Int),
  DecodeError,
) {
  witness_item_parser()
  |> parser.map(fn(item) {
    let item_size =
      item
      |> get_witness_item_bytes
      |> bit_array.byte_size

    #(item, item_size)
  })
}

fn witness_item_parser() -> Parser(ParseContext, WitnessItem, DecodeError) {
  witness_item_length_parser()
  |> parser.then(fn(item_length) {
    parser.new(fn(reader, ctx) {
      reader
      |> reader.read_bytes(item_length)
      |> result.map_error(fn(err) {
        err
        |> reader_error_to_kind
        |> parse_error(reader.get_offset(reader))
        |> with_contexts(ctx)
        |> ParseFailed
      })
    })
  })
  |> parser.map(WitnessItem)
}

fn witness_item_length_parser() -> Parser(ParseContext, Int, DecodeError) {
  WitnessItemLength
  |> compact_size_int_parser
  |> parser.try_with_start_offset(fn(item_length, start_offset, reader, ctx) {
    let on_invalid = fn(kind) {
      kind
      |> field_error(WitnessItemLength, start_offset, ctx)
      |> Error
    }
    validate_witness_item_length(item_length, reader, on_invalid)
  })
}

fn validate_witness_item_length(
  item_length: Int,
  reader: Reader,
  on_invalid: fn(ParseErrorKind) -> Result(Int, DecodeError),
) -> Result(Int, DecodeError) {
  let remaining = reader.bytes_remaining(reader)

  case item_length > remaining {
    True ->
      InsufficientBytes(claimed: item_length, remaining:)
      |> on_invalid

    False -> Ok(item_length)
  }
}

fn end_of_input_parser() -> Parser(ParseContext, Nil, DecodeError) {
  parser.end_of_input(fn(bytes_remaining, reader, ctx) {
    bytes_remaining
    |> TrailingBytes
    |> parse_error(reader.get_offset(reader))
    |> with_contexts(ctx)
    |> ParseFailed
  })
}

// ==============================================================================
// Context-Free Consensus Validation
// ==============================================================================

/// A violation of Bitcoin consensus rules detected during transaction validation.
///
/// Each variant identifies a specific rule that the transaction breaks.
pub type ConsensusViolation {
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

  /// The transaction contains duplicate inputs referencing the same prevout.
  ///
  /// Each input in a transaction must reference a unique previous output.
  ///
  /// The `prev_out` field identifies the duplicated outpoint.
  ///
  /// The `first_index` field indicates the zero-based index of the first
  /// occurrence of this outpoint in the input list.
  ///
  /// The `duplicate_index` field indicates the zero-based index of the
  /// subsequent input that duplicates the same outpoint.
  DuplicateInput(prev_out: PrevOut, first_index: Int, duplicate_index: Int)
}

/// Validate a transaction against context-free Bitcoin consensus rules.
///
/// "Context-free" means these checks require only the transaction itself —
/// no UTXO set, no block context, and no knowledge of other transactions.
///
/// This function enforces a subset of the checks performed by fully
/// validating Bitcoin nodes: the structural and monetary rules that can
/// be evaluated from the transaction alone.
///
/// The following consensus rules are enforced:
///
///   - At least one input
///   - At least one output
///   - Output values satisfy MoneyRange (0 <= value <= MAX_MONEY)
///   - Cumulative output value does not exceed MAX_MONEY
///   - Coinbase transactions contain exactly one input
///   - Coinbase scriptSig length is 2–100 bytes (inclusive)
///   - No two inputs reference the same previous output
///
/// Context-dependent checks — script execution, signature verification,
/// and input-spend validation against the UTXO set — are not performed.
pub fn validate_context_free_consensus(
  tx: Transaction(Parsed),
) -> Result(Transaction(ContextFreeValidated), List(ConsensusViolation)) {
  // Validators are designed to run together; some Ok branches rely on a sibling covering that case.
  let validators = [
    validate_at_least_one_input,
    validate_at_least_one_output,
    validate_output_values,
    validate_coinbase_structure,
    validate_coinbase_script_sig_length,
    validate_no_duplicate_inputs,
  ]

  let errors =
    list.filter_map(validators, fn(validator) {
      case validator(tx) {
        Ok(_) -> Error(Nil)
        Error(err) -> Ok(err)
      }
    })

  case errors {
    [] -> Ok(mark_as_context_free_validated(tx))
    _ -> Error(errors)
  }
}

fn mark_as_context_free_validated(
  tx: Transaction(Parsed),
) -> Transaction(ContextFreeValidated) {
  // Change the phantom type by reconstructing with identical data.
  case tx {
    Legacy(v, i, o, l) -> Legacy(v, i, o, l)
    Segwit(v, i, o, l, w) -> Segwit(v, i, o, l, w)
  }
}

fn validate_at_least_one_input(
  tx: Transaction(Parsed),
) -> Result(Nil, ConsensusViolation) {
  case tx.inputs {
    [] -> Error(NoInputs)
    _ -> Ok(Nil)
  }
}

fn validate_at_least_one_output(
  tx: Transaction(Parsed),
) -> Result(Nil, ConsensusViolation) {
  case tx.outputs {
    [] -> Error(NoOutputs)
    _ -> Ok(Nil)
  }
}

fn validate_output_values(
  tx: Transaction(Parsed),
) -> Result(Nil, ConsensusViolation) {
  validate_output_values_loop(tx.outputs, 0, 0)
}

/// The maximum number of satoshis that can exist: 21,000,000 BTC * 100,000,000 sat/BTC.
const max_satoshis = 2_100_000_000_000_000

fn validate_output_values_loop(
  outputs: List(TxOut),
  index: Int,
  sum: Int,
) -> Result(Nil, ConsensusViolation) {
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
            False -> validate_output_values_loop(rest, index + 1, sum)
          }
        }
      }
  }
}

fn validate_coinbase_structure(
  tx: Transaction(Parsed),
) -> Result(Nil, ConsensusViolation) {
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
  tx: Transaction(Parsed),
) -> Result(Nil, ConsensusViolation) {
  case tx.inputs {
    [input] ->
      case input.prev_out {
        NullOutPoint -> {
          let script_size = get_script_size(input.script_sig)
          case 2 <= script_size && script_size <= 100 {
            True -> Ok(Nil)
            False -> Error(InvalidCoinbaseScriptSigLength)
          }
        }

        _ -> Ok(Nil)
      }

    // Zero inputs are caught by validate_at_least_one_input.
    // Multiple inputs with a coinbase marker are caught by validate_coinbase_structure.
    _ -> Ok(Nil)
  }
}

fn validate_no_duplicate_inputs(
  tx: Transaction(Parsed),
) -> Result(Nil, ConsensusViolation) {
  validate_no_duplicate_inputs_loop(tx.inputs, 0, dict.new())
}

fn validate_no_duplicate_inputs_loop(
  inputs: List(TxIn),
  index: Int,
  seen: Dict(PrevOut, Int),
) -> Result(Nil, ConsensusViolation) {
  case inputs {
    [] -> Ok(Nil)

    [txin, ..rest] -> {
      let prev_out = txin.prev_out

      // NullOutPoint is skipped: validate_coinbase_structure already rejects any
      // transaction with multiple NullOutPoint inputs as CoinbaseWithMultipleInputs.
      case prev_out {
        NullOutPoint -> validate_no_duplicate_inputs_loop(rest, index + 1, seen)

        _ ->
          case dict.get(seen, prev_out) {
            Ok(first_index) ->
              Error(DuplicateInput(
                prev_out,
                first_index:,
                duplicate_index: index,
              ))

            Error(_) ->
              validate_no_duplicate_inputs_loop(
                rest,
                index + 1,
                dict.insert(seen, prev_out, index),
              )
          }
      }
    }
  }
}

// ==============================================================================
// Serialization
// ==============================================================================

/// Compute the transaction identifier (txid) for a context-free-validated
/// transaction.
///
/// Returns the 32 bytes of the txid in little-endian byte order, as they
/// appear in Bitcoin transactions and on the wire.
///
/// **Requires validation**: Accepts only `Transaction(ContextFreeValidated)` to
/// ensure the transaction has passed the context-free checks performed by
/// `validate_context_free_consensus`.
pub fn compute_txid(tx: Transaction(ContextFreeValidated)) -> BitArray {
  let assert <<_:256-bits>> =
    tx
    |> to_stripped_bytes
    |> dsha256
}

/// Compute the witness transaction identifier (wtxid) for a
/// context-free-validated transaction.
///
/// Returns the 32 bytes of the wtxid in little-endian byte order, as they
/// appear in Bitcoin transactions and on the wire. For legacy transactions,
/// the wtxid is identical to the txid.
///
/// **Requires validation**: Accepts only `Transaction(ContextFreeValidated)` to
/// ensure the transaction has passed the context-free checks performed by
/// `validate_context_free_consensus`.
pub fn compute_wtxid(tx: Transaction(ContextFreeValidated)) -> BitArray {
  let assert <<_:256-bits>> =
    tx
    |> to_wire_bytes
    |> dsha256
}

/// Serialize a transaction without witness data (the "stripped" form).
///
/// Returns the canonical serialization used when computing the `txid`:
/// version, inputs, outputs, and lock_time — with no SegWit marker, flag,
/// or witness stacks, regardless of whether the transaction is SegWit.
///
/// The byte size of the returned value is the `base_size` used in BIP 141
/// weight and virtual size calculations.
///
/// ## See Also
///
/// - `compute_txid` — hashes this serialization to produce the txid
/// - `to_wire_bytes` — the full wire serialization including witness data
pub fn to_stripped_bytes(tx: Transaction(ContextFreeValidated)) -> BitArray {
  // safe: input/output counts are non-negative Ints parsed from the wire,
  // so they fit within Uint64 (and within JS safe integer bounds)
  let assert Ok(vin_count) = uint64.from_int(list.length(tx.inputs))
  let assert Ok(vout_count) = uint64.from_int(list.length(tx.outputs))

  <<
    tx.version:32-little,
    compact_size.write(vin_count):bits,
    serialize_inputs(tx.inputs):bits,
    compact_size.write(vout_count):bits,
    serialize_outputs(tx.outputs):bits,
    tx.lock_time:32-little,
  >>
}

/// Serialize a transaction in its full wire form, including witness data.
///
/// Returns the complete serialization used when computing the `wtxid`:
/// version, SegWit marker and flag (if applicable), inputs, outputs,
/// witness stacks (if applicable), and lock_time. For legacy transactions,
/// this is identical to `to_stripped_bytes`.
///
/// The byte size of the returned value is the `total_size` used in BIP 141
/// weight and virtual size calculations:
///
/// ```
/// weight = base_size * 3 + total_size
/// vsize  = ceil(weight / 4)
/// ```
///
/// where `base_size = bit_array.byte_size(to_stripped_bytes(tx))` and
/// `total_size = bit_array.byte_size(to_wire_bytes(tx))`.
///
/// ## See Also
///
/// - `compute_wtxid` — hashes this serialization to produce the wtxid
/// - `to_stripped_bytes` — the no-witness serialization used for the txid
pub fn to_wire_bytes(tx: Transaction(ContextFreeValidated)) -> BitArray {
  // safe: input/output counts are non-negative Ints parsed from the wire,
  // so they fit within Uint64 (and within JS safe integer bounds)
  let assert Ok(vin_count) = uint64.from_int(list.length(tx.inputs))
  let assert Ok(vout_count) = uint64.from_int(list.length(tx.outputs))

  let #(segwit_marker_and_flag, witnesses) = case tx {
    Legacy(..) -> #(<<>>, <<>>)
    Segwit(witnesses:, ..) -> #(<<0x00, 0x01>>, serialize_witnesses(witnesses))
  }

  <<
    tx.version:32-little,
    segwit_marker_and_flag:bits,
    compact_size.write(vin_count):bits,
    serialize_inputs(tx.inputs):bits,
    compact_size.write(vout_count):bits,
    serialize_outputs(tx.outputs):bits,
    witnesses:bits,
    tx.lock_time:32-little,
  >>
}

fn serialize_inputs(inputs: List(TxIn)) -> BitArray {
  inputs
  |> list.map(serialize_tx_in)
  |> bit_array.concat
}

fn serialize_tx_in(txin: TxIn) -> BitArray {
  let prev_out_bytes = serialize_prev_out(txin.prev_out)

  let script_sig_length_bytes = {
    let assert Ok(script_sig_length) =
      txin.script_sig
      |> get_script_size
      |> uint64.from_int

    compact_size.write(script_sig_length)
  }

  <<
    prev_out_bytes:bits,
    script_sig_length_bytes:bits,
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

  let script_pubkey_length_bytes = {
    let assert Ok(script_pubkey_length) =
      txout.script_pubkey
      |> get_script_size
      |> uint64.from_int

    compact_size.write(script_pubkey_length)
  }

  <<
    satoshis_bytes:bits,
    script_pubkey_length_bytes:bits,
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

  let assert Ok(item_count) =
    witness_items
    |> list.length
    |> uint64.from_int

  <<
    compact_size.write(item_count):bits,
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

  let assert Ok(item_length) =
    witness_item_bytes
    |> bit_array.byte_size
    |> uint64.from_int

  <<
    compact_size.write(item_length):bits,
    witness_item_bytes:bits,
  >>
}

fn dsha256(bytes: BitArray) -> BitArray {
  bytes
  |> crypto.hash(Sha256, _)
  |> crypto.hash(Sha256, _)
}
