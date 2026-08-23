//// Deserialize, inspect, validate, and serialize Bitcoin blocks.

import btc_parser/internal/compact_size
import btc_parser/internal/decode
import btc_parser/internal/double_sha256
import btc_parser/internal/fixed_int/uint64.{type Uint64}
import btc_parser/internal/hash256.{type Hash256}
import btc_parser/internal/lifecycle
import btc_parser/internal/parser.{type Parser}
import btc_parser/internal/pow_target.{type PowTarget}
import btc_parser/internal/reader.{type Reader}
import btc_parser/transaction.{type Transaction}
import gleam/bit_array
import gleam/bool
import gleam/int
import gleam/list
import gleam/order.{Eq, Gt, Lt}
import gleam/pair
import gleam/result

// ==============================================================================
// Block types
// ==============================================================================

/// Phantom type indicating a block that has been successfully parsed from its
/// canonical Bitcoin wire-format serialization but has not yet been validated
/// against Bitcoin consensus rules.
pub type Parsed =
  lifecycle.Parsed

/// Phantom type indicating a block that has passed the context-free
/// Bitcoin consensus checks performed by `validate_context_free_consensus`.
///
/// This does not indicate full block validity.
pub type ContextFreeValidated =
  lifecycle.ContextFreeValidated

/// A Bitcoin block.
///
/// A block is a container data structure that aggregates transactions
/// for inclusion in the blockchain.
pub opaque type Block(state) {
  Block(
    /// The 80-byte block header.
    header: Header,
    /// The number of transactions recorded in the block.
    transaction_count: Int,
    /// The transactions in wire order.
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
    previous_block_hash: Hash256,
    /// The transaction merkle root in wire-order little-endian bytes.
    merkle_root: Hash256,
    /// The unsigned 32-bit block timestamp, in seconds since the Unix epoch.
    timestamp: Int,
    /// The unsigned 32-bit compact encoding (`nBits`) of the proof-of-work target.
    target: Int,
    /// The unsigned 32-bit value varied when searching for valid proof of work.
    nonce: Int,
  )
}

/// Get the number of transactions in a block.
///
/// Returns the decoded `CompactSize` transaction count from the block wire encoding.
pub fn get_transaction_count(block: Block(state)) -> Int {
  block.transaction_count
}

/// Get the transactions from a block.
///
/// Returns transactions in the same order they appear in the block wire encoding.
pub fn get_transactions(block: Block(state)) -> List(Transaction(state)) {
  block.transactions
}

/// Get the header from a block.
///
/// Returns the 80-byte header that precedes the transaction count and transactions
/// in the block wire encoding.
pub fn get_header(block: Block(state)) -> Header {
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
  hash256.to_bytes_le(header.previous_block_hash)
}

/// Get the transaction merkle root in its 32-byte wire-order little-endian
/// representation.
pub fn get_header_merkle_root(header: Header) -> BitArray {
  hash256.to_bytes_le(header.merkle_root)
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

/// Compute the block's BIP 141 base size in bytes.
///
/// This is the size of the complete stripped block serialization: the 80-byte
/// header, the canonical CompactSize transaction count, and every transaction
/// serialized without its SegWit marker, flag, or witness data.
pub fn compute_base_size(block: Block(state)) -> Int {
  compute_block_size(block, transaction.compute_base_size)
}

/// Compute the block's BIP 141 total size in bytes.
///
/// This is the byte size of the complete canonical wire serialization produced
/// by `serialize`, including SegWit marker, flag, and witness data.
pub fn compute_total_size(block: Block(state)) -> Int {
  compute_block_size(block, transaction.compute_total_size)
}

fn compute_block_size(
  block: Block(state),
  compute_tx_size: fn(Transaction(state)) -> Int,
) -> Int {
  let header_size = 80
  let txs_size = compute_txs_size_loop(block.transactions, compute_tx_size, 0)
  header_size + compact_size.encoded_size(block.transaction_count) + txs_size
}

fn compute_txs_size_loop(
  txs: List(Transaction(state)),
  compute_tx_size: fn(Transaction(state)) -> Int,
  acc: Int,
) -> Int {
  case txs {
    [] -> acc
    [tx, ..rest] ->
      compute_txs_size_loop(rest, compute_tx_size, acc + compute_tx_size(tx))
  }
}

const witness_scale_factor = 4

/// Compute the block's BIP 141 weight in weight units.
///
/// Weight is calculated as `base_size * 3 + total_size`. Equivalently, each
/// byte in the stripped serialization contributes four weight units and each
/// byte present only in the complete serialization contributes one.
///
/// This function only measures the block; it does not enforce the consensus
/// maximum.
pub fn compute_weight(block: Block(state)) -> Int {
  let non_tx_size = 80 + compact_size.encoded_size(block.transaction_count)
  let txs_weight = compute_txs_weight_loop(block.transactions, 0)
  non_tx_size * witness_scale_factor + txs_weight
}

fn compute_txs_weight_loop(txs: List(Transaction(state)), acc: Int) -> Int {
  case txs {
    [] -> acc
    [tx, ..rest] ->
      compute_txs_weight_loop(rest, acc + transaction.compute_weight(tx))
  }
}

/// Compute a block's transaction Merkle root and mutation flag.
///
/// Leaves are transaction IDs—not witness transaction IDs—in block order.
/// Parent hashes are produced by double-SHA-256 hashing each adjacent pair,
/// duplicating the final hash when a level contains an odd number of hashes.
///
/// The returned root is a 32-byte `BitArray` in wire-order little-endian
/// representation. An empty transaction list produces a zero-valued 32-byte
/// root. The `Bool` is `True` when an actual pair at any level contains
/// identical hashes before odd-node padding.
///
/// This function does not compare the computed root with the block header or
/// otherwise validate the block.
pub fn compute_merkle_root(block: Block(state)) -> #(BitArray, Bool) {
  let txids = list.map(block.transactions, transaction.compute_txid)
  let assert #([h], mutated) = compute_merkle_root_loop(txids, False)
  #(h, mutated)
}

fn compute_merkle_root_loop(
  hashes: List(BitArray),
  mutated: Bool,
) -> #(List(BitArray), Bool) {
  case hashes {
    [] -> #([<<0:256>>], False)

    [h] -> #([h], mutated)

    _ -> {
      let #(hashes, level_mutated) =
        compute_merkle_parents_loop(hashes, [], False)

      compute_merkle_root_loop(hashes, mutated || level_mutated)
    }
  }
}

fn compute_merkle_parents_loop(
  hashes: List(BitArray),
  parents: List(BitArray),
  mutated: Bool,
) -> #(List(BitArray), Bool) {
  case hashes {
    [] -> #(list.reverse(parents), mutated)

    [h] -> {
      let parent = double_sha256.hash(bit_array.append(h, h))
      #(list.reverse([parent, ..parents]), mutated)
    }

    [h1, h2, ..rest] -> {
      let parent = double_sha256.hash(bit_array.append(h1, h2))
      compute_merkle_parents_loop(
        rest,
        [parent, ..parents],
        mutated || h1 == h2,
      )
    }
  }
}

// ==============================================================================
// Error handling
// ==============================================================================

/// An error that occurred while deserializing a Bitcoin block from hex.
///
/// Distinguishes failures during hex-to-bytes conversion from underlying block
/// decoding failures.
pub type DeserializeHexError {
  /// The hexadecimal string could not be converted to bytes.
  ///
  /// This occurs before any block decoding begins, typically due to an
  /// odd-length hex string or the presence of invalid hexadecimal characters.
  InvalidHex

  /// The byte sequence could not be decoded as a Bitcoin block.
  ///
  /// This wraps a `DecodeError` containing details about what went wrong during
  /// the block decoding phase.
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

  /// One block was successfully decoded, but extra bytes remain, so
  /// deserialization failed.
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
// Deserialization
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
/// - `deserialize_with_policy` to apply a custom policy
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
/// automatically when using `deserialize` or `deserialize_hex`. These defaults
/// protect against malicious inputs while preventing excessive memory allocation
/// and processing time. As these are policy limits rather than consensus rules,
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

/// Deserialize a Bitcoin block from its canonical Bitcoin wire-format
/// serialization.
///
/// This is the standard entry point for converting a complete serialized
/// Bitcoin block into a typed value. The entire input must contain exactly one
/// block; trailing bytes are rejected.
///
/// This function applies `default_decode_policy` to protect against malicious inputs
/// by enforcing reasonable limits.
///
/// For custom resource limits, use `deserialize_with_policy` instead.
///
/// The returned block is marked as `Parsed`, meaning its structure was
/// successfully parsed but it has not yet been checked against Bitcoin
/// consensus rules.
///
/// ## Returns
///
/// - `Ok(Block(Parsed))`: Successfully deserialized within the default policy limits.
/// - `Error(DecodeError)`: The bytes were not a well-formed block encoding
///   within the default policy limits.
pub fn deserialize(bytes: BitArray) -> Result(Block(Parsed), DecodeError) {
  deserialize_with_policy(bytes, default_decode_policy())
}

/// Deserialize a Bitcoin block with custom resource limits.
///
/// Like `deserialize`, but accepts a `DecodePolicy` to override the resource
/// limits applied during decoding. Use `default_decode_policy` and the
/// `decode_policy_with_*` builder functions to construct custom policies.
/// Limits that are exceeded produce a `PolicyLimitExceeded` error. See
/// `DecodePolicy` and `default_decode_policy` for available options and defaults.
///
/// This policy controls block-level limits only. Contained transactions use
/// `transaction.default_decode_policy`: its `max_tx_size` does not apply, while
/// its other limits remain in effect and cannot be customized here.
///
/// ## Returns
///
/// - `Ok(Block(Parsed))`: Successfully deserialized within the supplied policy limits.
/// - `Error(DecodeError)`: The bytes were not a well-formed block
///   encoding within the supplied policy limits.
pub fn deserialize_with_policy(
  bytes: BitArray,
  policy: DecodePolicy,
) -> Result(Block(Parsed), DecodeError) {
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

/// Deserialize a Bitcoin block from its hexadecimal string representation.
///
/// This is a convenience function that combines hex-to-bytes conversion with
/// block deserialization. It's useful when working with block data in hexadecimal
/// format, such as from block explorers, RPC responses, or test vectors.
///
/// This function applies `default_decode_policy` for resource limits.
/// For custom resource limits, use `deserialize_hex_with_policy` instead.
///
/// ## Returns
///
/// - `Ok(Block(Parsed))`: Successfully deserialized within the default policy limits.
/// - `Error(InvalidHex)`: The hex string was invalid (odd length or
///   invalid characters).
/// - `Error(DecodeFailed(error))`: The decoded bytes were not a well-formed
///   block encoding within the default policy limits.
pub fn deserialize_hex(
  hex: String,
) -> Result(Block(Parsed), DeserializeHexError) {
  deserialize_hex_with_policy(hex, default_decode_policy())
}

/// Deserialize a Bitcoin block from hexadecimal with custom resource limits.
///
/// This function combines hex-to-bytes conversion with policy-based block
/// deserialization, providing both the convenience of hexadecimal input and
/// fine-grained control over resource limits. Use this when working with
/// hex-encoded block data that requires custom resource constraints.
///
/// As with `deserialize_with_policy`, this policy controls block-level limits only.
/// Contained transactions use the default transaction policy without its
/// top-level `max_tx_size` limit.
///
/// ## Returns
///
/// - `Ok(Block(Parsed))`: Successfully deserialized within the supplied policy limits.
/// - `Error(InvalidHex)`: The hex string was invalid (odd length or
///   invalid characters).
/// - `Error(DecodeFailed(error))`: The decoded bytes were not a well-formed
///   block encoding within the supplied policy limits.
pub fn deserialize_hex_with_policy(
  hex: String,
  policy: DecodePolicy,
) -> Result(Block(Parsed), DeserializeHexError) {
  use bytes <- result.try(
    hex
    |> bit_array.base16_decode
    |> result.replace_error(InvalidHex),
  )

  bytes
  |> deserialize_with_policy(policy)
  |> result.map_error(DecodeFailed)
}

// ==============================================================================
// Block Parser
// ==============================================================================

fn block_parser(
  policy: DecodePolicy,
) -> Parser(ParseContext, Block(Parsed), DecodeError) {
  use block <- parser.then(block_body_parser(policy))
  use Nil <- parser.then(end_of_block_parser())
  parser.return(block)
}

fn block_body_parser(
  policy: DecodePolicy,
) -> Parser(ParseContext, Block(Parsed), DecodeError) {
  use header <- parser.then(parser.with_context(header_parser(), InHeader))
  use transaction_count <- parser.then(transaction_count_parser(
    policy.max_tx_count,
  ))
  use transactions <- parser.then(transactions_parser(transaction_count))
  parser.return(Block(header:, transaction_count:, transactions:))
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
  use previous_block_hash <- parser.then(hash256_parser(PreviousBlockHash))
  use merkle_root <- parser.then(hash256_parser(MerkleRoot))
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
  tx_count: Int,
) -> Parser(ParseContext, List(Transaction(Parsed)), DecodeError) {
  parser.indexed_repeat(tx_count, transaction_parser(), AtTransaction)
}

fn transaction_count_parser(
  max_tx_count_policy: Int,
) -> Parser(ParseContext, Int, DecodeError) {
  TransactionCount
  |> compact_size_int_parser
  |> parser.try_with_start_offset(fn(tx_count, start_offset, reader, ctx) {
    tx_count
    |> validate_parsed_transaction_count(reader, max_tx_count_policy, fn(kind) {
      kind
      |> field_error(TransactionCount, start_offset, ctx)
      |> Error
    })
  })
}

fn transaction_parser() -> Parser(
  ParseContext,
  Transaction(Parsed),
  DecodeError,
) {
  fn(reader, ctx) {
    let tx_policy = transaction.default_decode_policy()
    let tx_start_offset = reader.get_offset(reader)

    // Decode one transaction without consuming the remainder of the block.
    // The prefix decoder returns both the decoded transaction and
    // the number of bytes it consumed.
    use #(tx, bytes_read) <- result.try(
      reader
      |> reader.get_remaining
      |> transaction.decode_prefix_with_policy(tx_policy)
      |> result.map_error(fn(err) {
        err
        |> TransactionDecodeFailed
        |> new_decode_error(
          // Transaction errors are relative to the transaction start.
          // Block errors must point at the corresponding offset in the whole block.
          tx_start_offset + transaction.get_decode_error_offset(err),
        )
        |> with_context(ctx)
      }),
    )

    // Advance the shared block reader so the next indexed transaction begins
    // exactly after this transaction's encoding.
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
  }
}

fn validate_parsed_transaction_count(
  tx_count: Int,
  reader: Reader,
  max_tx_count_policy: Int,
  on_invalid: fn(DecodeErrorKind) -> Result(Int, DecodeError),
) -> Result(Int, DecodeError) {
  let min_tx_size = 10
  let remaining = reader.bytes_remaining(reader)
  // Even the smallest legacy transaction occupies ten bytes.
  let max_txs_by_bytes = remaining / min_tx_size

  use <- bool.guard(
    tx_count > max_txs_by_bytes,
    on_invalid(InsufficientBytes(claimed: remaining + 1, remaining:)),
  )

  use <- bool.guard(
    tx_count > max_tx_count_policy,
    on_invalid(PolicyLimitExceeded(
      MaxTransactionCount,
      tx_count,
      max_tx_count_policy,
    )),
  )

  Ok(tx_count)
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

/// Construct a parser for a 32-byte hash field, preserving Bitcoin wire order.
fn hash256_parser(
  field: ParseField,
) -> Parser(ParseContext, Hash256, DecodeError) {
  field
  |> field_parser(reader.read_bytes(_, 32))
  |> parser.map(fn(bytes) {
    let assert Ok(hash256) = hash256.from_bytes_le(bytes)
    hash256
  })
}

// ==============================================================================
// Context-Free Consensus Validation
// ==============================================================================

/// A violation of Bitcoin consensus rules detected during block validation.
///
/// Each variant identifies a specific context-free rule that the block breaks.
pub type ConsensusViolation {
  /// The block contains no transactions.
  NoTransactions

  /// The transaction count exceeded the coarse consensus upper bound.
  ImpossiblyLargeTransactionCount

  /// Proof-of-work validation failed under the supplied proof-of-work limit.
  ///
  /// This is reported when the header's compact target encoding represents a
  /// negative or zero target, expands beyond 256 bits, or expands to a target
  /// exceeding the supplied `PowLimit`; or when the header hash exceeds the
  /// expanded target. Constructing the `PowLimit` separately ensures this
  /// variant always identifies a failure attributable to the block.
  InvalidProofOfWork

  /// The stripped block serialization exceeded the consensus size limit.
  ///
  /// The contained value is the measured base size in bytes. The consensus
  /// maximum is 1,000,000 bytes.
  BaseSizeLimitExceeded(size: Int)

  /// The block exceeded the consensus weight limit.
  ///
  /// The contained value is the measured block weight in weight units. The
  /// consensus maximum is 4,000,000 weight units.
  WeightLimitExceeded(weight: Int)

  /// The Merkle root recorded in the block header did not match the root
  /// computed from the block's transaction IDs.
  ///
  /// `actual` is the root recorded in the header and `expected` is the computed
  /// root. Both are 32-byte values in wire-order little-endian representation.
  MerkleRootMismatch(actual: BitArray, expected: BitArray)

  /// The transaction Merkle tree contained identical hashes in an actual pair
  /// at some level before odd-node padding.
  ///
  /// Duplicating the final unpaired hash during normal Merkle-tree construction
  /// does not itself count as mutation.
  MutatedMerkleTree

  /// The transaction at index zero does not have coinbase shape.
  ///
  /// Empty blocks are reported separately as `NoTransactions` before coinbase
  /// placement is checked.
  MissingCoinbase

  /// A transaction after index zero has coinbase shape.
  ///
  /// `index` is the zero-based position of the first unexpected coinbase
  /// transaction.
  UnexpectedCoinbase(index: Int)

  /// The block's legacy signature-operation count exceeded 20,000.
  ///
  /// `sigop_count` is the unscaled, structural total across all transaction
  /// scriptSigs and scriptPubKeys. It excludes witness data; the validator
  /// multiplies it by the witness scale factor when enforcing the 80,000
  /// sigop-cost limit.
  LegacySigOpLimitExceeded(sigop_count: Int)

  /// A contained transaction failed context-free consensus validation.
  ///
  /// `index` is the transaction's zero-based position in the block.
  InvalidTransaction(
    index: Int,
    violations: List(transaction.ConsensusViolation),
  )
}

/// A nonzero maximum proof-of-work target for a Bitcoin network.
///
/// Construct a `PowLimit` with `new_pow_limit` before validating blocks. The
/// constructor validates only that its little-endian representation is exactly
/// 32 bytes and nonzero; selecting the correct limit for the intended network
/// remains the caller's responsibility.
pub opaque type PowLimit {
  PowLimit(PowTarget)
}

/// An error that occurred while constructing a `PowLimit`.
///
/// These errors describe only the supplied representation. They do not verify
/// that a limit is appropriate for a particular Bitcoin network.
pub type PowLimitError {
  /// The supplied limit did not contain exactly 256 bits.
  ///
  /// The fields contain the measured and required bit counts, respectively.
  InvalidBitCount(actual: Int, expected: Int)

  /// The supplied 32-byte limit represented zero.
  ZeroPowLimit
}

/// Construct a proof-of-work limit from 32 little-endian bytes.
///
/// The bytes must represent a nonzero unsigned 256-bit value. This validates
/// only the representation; callers remain responsible for selecting the
/// correct proof-of-work limit for the network whose blocks they validate.
pub fn new_pow_limit(bytes: BitArray) -> Result(PowLimit, PowLimitError) {
  bytes
  |> pow_target.from_bytes_le
  |> result.map_error(fn(err) {
    case err {
      pow_target.InvalidBitCount(actual:, expected:) ->
        InvalidBitCount(actual:, expected:)

      pow_target.ZeroTarget -> ZeroPowLimit

      // `from_bytes_le` interprets the input as an unsigned magnitude, so it
      // never applies the compact encoding's sign-bit rule.
      pow_target.NegativeTarget ->
        panic as "a 32-byte unsigned proof-of-work limit cannot be negative"

      // `from_bytes_le` requires exactly 32 bytes before constructing the
      // target, so the resulting magnitude cannot require more than 256 bits.
      pow_target.Overflow ->
        panic as "a 32-byte proof-of-work limit cannot overflow 256 bits"
    }
  })
  |> result.map(PowLimit)
}

/// Validate a block against context-free Bitcoin consensus rules.
///
/// "Context-free" means these checks require only the block, its contained
/// transactions, and the static proof-of-work limit supplied by the caller. No
/// preceding headers, UTXO set, block height, or activation state is used.
///
/// `pow_limit` must be constructed with `new_pow_limit` from the network's
/// nonzero maximum proof-of-work target in little-endian order. Construction
/// validates only the representation, so selecting the correct network limit
/// remains the caller's responsibility.
///
/// The following rules are enforced:
///
///   - The compact target is valid, does not exceed `pow_limit`, and is
///     satisfied by the block-header hash
///   - The block contains at least one transaction and satisfies the
///     transaction-count, stripped-size, and weight limits
///   - The header Merkle root matches the transaction IDs and the Merkle tree
///     is not mutated
///   - The first transaction has coinbase shape and no later transaction does
///   - The block does not exceed the legacy signature-operation limit
///   - Every contained transaction passes its context-free consensus checks
///
/// This function does not determine the target required by preceding headers,
/// evaluate timestamp or transaction-finality rules, enforce activation-based
/// rules such as the BIP34 coinbase height or SegWit witness commitment, or
/// perform UTXO lookup, script execution, signature verification, fee, or
/// subsidy checks. Signet block-solution validation is outside this function's
/// scope.
///
/// Proof-of-work and block-size violations fail immediately and are returned as
/// a single-element list. After those checks pass, independent block-level and
/// transaction-level violations are collected in deterministic validation and
/// wire order.
///
/// Returns `Ok(Block(ContextFreeValidated))` when the block and every contained
/// transaction pass these checks, or `Error(violations)` otherwise.
pub fn validate_context_free_consensus(
  block: Block(Parsed),
  pow_limit: PowLimit,
) -> Result(Block(ContextFreeValidated), List(ConsensusViolation)) {
  // fail fast on pow and block size checks
  use _ <- result.try(
    block
    |> validate_proof_of_work(pow_limit)
    |> result.try(fn(_) { validate_block_size_limits(block) })
    |> result.map_error(fn(violation) { [violation] }),
  )

  // Collect independent block-semantic violations
  // and transaction violations here
  let block_violations =
    [
      validate_merkle_root,
      validate_coinbase_placement,
      validate_legacy_sigop_count,
    ]
    |> list.filter_map(fn(validator) {
      case validator(block) {
        Ok(_) -> Error(Nil)
        Error(violation) -> Ok(violation)
      }
    })

  let #(tx_violations, validated_txs) =
    validate_transactions(block.transactions)

  let violations = list.append(block_violations, tx_violations)
  case violations {
    [] -> Ok(mark_as_context_free_validated(block, validated_txs))
    _ -> Error(violations)
  }
}

/// Verify that the header's compact target is valid, does not exceed the
/// supplied proof-of-work limit, and is satisfied by the header hash.
///
/// `pow_limit` is a valid nonzero 256-bit limit constructed by
/// `new_pow_limit`. An invalid compact target, a target above that limit, or a
/// header hash above the target is reported as `InvalidProofOfWork`.
///
/// This does not determine whether the target is the difficulty required by
/// preceding headers or validate a Signet block solution.
fn validate_proof_of_work(
  block: Block(Parsed),
  pow_limit: PowLimit,
) -> Result(Nil, ConsensusViolation) {
  let PowLimit(limit) = pow_limit

  use target <- result.try(
    <<block.header.target:32-little>>
    |> pow_target.from_compact_encoding
    |> result.replace_error(InvalidProofOfWork),
  )

  use _ <- result.try(validate_pow_target_within_limit(target, limit))

  let assert Ok(block_hash) =
    block
    |> compute_block_hash
    |> hash256.from_bytes_le

  case pow_target.is_satisfied_by(target, block_hash) {
    True -> Ok(Nil)
    False -> Error(InvalidProofOfWork)
  }
}

fn validate_pow_target_within_limit(
  target: PowTarget,
  limit: PowTarget,
) -> Result(Nil, ConsensusViolation) {
  case pow_target.compare(target, limit) {
    Gt -> Error(InvalidProofOfWork)
    Lt | Eq -> Ok(Nil)
  }
}

fn validate_block_size_limits(
  block: Block(Parsed),
) -> Result(Nil, ConsensusViolation) {
  use _ <- result.try(validate_at_least_one_transaction(block))
  use _ <- result.try(validate_transaction_count(block))

  let base_size = compute_base_size(block)
  let max_block_base_size = max_block_weight / witness_scale_factor

  use <- bool.guard(
    base_size > max_block_base_size,
    Error(BaseSizeLimitExceeded(base_size)),
  )

  let witness_serialized_size =
    compute_txs_witness_serialized_size(block.transactions)

  let weight = base_size * witness_scale_factor + witness_serialized_size
  case weight > max_block_weight {
    True -> Error(WeightLimitExceeded(weight))
    False -> Ok(Nil)
  }
}

fn compute_txs_witness_serialized_size(txs: List(Transaction(state))) -> Int {
  compute_txs_witness_serialized_size_loop(txs, 0)
}

fn compute_txs_witness_serialized_size_loop(
  txs: List(Transaction(state)),
  acc: Int,
) -> Int {
  case txs {
    [] -> acc
    [tx, ..rest] ->
      compute_txs_witness_serialized_size_loop(
        rest,
        acc + transaction.compute_witness_serialized_size(tx),
      )
  }
}

fn validate_at_least_one_transaction(
  block: Block(Parsed),
) -> Result(Nil, ConsensusViolation) {
  case block.transaction_count == 0 {
    True -> Error(NoTransactions)
    False -> Ok(Nil)
  }
}

const max_block_weight = 4_000_000

/// Enforce Bitcoin Core's coarse transaction-count component of the block
/// size limit: `transaction_count * WITNESS_SCALE_FACTOR <= MAX_BLOCK_WEIGHT`.
fn validate_transaction_count(
  block: Block(Parsed),
) -> Result(Nil, ConsensusViolation) {
  case block.transaction_count * witness_scale_factor > max_block_weight {
    True -> Error(ImpossiblyLargeTransactionCount)
    False -> Ok(Nil)
  }
}

/// Verify that the header's Merkle root matches the root computed from
/// transaction IDs, rejecting mutated trees only after a matching root.
fn validate_merkle_root(
  block: Block(Parsed),
) -> Result(Nil, ConsensusViolation) {
  let header_merkle_root = hash256.to_bytes_le(block.header.merkle_root)
  let #(computed_merkle_root, mutated) = compute_merkle_root(block)

  case computed_merkle_root == header_merkle_root {
    False -> Error(MerkleRootMismatch(header_merkle_root, computed_merkle_root))
    True if mutated -> Error(MutatedMerkleTree)
    True -> Ok(Nil)
  }
}

/// Enforce that the first transaction has coinbase shape and no later
/// transaction does.
///
/// For this placement check, coinbase shape means exactly one input whose
/// outpoint is null. Transaction-local coinbase rules, such as the scriptSig
/// length restriction, are validated separately. The validator fails
/// immediately on a missing first coinbase or the first unexpected later
/// coinbase.
fn validate_coinbase_placement(
  block: Block(Parsed),
) -> Result(Nil, ConsensusViolation) {
  validate_coinbase_placement_loop(block.transactions, 0)
}

fn validate_coinbase_placement_loop(
  txs: List(Transaction(Parsed)),
  index: Int,
) -> Result(Nil, ConsensusViolation) {
  case txs {
    [] ->
      case index == 0 {
        True -> Error(MissingCoinbase)
        False -> Ok(Nil)
      }

    [tx, ..rest] ->
      case index == 0, transaction_has_coinbase_shape(tx) {
        True, True -> validate_coinbase_placement_loop(rest, 1)
        True, _ -> Error(MissingCoinbase)
        _, True -> Error(UnexpectedCoinbase(index))
        _, _ -> validate_coinbase_placement_loop(rest, index + 1)
      }
  }
}

fn transaction_has_coinbase_shape(tx: Transaction(Parsed)) -> Bool {
  case transaction.get_inputs(tx) {
    [input] -> transaction.input_has_null_outpoint(input)
    _ -> False
  }
}

/// Enforce the block's 20,000 legacy signature-operation limit.
///
/// This sums the structural legacy sigop counts from each transaction's
/// scriptSigs and scriptPubKeys. Witness data is excluded. The check expresses
/// the limit as 80,000 sigop-cost units by applying the witness scale factor,
/// and reports `LegacySigOpLimitExceeded` with the unscaled legacy count.
fn validate_legacy_sigop_count(
  block: Block(Parsed),
) -> Result(Nil, ConsensusViolation) {
  let max_block_sigops_cost = 80_000

  let legacy_sigop_count =
    compute_legacy_sigop_count_loop(block.transactions, 0)

  case legacy_sigop_count * witness_scale_factor > max_block_sigops_cost {
    True -> Error(LegacySigOpLimitExceeded(legacy_sigop_count))
    False -> Ok(Nil)
  }
}

fn compute_legacy_sigop_count_loop(
  txs: List(Transaction(Parsed)),
  acc: Int,
) -> Int {
  case txs {
    [] -> acc
    [tx, ..rest] ->
      compute_legacy_sigop_count_loop(
        rest,
        acc + transaction.compute_legacy_sigop_count(tx),
      )
  }
}

/// Validate all contained transactions, preserving wire order for both
/// indexed violations and successfully validated transactions.
fn validate_transactions(
  txs: List(Transaction(Parsed)),
) -> #(List(ConsensusViolation), List(Transaction(ContextFreeValidated))) {
  let #(violations, validated_txs) =
    list.index_fold(txs, #([], []), fn(acc, tx, i) {
      let #(violations, validated_txs) = acc

      case transaction.validate_context_free_consensus(tx) {
        Ok(tx) -> #(violations, [tx, ..validated_txs])
        Error(tx_violations) -> #(
          [InvalidTransaction(i, tx_violations), ..violations],
          validated_txs,
        )
      }
    })

  #(list.reverse(violations), list.reverse(validated_txs))
}

fn mark_as_context_free_validated(
  block: Block(Parsed),
  validated_txs: List(Transaction(ContextFreeValidated)),
) -> Block(ContextFreeValidated) {
  let Block(header:, transaction_count:, ..) = block

  Block(header:, transaction_count:, transactions: validated_txs)
}

// ==============================================================================
// Serialization
// ==============================================================================

/// Compute the hash that identifies a Bitcoin block.
///
/// Returns the double SHA-256 hash of the block's exact 80-byte header. The
/// transaction count and transactions are not included in this computation.
///
/// The returned 32 bytes use the little-endian byte order carried by previous
/// block hash fields on the Bitcoin wire. This function does not validate the
/// header's proof of work.
///
/// ## See Also
///
/// - `serialize_header` — produces the header serialization being hashed
pub fn compute_block_hash(block: Block(state)) -> BitArray {
  let assert <<_:256-bits>> =
    block.header
    |> serialize_header
    |> double_sha256.hash
}

/// Serialize a block in its complete Bitcoin wire form.
///
/// Returns the 80-byte header followed by the minimal `CompactSize` transaction
/// count and each transaction's full wire serialization in block order. SegWit
/// transactions include their marker, flag, and witness data.
///
/// ## See Also
///
/// - `serialize_header` — serializes only the fixed-size block header
pub fn serialize(block: Block(state)) -> BitArray {
  bit_array.concat([
    serialize_header(block.header),
    compact_size.encode_int(block.transaction_count),
    ..list.map(block.transactions, transaction.serialize)
  ])
}

/// Serialize a block header in its 80-byte Bitcoin wire form.
///
/// Returns the signed version, previous block hash, merkle root, timestamp,
/// compact target, and nonce in their wire order. Integer fields are encoded
/// little-endian, while both hashes retain their existing wire-order bytes.
///
/// ## See Also
///
/// - `compute_block_hash` — hashes this serialization to identify the block
/// - `serialize` — serializes the header and the block's transactions
pub fn serialize_header(header: Header) -> BitArray {
  <<
    header.version:32-little,
    hash256.to_bytes_le(header.previous_block_hash):bits,
    hash256.to_bytes_le(header.merkle_root):bits,
    header.timestamp:32-little,
    header.target:32-little,
    header.nonce:32-little,
  >>
}
