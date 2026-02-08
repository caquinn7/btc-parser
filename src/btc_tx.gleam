//// btc_tx provides facilities for parsing and modeling Bitcoin transaction data
//// in a form suitable for inspection, analysis, and reference.

import gleam/bit_array
import gleam/bool
import gleam/list.{Continue, Stop}
import gleam/option.{type Option, None, Some}
import gleam/pair
import gleam/result
import internal/compact_size
import internal/fixed_int/int64
import internal/fixed_int/uint64.{type Uint64}
import internal/hash32.{type Hash32}
import internal/hex
import internal/reader.{type Reader}

// ---- Transaction types ----

/// A Bitcoin transaction.
///
/// A transaction transfers value by consuming previously created outputs
/// (inputs) and creating new outputs. Transactions are either legacy
/// (pre-SegWit) or SegWit, which affects how witness data is serialized
/// and how transaction identifiers are computed.
pub opaque type Transaction {
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
  Segwit(
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

pub fn get_version(tx: Transaction) -> Int {
  tx.version
}

pub fn is_segwit(tx: Transaction) -> Bool {
  case tx {
    Legacy(..) -> False
    Segwit(..) -> True
  }
}

/// Get all transaction inputs in order.
pub fn get_inputs(tx: Transaction) -> List(TxIn) {
  tx.inputs
}

/// Get all transaction outputs in order.
pub fn get_outputs(tx: Transaction) -> List(TxOut) {
  tx.outputs
}

/// Get the lock time from a transaction.
///
/// Lock time specifies when this transaction is valid:
/// - Values less than 500,000,000 are interpreted as block heights
/// - Values greater than or equal to 500,000,000 are interpreted as Unix timestamps
/// - A value of 0 means the transaction is valid immediately
pub fn get_lock_time(tx: Transaction) -> Int {
  tx.lock_time
}

/// Get the witness stacks from a SegWit transaction.
///
/// Returns `Ok(witnesses)` if this is a `SegWit` transaction, or `Error(Nil)` if
/// it's a `Legacy` transaction (which has no witness data).
pub fn get_witnesses(tx: Transaction) -> Result(List(WitnessStack), Nil) {
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

  /// An error variant indicating that an invalid Segwit marker flag was encountered.
  ///
  /// - `marker`: The marker byte that was found
  /// - `flag`: The flag byte that was found
  InvalidSegwitMarkerFlag(marker: Int, flag: Int)

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
  /// `value` is the exceeded value, and `max` is the policy limit.
  PolicyLimitExceeded(value: Int, max: Int)

  /// A decoded numeric value fell outside the allowed range for the given field.
  ///
  /// The value was successfully decoded from well-formed input, but is rejected
  /// because it violates semantic constraints or consensus rules implied by the
  /// field's meaning (for example, negative satoshi amounts, satoshi values exceeding
  /// the maximum money supply, or counts below their required minimum).
  ///
  /// `value` is the decoded value, and `min` / `max` define the permitted inclusive range.
  InvalidValueRange(value: Int, min: Option(Int), max: Option(Int))

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
  /// (the `vin` field).
  Inputs

  /// The error occurred while parsing a specific input within the input vector.
  ///
  /// The wrapped `Int` is the zero-based index of the input being parsed.
  AtInput(Int)

  /// The error occurred while parsing the transaction’s output vector
  /// (the `vout` field).
  Outputs

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

fn new_parse_error(kind: ParseErrorKind, reader: Reader) -> ParseError {
  ParseError(reader.get_offset(reader), kind:, ctx: [])
}

fn with_contexts(err: ParseError, ctx: List(ParseContext)) -> ParseError {
  list.fold(ctx, err, fn(err, ctx) { ParseError(..err, ctx: [ctx, ..err.ctx]) })
}

/// Build a DecodeError factory function for a specific field.
///
/// Returns a function that takes a ParseErrorKind and produces a DecodeError
/// with the field context already applied.
fn make_field_error(
  field_name: String,
  reader: Reader,
  ctx: List(ParseContext),
) -> fn(ParseErrorKind) -> DecodeError {
  fn(kind) {
    kind
    |> new_parse_error(reader)
    |> with_contexts([AtField(field_name), ..ctx])
    |> ParseFailed
  }
}

// ---- Context-threading parser combinators ----

/// A parsing computation that threads both the `Reader` and `ParseContext`.
///
/// This allows us to use Gleam's `use` syntax to elegantly compose parsing
/// operations while automatically managing context propagation.
type Parser(a) =
  fn(Reader, List(ParseContext)) -> Result(#(Reader, a), DecodeError)

// -- Combinators: functions that combine or transform parsers

/// Run a Parser computation with an initial reader and context.
/// 
/// Combinator: chains parsers together using `use` syntax.
fn run_parse(
  reader: Reader,
  ctx: List(ParseContext),
  parser: Parser(a),
  next: fn(Reader, a) -> Result(b, DecodeError),
) -> Result(b, DecodeError) {
  use #(reader, value) <- result.try(parser(reader, ctx))
  next(reader, value)
}

/// Add a context layer to a parsing computation.
///
/// Combinator: wraps a Parser to prepend context to its context list.
fn in_context(ctx: ParseContext, parser: Parser(a)) -> Parser(a) {
  fn(reader, outer_ctx) { parser(reader, [ctx, ..outer_ctx]) }
}

// -- Parsers: functions that create parsers for specific data types

/// Lift a reader operation into a Parser, adding error mapping and context wrapping.
fn read_field(
  field_name: String,
  read_fn: fn(Reader) -> Result(#(Reader, a), reader.ReaderError),
) -> Parser(a) {
  fn(reader, ctx) {
    reader
    |> read_fn
    |> result.map_error(fn(err) {
      err
      |> ReaderError
      |> new_parse_error(reader)
      |> with_contexts([AtField(field_name), ..ctx])
      |> ParseFailed
    })
  }
}

/// Lift a compact_size read into a Parser, adding error mapping and context wrapping.
fn read_compact_size(field_name: String) -> Parser(Uint64) {
  fn(reader, ctx) {
    reader
    |> compact_size.read
    |> result.map_error(fn(err) {
      err
      |> CompactSizeError
      |> new_parse_error(reader)
      |> with_contexts([AtField(field_name), ..ctx])
      |> ParseFailed
    })
  }
}

/// Read a CompactSize value and convert it to `Int` with appropriate error handling.
///
/// This wraps `read_compact_size` and handles the common pattern of converting
/// the `Uint64` result to `Int`, mapping conversion failures to `IntegerOutOfRange` errors.
fn read_compact_size_as_int(field_name: String) -> Parser(Int) {
  fn(reader, ctx) {
    let start_reader = reader

    use reader, value_u64 <- run_parse(
      reader,
      ctx,
      read_compact_size(field_name),
    )

    use value_int <- result.try(
      value_u64
      |> uint64.to_int
      |> result.map_error(fn(_) {
        value_u64
        |> uint64.to_string
        |> IntegerOutOfRange
        |> make_field_error(field_name, start_reader, ctx)
      }),
    )

    Ok(#(reader, value_int))
  }
}

/// Read a vector of items by repeatedly calling a parser for each index.
///
/// Returns items in the order they appear in the binary stream.
fn read_vec(length: Int, create_parser: fn(Int) -> Parser(a)) -> Parser(List(a)) {
  fn(reader, ctx) {
    use <- bool.guard(length <= 0, Ok(#(reader, [])))

    let indices = list.range(0, length - 1)
    let init = Ok(#(reader, []))

    indices
    |> list.fold_until(init, fn(acc, index) {
      case acc {
        Ok(#(current_reader, items)) -> {
          let item_parser = create_parser(index)

          case item_parser(current_reader, ctx) {
            Ok(#(next_reader, item)) ->
              Continue(Ok(#(next_reader, [item, ..items])))

            Error(err) -> Stop(Error(err))
          }
        }

        Error(_) -> Stop(acc)
      }
    })
    |> result.map(pair.map_second(_, list.reverse))
  }
}

/// Read a vector of items while tracking a cumulative metric.
///
/// This is a generic combinator that accumulates a metric across items and
/// validates it doesn't exceed a maximum value. The `create_parser` function
/// receives the index and returns a parser that produces both the item and
/// its contribution to the metric as a tuple `#(item, metric_value)`.
///
/// The metric values are summed together, and parsing fails fast if the 
/// cumulative sum exceeds `limit`. The error is created by calling 
/// `limit_exceeded_err` with the exceeded value and contextualized with `field_name`.
fn read_vec_with_cumulative_limit(
  length: Int,
  limit: Int,
  field_name: String,
  create_parser: fn(Int) -> Parser(#(a, Int)),
  limit_exceeded_err: fn(Int) -> ParseErrorKind,
) -> Parser(List(a)) {
  fn(reader, ctx) {
    use <- bool.guard(length <= 0, Ok(#(reader, [])))

    let indices = list.range(0, length - 1)
    let init = Ok(#(reader, [], 0))

    indices
    |> list.fold_until(init, fn(acc, index) {
      case acc {
        Ok(#(reader, items, acc_val)) -> {
          let item_parser = create_parser(index)

          case item_parser(reader, ctx) {
            Ok(#(reader, #(item, item_val))) -> {
              let acc_val = acc_val + item_val
              case acc_val > limit {
                True ->
                  limit_exceeded_err(acc_val)
                  |> make_field_error(field_name, reader, ctx)
                  |> Error
                  |> Stop

                False -> Continue(Ok(#(reader, [item, ..items], acc_val)))
              }
            }

            Error(err) -> Stop(Error(err))
          }
        }

        Error(_) -> Stop(acc)
      }
    })
    |> result.map(fn(acc) { #(acc.0, list.reverse(acc.1)) })
  }
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

pub fn decode(bytes: BitArray) -> Result(Transaction, DecodeError) {
  decode_with_policy(bytes, default_policy)
}

pub fn decode_with_policy(
  bytes: BitArray,
  policy: DecodePolicy,
) -> Result(Transaction, DecodeError) {
  let reader = reader.new(bytes)
  let tx_ctx = [InTransaction]

  // version
  use reader, version <- run_parse(
    reader,
    tx_ctx,
    read_field("version", reader.read_i32_le),
  )

  // segwit?
  use reader, is_segwit <- run_parse(reader, tx_ctx, detect_segwit())

  // inputs
  use reader, inputs <- run_parse(
    reader,
    tx_ctx,
    in_context(
      Inputs,
      read_inputs(policy.max_vin_count, policy.max_script_size),
    ),
  )

  // outputs
  use reader, outputs <- run_parse(
    reader,
    tx_ctx,
    in_context(
      Outputs,
      read_outputs(policy.max_vout_count, policy.max_script_size),
    ),
  )

  // Parse witnesses if segwit
  use #(reader, witnesses) <- result.try(case is_segwit {
    True -> {
      use reader, witnesses <- run_parse(
        reader,
        tx_ctx,
        read_witness_stacks(list.length(inputs), policy.witness_policy),
      )
      Ok(#(reader, Some(witnesses)))
    }

    False -> Ok(#(reader, None))
  })

  // lock_time (common to both paths)
  use reader, lock_time <- run_parse(
    reader,
    tx_ctx,
    read_field("lock_time", reader.read_u32_le),
  )

  let tx = case witnesses {
    Some(witnesses) ->
      Segwit(version:, inputs:, outputs:, lock_time:, witnesses:)

    None -> Legacy(version:, inputs:, outputs:, lock_time:)
  }

  case reader.bytes_remaining(reader) {
    0 -> Ok(tx)

    byte_count ->
      byte_count
      |> TrailingBytes
      |> new_parse_error(reader)
      |> with_contexts(tx_ctx)
      |> ParseFailed
      |> Error
  }
}

pub fn decode_hex(hex: String) -> Result(Transaction, DecodeError) {
  hex
  |> hex.hex_to_bytes
  |> result.map_error(HexToBytesFailed)
  |> result.try(decode)
}

/// Detect whether this is a SegWit transaction by peeking at the marker/flag bytes.
///
/// Returns `True` if SegWit marker (0x00, 0x01) is present,`False` otherwise.
/// Side effect: consumes the marker/flag bytes if SegWit is detected.
fn detect_segwit() -> Parser(Bool) {
  fn(reader, ctx) {
    use reader, is_segwit <- run_parse(reader, ctx, peek_segwit())

    let reader = case is_segwit {
      True -> {
        // safe to assert because we already peeked the next two bytes
        let assert Ok(reader) = reader.skip_bytes(reader, 2)
        reader
      }
      False -> reader
    }

    Ok(#(reader, is_segwit))
  }
}

/// Peek ahead at the next two bytes to check for SegWit marker/flag.
///
/// Returns `True` if next bytes are 0x00 0x01, `False` if they don't start with 0x00
/// or on EOF. Returns an error if marker is 0x00 but flag is invalid.
fn peek_segwit() -> Parser(Bool) {
  fn(reader, ctx) {
    case reader.peek_bytes(reader, 2) {
      Ok(bytes) -> {
        let assert <<marker, flag>> = bytes
        case marker, flag {
          0x00, 0x01 -> Ok(#(reader, True))
          0x00, _ ->
            InvalidSegwitMarkerFlag(marker, flag)
            |> new_parse_error(reader)
            |> with_contexts([AtField("segwit_discriminator"), ..ctx])
            |> ParseFailed
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
            |> new_parse_error(reader)
            |> with_contexts([AtField("segwit_discriminator"), ..ctx])
            |> ParseFailed
            |> Error
        }
    }
  }
}

fn read_inputs(
  max_vin_count_policy: Int,
  max_script_size_policy: Int,
) -> Parser(List(TxIn)) {
  fn(reader, ctx) {
    use reader, vin_count <- run_parse(
      reader,
      ctx,
      read_vin_count(max_vin_count_policy),
    )
    use reader, inputs <- run_parse(
      reader,
      ctx,
      read_tx_ins(vin_count, max_script_size_policy),
    )
    Ok(#(reader, inputs))
  }
}

/// Validate and convert the vin_count from Uint64 to Int, checking structural and policy limits.
fn read_vin_count(max_vin_count_policy: Int) -> Parser(Int) {
  fn(reader, ctx) {
    use reader, vin_count_int <- run_parse(
      reader,
      ctx,
      read_compact_size_as_int("vin_count"),
    )

    let min_txin_size = 41
    let remaining = reader.bytes_remaining(reader)

    // Upper bound implied by remaining bytes (each input is at least 41 bytes)
    let max_inputs_by_bytes = remaining / min_txin_size

    let vin_count_err = fn(parse_error_kind) {
      parse_error_kind
      |> make_field_error("vin_count", reader, ctx)
      |> Error
    }

    case
      vin_count_int < 1,
      vin_count_int > max_inputs_by_bytes,
      vin_count_int > max_vin_count_policy
    {
      // Minimum count validation
      True, _, _ ->
        InvalidValueRange(vin_count_int, Some(1), None)
        |> vin_count_err

      // Structural limit: count exceeds what remaining bytes can accommodate
      False, True, _ ->
        InsufficientBytes(claimed: remaining + 1, remaining:)
        |> vin_count_err

      // Policy limit: count exceeds configured maximum
      False, False, True ->
        PolicyLimitExceeded(vin_count_int, max_vin_count_policy)
        |> vin_count_err

      // All validations passed
      False, False, False -> Ok(#(reader, vin_count_int))
    }
  }
}

fn read_tx_ins(
  vin_count: Int,
  max_script_size_policy: Int,
) -> Parser(List(TxIn)) {
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
  read_vec(vin_count, fn(index) {
    in_context(AtInput(index), read_tx_in(max_script_size_policy))
  })
}

fn read_tx_in(max_script_size_policy: Int) -> Parser(TxIn) {
  // │ prev_txid (32 bytes)
  // │ vout (4 bytes)
  // │ scriptSig_len (CompactSize)
  // │ scriptSig bytes
  // │ sequence (4 bytes)
  fn(reader, ctx) {
    use reader, prev_out <- run_parse(reader, ctx, read_prev_out())
    use reader, script_sig <- run_parse(
      reader,
      ctx,
      read_script("scriptSig", max_script_size_policy),
    )
    use reader, sequence <- run_parse(
      reader,
      ctx,
      read_field("sequence", reader.read_u32_le),
    )

    Ok(#(reader, TxIn(prev_out:, script_sig:, sequence:)))
  }
}

fn read_prev_out() -> Parser(PrevOut) {
  fn(reader, ctx) {
    use reader, prev_txid_bytes <- run_parse(
      reader,
      ctx,
      read_field("prev_txid", reader.read_bytes(_, 32)),
    )

    use reader, vout <- run_parse(
      reader,
      ctx,
      read_field("vout", reader.read_u32_le),
    )

    let prev_out = case prev_txid_bytes, vout {
      <<0:size(256)>>, 0xFFFFFFFF -> Coinbase

      _, _ -> {
        // Safe: read_bytes(_, 32) guarantees exactly 32 bytes on success
        let assert Ok(hash32) = hash32.from_bytes_le(prev_txid_bytes)
        OutPoint(TxId(hash32), vout)
      }
    }

    Ok(#(reader, prev_out))
  }
}

fn read_outputs(
  max_vout_count_policy: Int,
  max_script_size_policy: Int,
) -> Parser(List(TxOut)) {
  fn(reader, ctx) {
    use reader, vout_count <- run_parse(
      reader,
      ctx,
      read_vout_count(max_vout_count_policy),
    )
    use reader, outputs <- run_parse(
      reader,
      ctx,
      read_tx_outs(vout_count, max_script_size_policy),
    )
    Ok(#(reader, outputs))
  }
}

/// Validate and convert the vout_count from Uint64 to Int, checking structural and policy limits.
fn read_vout_count(max_vout_count_policy: Int) -> Parser(Int) {
  fn(reader, ctx) {
    use reader, vout_count_int <- run_parse(
      reader,
      ctx,
      read_compact_size_as_int("vout_count"),
    )

    let min_txout_size = 9
    let remaining = reader.bytes_remaining(reader)

    // Upper bound implied by remaining bytes (each output is at least 9 bytes)
    let max_outputs_by_bytes = remaining / min_txout_size

    let vout_count_err = fn(parse_error_kind) {
      parse_error_kind
      |> make_field_error("vout_count", reader, ctx)
      |> Error
    }

    case
      vout_count_int < 1,
      vout_count_int > max_outputs_by_bytes,
      vout_count_int > max_vout_count_policy
    {
      // Minimum count validation
      True, _, _ ->
        InvalidValueRange(vout_count_int, Some(1), None)
        |> vout_count_err

      // Structural limit: count exceeds what remaining bytes can accommodate
      False, True, _ ->
        InsufficientBytes(claimed: remaining + 1, remaining:)
        |> vout_count_err

      // Policy limit: count exceeds configured maximum
      False, False, True ->
        PolicyLimitExceeded(vout_count_int, max_vout_count_policy)
        |> vout_count_err

      // All validations passed
      False, False, False -> Ok(#(reader, vout_count_int))
    }
  }
}

fn read_tx_outs(
  vout_count: Int,
  max_script_size_policy: Int,
) -> Parser(List(TxOut)) {
  // vout_count
  // ├─ TxOut #0
  // │    ├─ value (8 bytes)
  // │    ├─ scriptPubKey_len (CompactSize)
  // │    └─ scriptPubKey bytes
  // ├─ TxOut #1
  // │    ├─ ...
  // └─ TxOut #(vout_count - 1)
  read_vec_with_cumulative_limit(
    vout_count,
    max_satoshis,
    "outputs_total_value",
    fn(index) {
      in_context(
        AtOutput(index),
        read_tx_out_with_value(max_script_size_policy),
      )
    },
    InvalidValueRange(_, Some(0), Some(max_satoshis)),
  )
}

fn read_tx_out_with_value(max_script_size_policy: Int) -> Parser(#(TxOut, Int)) {
  // | value (8 bytes)
  // | scriptPubKey_len (CompactSize)
  // | scriptPubKey bytes
  fn(reader, ctx) {
    use reader, value <- run_parse(reader, ctx, read_satoshis())
    use reader, script_pubkey <- run_parse(
      reader,
      ctx,
      read_script("scriptPubKey", max_script_size_policy),
    )

    let output = TxOut(value:, script_pubkey:)
    let Satoshis(value_int) = value

    Ok(#(reader, #(output, value_int)))
  }
}

fn read_satoshis() -> Parser(Satoshis) {
  fn(reader, ctx) {
    use reader, value_bytes <- run_parse(
      reader,
      ctx,
      read_field("value", reader.read_bytes(_, 8)),
    )

    let assert Ok(value_i64) = int64.from_bytes_le(value_bytes)

    let value_err = make_field_error("value", reader, ctx)

    // This should never happen.
    // The max possible amount of satoshis 2_100_000_000_000_000 (2.1 quadrillion)
    // is less than JavaScript's Number.MAX_SAFE_INTEGER 
    use value_int <- result.try(
      value_i64
      |> int64.to_int
      |> result.map_error(fn(_) {
        value_i64
        |> int64.to_string
        |> IntegerOutOfRange
        |> value_err
      }),
    )

    case value_int < 0 || value_int > max_satoshis {
      True ->
        InvalidValueRange(value_int, Some(0), Some(max_satoshis))
        |> value_err
        |> Error

      False -> Ok(#(reader, Satoshis(value_int)))
    }
  }
}

fn read_script(
  field_name: String,
  max_script_size_policy: Int,
) -> Parser(ScriptBytes) {
  fn(reader, ctx) {
    use reader, script_len <- run_parse(
      reader,
      ctx,
      read_script_length(field_name <> "_len", max_script_size_policy),
    )
    use reader, script_bytes <- run_parse(
      reader,
      ctx,
      read_field(field_name, reader.read_bytes(_, script_len)),
    )
    Ok(#(reader, ScriptBytes(script_bytes)))
  }
}

/// Read and validate a script length field.
///
/// Reads a CompactSize length, converts it to Int, validates it against
/// max_script_size_policy, and ensures sufficient bytes remain.
fn read_script_length(
  field_name: String,
  max_script_size_policy: Int,
) -> Parser(Int) {
  fn(reader, ctx) {
    use reader, script_len_int <- run_parse(
      reader,
      ctx,
      read_compact_size_as_int(field_name),
    )

    let script_len_err = fn(parse_error_kind) {
      parse_error_kind
      |> make_field_error(field_name, reader, ctx)
      |> Error
    }

    let remaining = reader.bytes_remaining(reader)

    case script_len_int > remaining, script_len_int > max_script_size_policy {
      // Structural limit: length exceeds remaining bytes
      True, _ ->
        InsufficientBytes(claimed: script_len_int, remaining:)
        |> script_len_err

      // Policy limit: length exceeds configured maximum
      False, True ->
        PolicyLimitExceeded(script_len_int, max_script_size_policy)
        |> script_len_err

      // All validations passed
      False, False -> Ok(#(reader, script_len_int))
    }
  }
}

fn read_witness_stacks(
  vin_count: Int,
  policy: WitnessPolicy,
) -> Parser(List(WitnessStack)) {
  read_vec(vin_count, fn(index) {
    in_context(AtWitnessStack(index), read_witness_stack(policy))
  })
}

fn read_witness_stack(policy: WitnessPolicy) -> Parser(WitnessStack) {
  // WitnessStack for one input:
  // ├─ stack_len (CompactSize) - number of witness items
  // ├─ WitnessItem #0
  // │    ├─ item_len (CompactSize)
  // │    └─ item bytes
  // ├─ WitnessItem #1
  // │    ├─ ...
  // └─ WitnessItem #(stack_len - 1)
  fn(reader, ctx) {
    use reader, stack_len <- run_parse(
      reader,
      ctx,
      read_witness_stack_length(policy.max_items_per_input),
    )

    // Parse witness items while tracking cumulative byte size
    use reader, witness_items <- run_parse(
      reader,
      ctx,
      read_witness_items_with_byte_tracking(
        stack_len,
        policy.max_item_size,
        policy.max_stack_payload_bytes_per_input,
      ),
    )

    Ok(#(reader, WitnessStack(witness_items)))
  }
}

/// Read witness items while tracking cumulative payload bytes and failing fast
/// if the total exceeds max_stack_payload_bytes_per_input.
fn read_witness_items_with_byte_tracking(
  count: Int,
  max_item_size: Int,
  max_total_bytes: Int,
) -> Parser(List(WitnessItem)) {
  read_vec_with_cumulative_limit(
    count,
    max_total_bytes,
    "witnessStack_total_payload_bytes",
    fn(index) {
      in_context(
        AtWitnessItem(index),
        read_witness_item_with_size(max_item_size),
      )
    },
    PolicyLimitExceeded(_, max_total_bytes),
  )
}

/// Read a witness item and return it along with its byte size.
fn read_witness_item_with_size(
  max_item_size: Int,
) -> Parser(#(WitnessItem, Int)) {
  fn(reader, ctx) {
    use reader, item <- run_parse(reader, ctx, read_witness_item(max_item_size))

    let WitnessItem(bytes) = item
    let byte_size = bit_array.byte_size(bytes)

    Ok(#(reader, #(item, byte_size)))
  }
}

fn read_witness_item(max_item_size_policy: Int) -> Parser(WitnessItem) {
  fn(reader, ctx) {
    use reader, length <- run_parse(
      reader,
      ctx,
      read_witness_item_size(max_item_size_policy),
    )
    use reader, item_bytes <- run_parse(
      reader,
      ctx,
      read_field("witnessItem", reader.read_bytes(_, length)),
    )
    Ok(#(reader, WitnessItem(item_bytes)))
  }
}

/// Read and validate a witness stack length field.
///
/// Reads a CompactSize length, converts it to Int, and validates it against
/// max_items_per_input policy.
fn read_witness_stack_length(max_items_per_input_policy: Int) -> Parser(Int) {
  fn(reader, ctx) {
    use reader, stack_len <- run_parse(
      reader,
      ctx,
      read_compact_size_as_int("witnessStack_len"),
    )

    use <- bool.lazy_guard(stack_len > max_items_per_input_policy, fn() {
      PolicyLimitExceeded(stack_len, max_items_per_input_policy)
      |> make_field_error("witnessStack_len", reader, ctx)
      |> Error
    })

    Ok(#(reader, stack_len))
  }
}

fn read_witness_item_size(max_item_size_policy: Int) -> Parser(Int) {
  fn(reader, ctx) {
    use reader, length <- run_parse(
      reader,
      ctx,
      read_compact_size_as_int("witnessItem_len"),
    )

    let witness_item_len_err = fn(parse_error_kind) {
      parse_error_kind
      |> make_field_error("witnessItem_len", reader, ctx)
      |> Error
    }

    let remaining = reader.bytes_remaining(reader)

    case length > remaining, length > max_item_size_policy {
      // Structural limit: length exceeds remaining bytes
      True, _ ->
        InsufficientBytes(claimed: length, remaining:)
        |> witness_item_len_err

      // Policy limit: length exceeds configured maximum
      False, True ->
        PolicyLimitExceeded(length, max_item_size_policy)
        |> witness_item_len_err

      // All validations passed
      False, False -> Ok(#(reader, length))
    }
  }
}
