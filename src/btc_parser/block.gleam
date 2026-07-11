import btc_parser/internal/compact_size
import btc_parser/internal/decode
import btc_parser/internal/fixed_int/uint64.{type Uint64}
import btc_parser/internal/hash32.{type Hash32}
import btc_parser/internal/lifecycle
import btc_parser/internal/parser.{type Parser}
import btc_parser/internal/reader.{type Reader}
import btc_parser/transaction.{type Transaction}
import gleam/bit_array
import gleam/bool
import gleam/int
import gleam/list
import gleam/pair
import gleam/result

// ==============================================================================
// Block types
// ==============================================================================

/// Phantom type indicating a block that has been successfully
/// decoded from bytes but has not yet been validated against
/// Bitcoin consensus rules.
pub type Decoded =
  lifecycle.Decoded

/// A Bitcoin block.
///
/// A block is a container data structure that aggregates transactions
/// for inclusion in the blockchain.
pub opaque type Block(state) {
  Block(
    /// The 80-byte block header.
    header: Header,
    /// The transactions recorded in this block.
    transactions: List(Transaction(state)),
  )
}

/// A Bitcoin block header.
///
/// Its 80-byte wire encoding links to the previous block, records a hash
/// derived from the block’s transactions, and contains the proof-of-work fields.
pub opaque type Header {
  Header(
    /// The signed 32-bit block version.
    version: Int,
    /// The previous block header hash in wire-order little-endian bytes.
    previous_block_hash: Hash32,
    /// The transaction merkle root in wire-order little-endian bytes.
    merkle_root: Hash32,
    /// The unsigned 32-bit block timestamp, in seconds since the Unix epoch.
    timestamp: Int,
    /// The unsigned 32-bit compact encoding (`nBits`) of the proof-of-work target.
    target: Int,
    /// The unsigned 32-bit value varied when searching for valid proof of work.
    nonce: Int,
  )
}

/// Get the transactions from a block.
///
/// Returns transactions in the same order they appear in the block wire encoding.
pub fn get_transactions(block: Block(s)) -> List(Transaction(s)) {
  block.transactions
}

/// Get the header from a block.
///
/// Returns the 80-byte header that precedes the transaction count and transactions
/// in the block wire encoding.
pub fn get_header(block: Block(s)) -> Header {
  block.header
}

/// Get the signed 32-bit version from a block header.
///
/// The version is encoded as four little-endian bytes in the block wire format.
/// This function interprets those bytes as a signed integer, so `ff ff ff ff`
/// is returned as `-1`.
pub fn get_header_version(header: Header) -> Int {
  header.version
}

/// Get the previous block header hash in its 32-byte wire-order little-endian
/// representation.
pub fn get_header_previous_block_hash(header: Header) -> BitArray {
  hash32.to_bytes_le(header.previous_block_hash)
}

/// Get the transaction merkle root in its 32-byte wire-order little-endian
/// representation.
pub fn get_header_merkle_root(header: Header) -> BitArray {
  hash32.to_bytes_le(header.merkle_root)
}

/// Get the unsigned 32-bit timestamp from a block header.
///
/// The value is the number of seconds since the Unix epoch recorded in the
/// header. It is returned in the range `0` through `4_294_967_295`.
pub fn get_header_timestamp(header: Header) -> Int {
  header.timestamp
}

/// Get the unsigned 32-bit compact target encoding (`nBits`) from a block header.
///
/// Returns the raw compact encoding in the range `0` through `4_294_967_295`.
/// This function does not expand `nBits` into a full target or validate the
/// header's proof of work.
pub fn get_header_target(header: Header) -> Int {
  header.target
}

/// Get the unsigned 32-bit nonce from a block header.
///
/// The nonce is returned in the range `0` through `4_294_967_295`. This function
/// exposes the encoded value without validating the header's proof of work.
pub fn get_header_nonce(header: Header) -> Int {
  header.nonce
}

// ==============================================================================
// Error handling
// ==============================================================================

/// An error that occurred while decoding a Bitcoin block.
///
/// Distinguishes failures during hex-to-bytes conversion from failures during
/// block parsing.
pub type DecodeHexError {
  /// The hexadecimal string could not be converted to bytes.
  ///
  /// This occurs before any block parsing begins, typically due to an
  /// odd-length hex string or the presence of invalid hexadecimal characters.
  InvalidHex

  /// The byte sequence could not be parsed as a Bitcoin block.
  ///
  /// This wraps a `DecodeError` containing details about what went wrong during
  /// the block parsing phase.
  DecodeFailed(DecodeError)
}

/// An error that occurred while decoding a Bitcoin block from bytes.
///
/// Carries the byte offset where the error occurred, the kind of error, and
/// internal parser-location details used to build the public structural path.
pub opaque type DecodeError {
  DecodeError(offset: Int, kind: DecodeErrorKind, context: List(ParseContext))
}

/// The specific kind of error that occurred during block decoding.
///
/// Categorizes decode failures into distinct variants.
pub type DecodeErrorKind {
  /// The input ended before enough bytes could be read.
  UnexpectedEof(
    /// The number of bytes the decoder required.
    bytes_needed: Int,
    /// The number of bytes available at that point.
    remaining: Int,
  )

  /// A CompactSize-encoded integer used a non-minimal encoding.
  ///
  /// Bitcoin's serialization rules require CompactSize integers to use the
  /// shortest possible encoding. This error occurs when a value could have
  /// been encoded in fewer bytes than were used.
  NonMinimalCompactSize(
    /// The size of the encoded CompactSize in bytes.
    encoded_size: Int,
    /// The decoded integer value.
    value: Int,
  )

  /// A length or count requires more bytes than remain in the input.
  ///
  /// Unlike `UnexpectedEof`, which reports a failed read, this error reports a
  /// decoded length or count that is known in advance not to fit in the remaining
  /// input. This is distinct from `PolicyLimitExceeded`, which enforces configured
  /// resource limits.
  ///
  /// Examples:
  ///
  /// - A transaction count claims one transaction, whose smallest encoding is
  ///   10 bytes, but only 9 bytes remain.
  InsufficientBytes(
    /// The number of bytes required.
    ///
    /// This may be a conservative estimate, such as `remaining + 1`, rather
    /// than the exact requirement to avoid integer overflow on JavaScript.
    claimed: Int,
    /// The number of bytes available.
    remaining: Int,
  )

  /// A decoded 64-bit integer value exceeds the range representable by the runtime.
  ///
  /// The original value is preserved as a string for diagnostics.
  IntegerOutOfRange(String)

  /// A transaction contained in the block could not be decoded.
  ///
  /// The wrapped transaction decode error preserves the transaction-level
  /// failure details. The block decode error's own offset and context identify
  /// where that transaction appears within the block.
  TransactionDecodeFailed(transaction.DecodeError)

  /// A policy limit was exceeded.
  PolicyLimitExceeded(
    /// The `DecodePolicy` limit that was violated.
    limit: DecodePolicyLimit,
    /// The measured or decoded quantity that exceeded `max`.
    value: Int,
    /// The configured maximum.
    max: Int,
  )

  /// The block was successfully decoded, but extra bytes remain in the input.
  ///
  /// This indicates the input buffer contains more data than a single valid block.
  /// The wrapped `Int` is the count of trailing bytes that were not consumed.
  TrailingBytes(Int)
}

/// Identifies the configured `DecodePolicy` limit that was exceeded.
///
/// Carried by `PolicyLimitExceeded`. Use `get_decode_error_path` to identify
/// where the violation occurred.
pub type DecodePolicyLimit {
  /// The maximum input buffer size was exceeded.
  ///
  /// In `PolicyLimitExceeded`, `value` is the total byte size of the supplied
  /// buffer. This limit is checked before decoding begins.
  MaxBlockSize
  /// The maximum number of transactions was exceeded.
  MaxTransactionCount
}

/// Internal breadcrumbs used to build public decode error paths.
///
/// Contexts are accumulated from outermost to innermost and projected by
/// `get_decode_error_path`.
type ParseContext {
  InBlock
  InHeader
  AtTransaction(Int)
  AtField(ParseField)
}

/// Internal block wire-format fields used in decode error paths.
type ParseField {
  TransactionCount
  Version
  PreviousBlockHash
  MerkleRoot
  Timestamp
  Target
  Nonce
}

/// Get the byte offset where a block decoding error occurred.
pub fn get_decode_error_offset(err: DecodeError) -> Int {
  err.offset
}

/// Get the specific kind of block decoding error that occurred.
pub fn get_decode_error_kind(err: DecodeError) -> DecodeErrorKind {
  err.kind
}

/// Get the structural path where a block decoding error occurred.
///
/// Paths are rooted at `block`, and transaction indices are zero-based. For
/// example, a truncated nonce is reported at `block.header.nonce`, while an
/// error starting the third transaction is reported at `block.transactions[2]`.
/// When the kind is `TransactionDecodeFailed`, inspect the wrapped transaction
/// error for its path within that transaction.
pub fn get_decode_error_path(err: DecodeError) -> String {
  list.fold(err.context, "", fn(path, ctx) {
    case ctx {
      InBlock -> "block"
      InHeader -> path <> ".header"
      AtTransaction(index) ->
        path <> ".transactions[" <> int.to_string(index) <> "]"
      AtField(field) -> path <> field_path_suffix(field)
    }
  })
}

fn field_path_suffix(field: ParseField) -> String {
  case field {
    TransactionCount -> ".transactions.count"
    Version -> ".version"
    PreviousBlockHash -> ".previous_block_hash"
    MerkleRoot -> ".merkle_root"
    Timestamp -> ".timestamp"
    Target -> ".target"
    Nonce -> ".nonce"
  }
}

fn new_decode_error(kind: DecodeErrorKind, offset: Int) -> DecodeError {
  DecodeError(offset:, kind:, context: [])
}

fn with_context(err: DecodeError, context: List(ParseContext)) -> DecodeError {
  list.fold(context, err, fn(err, ctx) {
    DecodeError(..err, context: [ctx, ..err.context])
  })
}

fn field_error(
  field: ParseField,
  offset: Int,
  context: List(ParseContext),
) -> fn(DecodeErrorKind) -> DecodeError {
  fn(kind) {
    kind
    |> new_decode_error(offset)
    |> with_context([AtField(field), ..context])
  }
}

// ==============================================================================
// Decoding
// ==============================================================================

/// Configuration policy for block decoding limits.
///
/// This type controls resource constraints during block decoding to protect
/// against malicious inputs that could cause excessive memory allocation or
/// processing time.
///
/// Limits are enforced during decoding. If a limit is exceeded,
/// decoding fails with `PolicyLimitExceeded`.
///
/// ## Contained Transactions
///
/// Contained transactions are decoded with `transaction.default_decode_policy`.
/// Its top-level `max_tx_size` limit is not applied because `max_block_size`
/// owns the enclosing byte budget. The other default transaction limits still
/// apply, and this policy cannot configure or override them.
///
/// Builder functions do not validate whether custom limits are useful for
/// decoding consensus-valid blocks. Callers that override `default_decode_policy`
/// are responsible for choosing sensible values for their use case. Overly
/// strict or unusual values may simply cause decoding to fail with existing
/// decode errors.
///
/// ## See Also
///
/// - `default_decode_policy` for the standard decoding limits
/// - `decode_with_policy` to apply a custom policy
pub opaque type DecodePolicy {
  DecodePolicy(
    /// Maximum byte size accepted by the decoder, checked before decoding.
    max_block_size: Int,
    /// Maximum decoded transaction count.
    max_tx_count: Int,
  )
}

/// The default block decoding policy.
///
/// Provides reasonable resource limits for block decoding, applied
/// automatically when using `decode` or `decode_hex`. These defaults protect
/// against malicious inputs while preventing excessive memory allocation and
/// processing time. As these are policy limits rather than consensus rules,
/// some valid Bitcoin blocks may be rejected by this configuration.
///
/// The overall block size limit (`max_block_size`) serves as the primary
/// resource constraint.
///
/// ## Default Values
///
/// - `max_block_size`: 4,000,000 bytes - Primary resource constraint, enforced before
///   decoding begins.
/// - `max_tx_count`: 20,000 transactions - Substantially higher than typical blocks
///   but prevents unbounded memory allocation for transaction lists.
pub fn default_decode_policy() -> DecodePolicy {
  DecodePolicy(max_block_size: 4_000_000, max_tx_count: 20_000)
}

/// Return a policy with a custom maximum serialized block size.
pub fn decode_policy_with_max_block_size(
  policy: DecodePolicy,
  max_block_size: Int,
) -> DecodePolicy {
  DecodePolicy(..policy, max_block_size:)
}

/// Return a policy with a custom maximum transaction count.
pub fn decode_policy_with_max_tx_count(
  policy: DecodePolicy,
  max_tx_count: Int,
) -> DecodePolicy {
  DecodePolicy(..policy, max_tx_count:)
}

/// Get the maximum serialized block size.
pub fn decode_policy_max_block_size(policy: DecodePolicy) -> Int {
  policy.max_block_size
}

/// Get the maximum decoded transaction count.
pub fn decode_policy_max_tx_count(policy: DecodePolicy) -> Int {
  policy.max_tx_count
}

/// Decode a Bitcoin block from its binary representation.
///
/// This is the standard entry point for decoding Bitcoin block data
/// serialized in the Bitcoin network protocol format.
///
/// This function applies `default_decode_policy` to protect against malicious inputs
/// by enforcing reasonable limits.
///
/// For custom resource limits, use `decode_with_policy` instead.
///
/// The returned block is marked as `Decoded`, meaning it has been
/// successfully decoded from bytes but has not yet been checked against
/// Bitcoin consensus rules.
///
/// ## Returns
///
/// - `Ok(Block(Decoded))`: Successfully decoded within the default policy limits.
/// - `Error(DecodeError)`: The bytes were not a well-formed block encoding
///   within the default policy limits.
pub fn decode(bytes: BitArray) -> Result(Block(Decoded), DecodeError) {
  decode_with_policy(bytes, default_decode_policy())
}

/// Decode a Bitcoin block with custom resource limits.
///
/// Like `decode`, but accepts a `DecodePolicy` to override the resource limits
/// applied during decoding. Use `default_decode_policy` and the `decode_policy_with_*`
/// builder functions to construct custom policies. Limits that are exceeded
/// produce a `PolicyLimitExceeded` error. See `DecodePolicy` and
/// `default_decode_policy` for available options and defaults.
///
/// This policy controls block-level limits only. Contained transactions use
/// `transaction.default_decode_policy`: its `max_tx_size` does not apply, while
/// its other limits remain in effect and cannot be customized here.
///
/// ## Returns
///
/// - `Ok(Block(Decoded))`: Successfully decoded within the supplied policy limits.
/// - `Error(DecodeError)`: The bytes were not a well-formed block
///   encoding within the supplied policy limits.
pub fn decode_with_policy(
  bytes: BitArray,
  policy: DecodePolicy,
) -> Result(Block(Decoded), DecodeError) {
  let block_size = bit_array.byte_size(bytes)
  use <- bool.guard(
    block_size > policy.max_block_size,
    PolicyLimitExceeded(MaxBlockSize, block_size, policy.max_block_size)
      |> new_decode_error(0)
      |> with_context([InBlock])
      |> Error,
  )

  bytes
  |> reader.new
  |> parser.run(block_parser(policy), _, [InBlock])
  |> result.map(pair.second)
}

/// Decode a Bitcoin block from its hexadecimal string representation.
///
/// This is a convenience function that combines hex-to-bytes conversion with
/// block decoding. It's useful when working with block data in hexadecimal
/// format, such as from block explorers, RPC responses, or test vectors.
///
/// This function applies `default_decode_policy` for resource limits.
/// For custom resource limits, use `decode_hex_with_policy` instead.
///
/// ## Returns
///
/// - `Ok(Block(Decoded))`: Successfully decoded within the default policy limits.
/// - `Error(InvalidHex)`: The hex string was invalid (odd length or
///   invalid characters).
/// - `Error(DecodeFailed(error))`: The decoded bytes were not a well-formed
///   block encoding within the default policy limits.
pub fn decode_hex(hex: String) -> Result(Block(Decoded), DecodeHexError) {
  decode_hex_with_policy(hex, default_decode_policy())
}

/// Decode a Bitcoin block from hexadecimal with custom resource limits.
///
/// This function combines hex-to-bytes conversion with policy-based block
/// decoding, providing both the convenience of hexadecimal input and fine-grained
/// control over resource limits. Use this when working with hex-encoded block
/// data that requires custom resource constraints.
///
/// As with `decode_with_policy`, this policy controls block-level limits only.
/// Contained transactions use the default transaction policy without its
/// top-level `max_tx_size` limit.
///
/// ## Returns
///
/// - `Ok(Block(Decoded))`: Successfully decoded within the supplied policy limits.
/// - `Error(InvalidHex)`: The hex string was invalid (odd length or
///   invalid characters).
/// - `Error(DecodeFailed(error))`: The decoded bytes were not a well-formed
///   block encoding within the supplied policy limits.
pub fn decode_hex_with_policy(
  hex: String,
  policy: DecodePolicy,
) -> Result(Block(Decoded), DecodeHexError) {
  use bytes <- result.try(
    hex
    |> bit_array.base16_decode
    |> result.replace_error(InvalidHex),
  )

  bytes
  |> decode_with_policy(policy)
  |> result.map_error(DecodeFailed)
}

// ==============================================================================
// Block Parser
// ==============================================================================

fn block_parser(
  policy: DecodePolicy,
) -> Parser(ParseContext, Block(Decoded), DecodeError) {
  use block <- parser.then(block_body_parser(policy))
  use Nil <- parser.then(end_of_block_parser())
  parser.return(block)
}

fn block_body_parser(
  policy: DecodePolicy,
) -> Parser(ParseContext, Block(Decoded), DecodeError) {
  use header <- parser.then(parser.with_context(header_parser(), InHeader))
  use transactions <- parser.then(transactions_parser(policy.max_tx_count))
  parser.return(Block(header:, transactions:))
}

fn end_of_block_parser() -> Parser(ParseContext, Nil, DecodeError) {
  parser.end_of_input(fn(bytes_remaining, reader, ctx) {
    bytes_remaining
    |> TrailingBytes
    |> new_decode_error(reader.get_offset(reader))
    |> with_context(ctx)
  })
}

fn header_parser() -> Parser(ParseContext, Header, DecodeError) {
  use version <- parser.then(field_parser(Version, reader.read_i32_le))
  use previous_block_hash <- parser.then(hash32_parser(PreviousBlockHash))
  use merkle_root <- parser.then(hash32_parser(MerkleRoot))
  use timestamp <- parser.then(field_parser(Timestamp, reader.read_u32_le))
  use target <- parser.then(field_parser(Target, reader.read_u32_le))
  use nonce <- parser.then(field_parser(Nonce, reader.read_u32_le))

  parser.return(Header(
    version:,
    previous_block_hash:,
    merkle_root:,
    timestamp:,
    target:,
    nonce:,
  ))
}

fn transactions_parser(
  max_tx_count_policy: Int,
) -> Parser(ParseContext, List(Transaction(Decoded)), DecodeError) {
  max_tx_count_policy
  |> transaction_count_parser
  |> parser.then(parser.indexed_repeat(_, transaction_parser(), AtTransaction))
}

fn transaction_count_parser(
  max_tx_count_policy: Int,
) -> Parser(ParseContext, Int, DecodeError) {
  TransactionCount
  |> compact_size_int_parser
  |> parser.try_with_start_offset(fn(tx_count, start_offset, reader, ctx) {
    tx_count
    |> validate_transaction_count(reader, max_tx_count_policy, fn(kind) {
      kind
      |> field_error(TransactionCount, start_offset, ctx)
      |> Error
    })
  })
}

fn transaction_parser() -> Parser(
  ParseContext,
  Transaction(Decoded),
  DecodeError,
) {
  parser.new(fn(reader, ctx) {
    let tx_start_offset = reader.get_offset(reader)

    use #(tx, bytes_read) <- result.try(
      reader
      |> reader.get_remaining
      |> transaction.decode_prefix_with_policy(
        transaction.default_decode_policy(),
      )
      |> result.map_error(fn(err) {
        err
        |> TransactionDecodeFailed
        |> new_decode_error(
          tx_start_offset + transaction.get_decode_error_offset(err),
        )
        |> with_context(ctx)
      }),
    )

    use reader <- result.try(
      reader
      |> reader.skip_bytes(bytes_read)
      |> result.map_error(fn(err) {
        err
        |> decode.map_reader_error(UnexpectedEof)
        |> new_decode_error(tx_start_offset)
        |> with_context(ctx)
      }),
    )

    Ok(#(reader, tx))
  })
}

fn validate_transaction_count(
  tx_count: Int,
  reader: Reader,
  max_tx_count_policy: Int,
  on_invalid: fn(DecodeErrorKind) -> Result(Int, DecodeError),
) -> Result(Int, DecodeError) {
  let min_transaction_size = 10
  let remaining = reader.bytes_remaining(reader)
  // A legacy transaction with zero inputs and outputs is ten bytes.
  let max_transactions_by_bytes = remaining / min_transaction_size

  case tx_count > max_transactions_by_bytes, tx_count > max_tx_count_policy {
    // Structural limit: count exceeds what remaining bytes can accommodate.
    True, _ ->
      InsufficientBytes(claimed: remaining + 1, remaining:)
      |> on_invalid

    // Policy limit: count exceeds the configured maximum.
    _, True ->
      PolicyLimitExceeded(MaxTransactionCount, tx_count, max_tx_count_policy)
      |> on_invalid

    _, _ -> Ok(tx_count)
  }
}

// ==============================================================================
// Shared Parser Helpers
// ==============================================================================

/// Construct a parser for a field, adding error mapping and context wrapping.
fn field_parser(
  field: ParseField,
  read_fn: fn(Reader) -> Result(#(Reader, a), reader.ReaderError),
) -> Parser(ParseContext, a, DecodeError) {
  parser.from_reader(read_fn, fn(err, start_offset, ctx) {
    err
    |> decode.map_reader_error(UnexpectedEof)
    |> field_error(field, start_offset, ctx)
  })
}

/// Construct a CompactSize parser with error mapping and context wrapping.
fn compact_size_parser(
  field: ParseField,
) -> Parser(ParseContext, Uint64, DecodeError) {
  parser.from_reader(compact_size.read, fn(err, start_offset, ctx) {
    err
    |> decode.map_compact_size_error(UnexpectedEof, NonMinimalCompactSize)
    |> field_error(field, start_offset, ctx)
  })
}

/// Construct a parser for a CompactSize value converted to `Int`.
fn compact_size_int_parser(
  field: ParseField,
) -> Parser(ParseContext, Int, DecodeError) {
  field
  |> compact_size_parser
  |> parser.try_with_start_offset(fn(value_u64, start_offset, _reader, ctx) {
    value_u64
    |> decode.uint64_to_int(IntegerOutOfRange)
    |> result.map_error(field_error(field, start_offset, ctx))
  })
}

fn hash32_parser(
  field: ParseField,
) -> Parser(ParseContext, Hash32, DecodeError) {
  field
  |> field_parser(reader.read_bytes(_, 32))
  |> parser.map(fn(bytes) {
    let assert Ok(hash32) = hash32.from_bytes_le(bytes)
    hash32
  })
}
