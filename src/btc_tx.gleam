//// btc_tx provides facilities for parsing and modeling Bitcoin transaction data
//// in a form suitable for inspection, analysis, and reference.

import gleam/bit_array
import gleam/list.{Continue, Stop}
import gleam/option.{None, Some}
import gleam/pair
import gleam/result
import internal/compact_size
import internal/fixed_int/int64
import internal/fixed_int/uint64.{type Uint64}
import internal/hash32.{type Hash32}
import internal/hex
import internal/parser.{type Parser}
import internal/reader.{type Reader}

// ---- Transaction types ----

pub type Unvalidated

pub type Validated

/// A Bitcoin transaction.
///
/// A transaction transfers value by consuming previously created outputs
/// (inputs) and creating new outputs. Transactions are either legacy
/// (pre-SegWit) or SegWit, which affects how witness data is serialized
/// and how transaction identifiers are computed.
pub opaque type Transaction(validation_state) {
  /// A legacy (non-SegWit) transaction.
  ///
  /// Legacy transactions do not include witness data and compute their
  /// transaction identifier (txid) from the full serialization.
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
  /// SegWit transactions separate witness data from the main transaction
  /// serialization and compute both a txid (non-witness data) and a wtxid
  /// (full serialization including witness data).
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

pub fn get_version(tx: Transaction(v)) -> Int {
  tx.version
}

pub fn is_segwit(tx: Transaction(v)) -> Bool {
  case tx {
    Legacy(..) -> False
    SegWit(..) -> True
  }
}

pub fn is_coinbase(tx: Transaction(Validated)) -> Bool {
  list.any(tx.inputs, fn(txin) { prev_out_is_coinbase(txin.prev_out) })
}

/// Get all transaction inputs in order.
pub fn get_inputs(tx: Transaction(v)) -> List(TxIn) {
  tx.inputs
}

/// Get all transaction outputs in order.
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
/// Returns `Ok(witnesses)` if this is a `SegWit` transaction, or `Error(Nil)` if
/// it's a `Legacy` transaction (which has no witness data).
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
    script_sig: ScriptBytes,
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
pub fn get_input_script_sig(input: TxIn) -> ScriptBytes {
  input.script_sig
}

/// A reference to a previous transaction output.
///
/// This identifies the output being consumed by a transaction input.
pub opaque type PrevOut {
  /// A special marker used by coinbase transactions.
  ///
  /// Coinbase inputs do not reference a previous transaction output.
  Coinbase

  /// A reference to a specific output of a previous transaction.
  ///
  /// `txid` identifies the transaction, and `vout` is the zero-based index
  /// of the output within that transaction.
  OutPoint(txid: TxId, vout: Int)
}

/// Check whether a previous output reference is a coinbase marker.
///
/// Returns `True` if this is a `Coinbase`  input (which does not reference any
/// previous transaction output), `False` if it is a regular `OutPoint`.
pub fn prev_out_is_coinbase(prev_out: PrevOut) -> Bool {
  case prev_out {
    Coinbase -> True
    OutPoint(..) -> False
  }
}

/// Get the transaction ID from a previous output reference.
///
/// For a regular `OutPoint`, returns the transaction ID of the referenced output.
/// For a `Coinbase` input, returns an all-zero hash.
pub fn get_prev_out_txid(prev_out: PrevOut) -> TxId {
  case prev_out {
    Coinbase -> {
      let assert Ok(hash32) = hash32.from_bytes_le(<<0:size(256)>>)
      TxId(hash32)
    }
    OutPoint(txid:, ..) -> txid
  }
}

/// Get the output index from a previous output reference.
///
/// For a regular `OutPoint`, returns the zero-based index of the output within
/// the referenced transaction. For a `Coinbase` input, returns `0xFFFFFFFF` (the
/// special sentinel value indicating no previous output).
pub fn get_prev_out_vout(prev_out: PrevOut) -> Int {
  case prev_out {
    Coinbase -> 0xFFFFFFFF
    OutPoint(vout:, ..) -> vout
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
    value: Satoshis,
    /// The locking script (scriptPubKey) defining the spending conditions.
    script_pubkey: ScriptBytes,
  )
}

/// Get the satoshi value assigned to a transaction output.
///
/// Returns the number of satoshis that will be available to spend if the
/// output's spending conditions (specified by scriptPubKey) are satisfied.
pub fn get_output_value(output: TxOut) -> Satoshis {
  output.value
}

/// Get the locking script from a transaction output.
///
/// Returns the scriptPubKey that defines the conditions under which this
/// output may be spent. The script is interpreted together with a spending
/// input's scriptSig during script validation.
pub fn get_output_script_pubkey(output: TxOut) -> ScriptBytes {
  output.script_pubkey
}

/// Raw Bitcoin script bytes.
///
/// This type represents an uninterpreted script as it appears on the wire.
/// No validation or opcode parsing is performed at this level.
pub opaque type ScriptBytes {
  ScriptBytes(BitArray)
}

/// Get the raw bytes from a `ScriptBytes`.
pub fn get_raw_script_bytes(script: ScriptBytes) -> BitArray {
  let ScriptBytes(bytes) = script
  bytes
}

/// A quantity of satoshis. (1 Bitcoin = 100,000,000 Satoshis)
///
/// A satoshi is the smallest unit of Bitcoin.
/// Valid values are non-negative and bounded by the consensus maximum money supply.
pub opaque type Satoshis {
  Satoshis(Int)
}

/// Convert a satoshi quantity to its integer representation.
pub fn satoshis_to_int(sats: Satoshis) -> Int {
  let Satoshis(value) = sats
  value
}

/// The transaction identifier (txid).
///
/// This is the double SHA-256 hash of the transaction’s
/// non-witness serialization and is distinct from the wtxid.
pub opaque type TxId {
  TxId(Hash32)
}

/// Convert a transaction ID to its raw byte representation.
///
/// Returns the 32 bytes of the transaction ID in little-endian byte order,
/// as they would appear in Bitcoin transactions and on the wire.
pub fn txid_to_bytes(txid: TxId) -> BitArray {
  let TxId(hash32) = txid
  hash32.to_bytes_le(hash32)
}

/// The witness transaction identifier (wtxid).
///
/// This is the double SHA-256 hash of the transaction’s
/// full serialization, including witness data.
pub opaque type WtxId {
  WtxId(Hash32)
}

// ---- Error handling ----

/// An error that occurred while decoding a Bitcoin transaction.
///
/// This error type distinguishes between failures that occur during hex-to-bytes
/// conversion and failures that occur during transaction parsing.
pub type DecodeError {
  /// The hexadecimal string could not be converted to bytes.
  ///
  /// This occurs before any transaction parsing begins, typically due to an
  /// odd-length hex string or the presence of invalid hexadecimal characters.
  HexToBytesFailed(hex.HexToBytesError)

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
/// This type categorizes parsing failures into distinct categories, ranging from
/// low-level binary reading errors to semantic constraint violations.
pub type ParseErrorKind {
  /// A low-level binary reader operation failed.
  ///
  /// This error wraps failures from the underlying `Reader`, such as attempting
  /// to read beyond the end of the input or requesting an invalid number of bytes.
  ReaderError(reader.ReaderError)

  /// A CompactSize-encoded integer could not be parsed.
  ///
  /// This error wraps failures from CompactSize decoding operations, such as
  /// encountering an unexpected end of input or detecting a non-minimal encoding
  /// that violates Bitcoin's canonical serialization rules.
  CompactSizeError(compact_size.CompactSizeError)

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
  ///
  /// This should be used sparingly and primarily for truly exceptional cases.
  Other(message: String)
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

  /// The error occurred while parsing or validating a specific logical field.
  ///
  /// This is typically used to label reads of fixed-size or length-prefixed
  /// fields such as `"version"`, `"sequence"`, `"lock_time"`, `"script_sig"`,
  /// or `"script_pubkey"`.
  AtField(String)
}

pub fn parse_error_offset(err: ParseError) -> Int {
  err.offset
}

pub fn parse_error_kind(err: ParseError) -> ParseErrorKind {
  err.kind
}

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
  field_name: String,
  offset: Int,
  ctx: List(ParseContext),
) -> fn(ParseErrorKind) -> DecodeError {
  fn(kind) {
    kind
    |> new_parse_error(offset)
    |> with_contexts([AtField(field_name), ..ctx])
    |> ParseFailed
  }
}

// ---- Parser functions ----

/// Lift a reader operation into a Parser, adding error mapping and context wrapping.
fn read_field(
  field_name: String,
  read_fn: fn(Reader) -> Result(#(Reader, a), reader.ReaderError),
) -> Parser(ParseContext, a, DecodeError) {
  parser.new(fn(reader, ctx) {
    reader
    |> read_fn
    |> result.map_error(fn(err) {
      err
      |> ReaderError
      |> new_parse_error(reader.get_offset(reader))
      |> with_contexts([AtField(field_name), ..ctx])
      |> ParseFailed
    })
  })
}

/// Lift a compact_size read into a Parser, adding error mapping and context wrapping.
fn read_compact_size(
  field_name: String,
) -> Parser(ParseContext, Uint64, DecodeError) {
  parser.new(fn(reader, ctx) {
    reader
    |> compact_size.read
    |> result.map_error(fn(err) {
      err
      |> CompactSizeError
      |> new_parse_error(reader.get_offset(reader))
      |> with_contexts([AtField(field_name), ..ctx])
      |> ParseFailed
    })
  })
}

/// Read a CompactSize value and convert it to `Int` with appropriate error handling.
///
/// This wraps `read_compact_size` and handles the common pattern of converting
/// the `Uint64` result to `Int`, mapping conversion failures to `IntegerOutOfRange` errors.
fn read_compact_size_as_int(
  field_name: String,
) -> Parser(ParseContext, Int, DecodeError) {
  field_name
  |> read_compact_size
  |> parser.try_with_start_offset(fn(value_u64, start_offset, _, ctx) {
    value_u64
    |> uint64.to_int
    |> result.map_error(fn(_) {
      value_u64
      |> uint64.to_string
      |> IntegerOutOfRange
      |> make_field_error(field_name, start_offset, ctx)
    })
  })
}

// ---- Decoding functions ----

pub type DecodePolicy {
  DecodePolicy(
    max_vin_count: Int,
    max_vout_count: Int,
    max_script_size: Int,
    witness_policy: WitnessPolicy,
  )
}

pub type WitnessPolicy {
  WitnessPolicy(
    max_item_size: Int,
    max_items_per_input: Int,
    max_stack_payload_bytes_per_input: Int,
  )
}

pub const default_witness_policy = WitnessPolicy(
  max_item_size: 100,
  max_items_per_input: 10_000,
  max_stack_payload_bytes_per_input: 100_000,
)

pub const default_policy = DecodePolicy(
  max_vin_count: 100_000,
  max_vout_count: 100_000,
  max_script_size: 10_000,
  witness_policy: default_witness_policy,
)

// 21_000_000 bitcoins * 100_000_000 satoshis in a bitcoin
const max_satoshis = 2_100_000_000_000_000

pub fn decode(bytes: BitArray) -> Result(Transaction(Unvalidated), DecodeError) {
  decode_with_policy(bytes, default_policy)
}

pub fn decode_with_policy(
  bytes: BitArray,
  policy: DecodePolicy,
) -> Result(Transaction(Unvalidated), DecodeError) {
  let tx_parser = {
    use version <- parser.then(read_field("version", reader.read_i32_le))

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
        read_witness_stacks(list.length(inputs), policy.witness_policy)
        |> parser.map(Some)

      False -> parser.return(None)
    })

    use lock_time <- parser.then(read_field("lock_time", reader.read_u32_le))

    // Build transaction and verify no trailing bytes
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

pub fn decode_hex(hex: String) -> Result(Transaction(Unvalidated), DecodeError) {
  hex
  |> hex.hex_to_bytes
  |> result.map_error(HexToBytesFailed)
  |> result.try(decode)
}

/// Detect whether this is a SegWit transaction by peeking at the marker/flag bytes.
///
/// Returns `True` if SegWit marker (0x00, 0x01) is present,`False` otherwise.
/// Side effect: consumes the marker/flag bytes if SegWit is detected.
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
/// Returns `True` if next bytes are 0x00 0x01, `False` if they don't start with 0x00
/// or on EOF. Returns an error if marker is 0x00 but flag is invalid.
fn peek_segwit() -> Parser(ParseContext, Bool, DecodeError) {
  // Uses `parser.new` directly due to special peek semantics and EOF error recovery.
  parser.new(fn(reader, ctx) {
    let field_err =
      make_field_error("segwit_discriminator", reader.get_offset(reader), ctx)

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

      Error(err) ->
        case err {
          // Ambiguity-aware: do not fail the whole decode just because we couldn't look ahead.
          // Let the later parsing produce a better contextual EOF.
          reader.UnexpectedEof(..) -> Ok(#(reader, False))
          _ ->
            err
            |> ReaderError
            |> field_err
            |> Error
        }
    }
  })
}

/// Helper parser that consumes the 2-byte segwit discriminator
fn skip_marker_bytes() -> Parser(ParseContext, Nil, DecodeError) {
  "segwit_marker"
  |> read_field(fn(reader) {
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
  let field_name = "vin_count"

  field_name
  |> read_compact_size_as_int
  |> parser.try_with_start_offset(fn(vin_count_int, start_offset, reader, ctx) {
    let on_invalid = fn(kind) {
      kind
      |> make_field_error(field_name, start_offset, ctx)
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
    read_script("scriptSig", max_script_size_policy),
    read_field("sequence", reader.read_u32_le),
    TxIn,
  )
}

fn read_prev_out() -> Parser(ParseContext, PrevOut, DecodeError) {
  parser.map2(
    read_field("prev_txid", reader.read_bytes(_, 32)),
    read_field("vout", reader.read_u32_le),
    fn(prev_txid_bytes, vout) {
      case prev_txid_bytes, vout {
        <<0:size(256)>>, 0xFFFFFFFF -> Coinbase

        _, _ -> {
          // Safe: read_bytes(_, 32) guarantees exactly 32 bytes on success
          let assert Ok(hash32) = hash32.from_bytes_le(prev_txid_bytes)
          OutPoint(TxId(hash32), vout)
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
  let field_name = "vout_count"

  field_name
  |> read_compact_size_as_int
  |> parser.try_with_start_offset(fn(vout_count_int, start_offset, reader, ctx) {
    let on_invalid = fn(kind) {
      kind
      |> make_field_error(field_name, start_offset, ctx)
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
    read_script("scriptPubKey", max_script_size_policy),
    TxOut,
  )
}

fn read_satoshis() -> Parser(ParseContext, Satoshis, DecodeError) {
  let field_name = "value"

  field_name
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
      |> make_field_error(field_name, start_offset, ctx)
    })
    |> result.map(Satoshis)
  })
}

fn read_script(
  field_name: String,
  max_script_size_policy: Int,
) -> Parser(ParseContext, ScriptBytes, DecodeError) {
  { field_name <> "_len" }
  |> read_script_length(max_script_size_policy)
  |> parser.then(fn(script_len) {
    read_field(field_name, reader.read_bytes(_, script_len))
  })
  |> parser.map(ScriptBytes)
}

/// Read and validate a script length field.
///
/// Reads a CompactSize length, converts it to Int, validates it against
/// max_script_size_policy, and ensures sufficient bytes remain.
fn read_script_length(
  field_name: String,
  max_script_size_policy: Int,
) -> Parser(ParseContext, Int, DecodeError) {
  field_name
  |> read_compact_size_as_int
  |> parser.try_with_start_offset(fn(script_len_int, start_offset, reader, ctx) {
    let on_invalid = fn(kind) {
      kind
      |> make_field_error(field_name, start_offset, ctx)
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

fn read_witness_stacks(
  vin_count: Int,
  policy: WitnessPolicy,
) -> Parser(ParseContext, List(WitnessStack), DecodeError) {
  parser.indexed_repeat(vin_count, read_witness_stack(policy), AtWitnessStack)
}

fn read_witness_stack(
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
      |> make_field_error("witnessStack_total_payload_bytes", start_offset, ctx)
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
    read_field("witnessItem", reader.read_bytes(_, length))
  })
  |> parser.map(WitnessItem)
}

/// Read and validate a witness stack length field.
///
/// Reads a CompactSize length, converts it to Int, and validates it against
/// max_items_per_input policy.
fn read_witness_stack_length(
  max_items_per_input_policy: Int,
) -> Parser(ParseContext, Int, DecodeError) {
  let field_name = "witnessStack_len"

  field_name
  |> read_compact_size_as_int
  |> parser.try_with_start_offset(fn(stack_len, start_offset, _, ctx) {
    let on_invalid = fn(kind) {
      kind
      |> make_field_error(field_name, start_offset, ctx)
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

fn read_witness_item_size(
  max_item_size_policy: Int,
) -> Parser(ParseContext, Int, DecodeError) {
  let field_name = "witnessItem_len"

  field_name
  |> read_compact_size_as_int
  |> parser.try_with_start_offset(fn(length, start_offset, reader, ctx) {
    let on_invalid = fn(kind) {
      kind
      |> make_field_error(field_name, start_offset, ctx)
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

// ---- Validate Consensus functions ----

/// An error that occurred during consensus validation of a Bitcoin transaction.
///
/// These errors represent violations of Bitcoin's consensus rules that would
/// cause a transaction to be rejected by the network.
pub type ValidationError {
  /// The transaction has no inputs.
  ///
  /// All Bitcoin transactions must have at least one input.
  NoInputs

  /// The transaction has no outputs.
  ///
  /// All Bitcoin transactions must have at least one output.
  NoOutputs

  /// An output has a negative value.
  ///
  /// Output values must be non-negative.
  NegativeOutputValue

  /// An individual output's value exceeds the maximum possible supply.
  ///
  /// No single output can contain more than 21 million BTC (2.1 quadrillion satoshis).
  OutputValueExceedsSupply

  /// The sum of all output values exceeds the maximum possible supply.
  ///
  /// The total value of all outputs cannot exceed 21 million BTC (2.1 quadrillion satoshis).
  TotalOutputValueExceedsSupply

  /// A coinbase transaction has more than one input.
  ///
  /// Coinbase transactions (those with a coinbase input) must have exactly one input.
  CoinbaseWithMultipleInputs

  /// A transaction has multiple coinbase inputs.
  ///
  /// A transaction cannot contain more than one coinbase input.
  MultipleCoinbaseInputs

  /// A coinbase transaction's scriptSig length is invalid.
  ///
  /// Coinbase scriptSig must be between 2 and 100 bytes (inclusive).
  InvalidCoinbaseScriptSigLength
}

pub fn validate_consensus(
  tx: Transaction(Unvalidated),
) -> Result(Transaction(Validated), List(ValidationError)) {
  let validators = [
    validate_at_least_one_input,
    validate_at_least_one_output,
    validate_output_values,
    validate_coinbase_structure,
    validate_coinbase_scriptsig_length,
  ]

  validators
  |> list.map(fn(validator) { validator(tx) })
  |> list.filter_map(fn(result) {
    case result {
      Error(err) -> Ok(err)
      Ok(_) -> Error(Nil)
    }
  })
  |> fn(errors) {
    case errors {
      [] -> {
        Ok(case tx {
          Legacy(v, i, o, l) -> Legacy(v, i, o, l)
          SegWit(v, i, o, l, w) -> SegWit(v, i, o, l, w)
        })
      }
      _ -> Error(errors)
    }
  }
}

fn validate_at_least_one_input(
  tx: Transaction(Unvalidated),
) -> Result(Nil, ValidationError) {
  case list.is_empty(tx.inputs) {
    True -> Error(NoInputs)
    False -> Ok(Nil)
  }
}

fn validate_at_least_one_output(
  tx: Transaction(Unvalidated),
) -> Result(Nil, ValidationError) {
  case list.is_empty(tx.outputs) {
    True -> Error(NoOutputs)
    False -> Ok(Nil)
  }
}

fn validate_output_values(
  tx: Transaction(Unvalidated),
) -> Result(Nil, ValidationError) {
  tx.outputs
  |> list.fold_until(Ok(0), fn(acc, output) {
    let assert Ok(sum) = acc
    let sats = output.value

    case sats {
      Satoshis(s) if s < 0 -> Stop(Error(NegativeOutputValue))
      Satoshis(s) if s > max_satoshis -> Stop(Error(OutputValueExceedsSupply))
      Satoshis(s) -> Continue(Ok(sum + s))
    }
  })
  |> result.try(fn(total_sats) {
    case total_sats > max_satoshis {
      True -> Error(TotalOutputValueExceedsSupply)
      False -> Ok(Nil)
    }
  })
}

fn validate_coinbase_structure(
  tx: Transaction(Unvalidated),
) -> Result(Nil, ValidationError) {
  let coinbase_count =
    list.count(tx.inputs, fn(txin) { prev_out_is_coinbase(txin.prev_out) })

  case coinbase_count {
    0 -> Ok(Nil)
    1 ->
      case list.length(tx.inputs) == 1 {
        True -> Ok(Nil)
        False -> Error(CoinbaseWithMultipleInputs)
      }
    _ -> Error(MultipleCoinbaseInputs)
  }
}

fn validate_coinbase_scriptsig_length(
  tx: Transaction(Unvalidated),
) -> Result(Nil, ValidationError) {
  case tx.inputs {
    [] -> Ok(Nil)

    [input] ->
      case prev_out_is_coinbase(input.prev_out) {
        True -> {
          let ScriptBytes(bytes) = input.script_sig
          let script_sig_size = bit_array.byte_size(bytes)

          case 2 <= script_sig_size && script_sig_size <= 100 {
            True -> Ok(Nil)
            False -> Error(InvalidCoinbaseScriptSigLength)
          }
        }

        False -> Ok(Nil)
      }

    _ -> Ok(Nil)
  }
}
