# `btc_parser/block`

The block domain deserializes, inspects, validates, and serializes Bitcoin
blocks while preserving Bitcoin's wire representation.

## Features

- **Safe deserialization**: Configurable block-size and transaction-count limits
  constrain work and allocation when deserializing untrusted block bytes.
- **Rich decode diagnostics**: Decode errors include byte offsets and stable
  structural paths, with contained transaction failures preserved for further
  inspection.
- **Block inspection**: Access the header, header fields, transaction count, and
  transactions in wire order.
- **Measurements and Merkle trees**: Compute BIP 141 base size, total size,
  weight, and upward-rounded virtual size in vbytes, as well as the transaction
  Merkle root with explicit `Mutated` or `NonMutated` status.
- **Context-free consensus validation**: Check proof of work, block size and
  weight limits, transaction-count bounds, the transaction Merkle root,
  coinbase placement, the legacy sigop limit, and every contained transaction's
  context-free consensus rules.
- **Validation-aware API**: Phantom types distinguish parsed blocks from blocks
  that passed the available context-free consensus checks.
- **Serialization and identifiers**: Serialize complete blocks or their
  80-byte headers and compute block hashes.

## Quick Start

```gleam
import btc_parser/block
import btc_parser/hash256
import btc_parser/transaction
import gleam/result

pub fn display_block_hash_from_bytes(
  bytes: BitArray,
) -> Result(String, block.DecodeError) {
  bytes
  |> block.deserialize
  |> result.map(block.compute_block_hash)
  |> result.map(hash256.to_display_hex)
}

pub fn block_hash_bytes_from_hex(
  hex: String,
) -> Result(BitArray, block.DeserializeHexError) {
  hex
  |> block.deserialize_hex
  |> result.map(block.compute_block_hash)
  |> result.map(hash256.to_bytes_le)
}
```

## Decode Policy

Block decoding applies the limit configured by
`block.decode_policy_with_max_block_size` to the complete block byte envelope
and uses the configured transaction policy for every contained transaction. For
example, a caller can allow larger scripts while keeping the block limits at
their defaults:

```gleam
let transaction_policy =
  transaction.default_decode_policy()
  |> transaction.decode_policy_with_max_script_size(20_000)

let policy =
  block.default_decode_policy()
  |> block.decode_policy_with_transaction_policy(transaction_policy)

let result = block.deserialize_with_policy(block_bytes, policy)
```

The limit configured by `transaction.decode_policy_with_max_tx_size` is ignored
for contained transactions. The block's maximum serialized size remains the
only byte-envelope limit for the block and its transactions.

Previous-block hashes, Merkle roots, and computed block hashes are exposed as
`Hash256` values in the same little-endian order used on the Bitcoin wire. Use
`hash256.to_display_hex` for conventional explorer notation or
`hash256.to_bytes_le` for the exact 32 wire-order bytes.

## Context-Free Consensus Validation

Deserialization produces a `Block(Parsed)`. Pass that block and the intended
network's proof-of-work limit to `validate_context_free_consensus` to obtain a
`Block(ContextFreeValidated)`:

For mainnet, supply its maximum target as 32 little-endian bytes:

```gleam
let mainnet_pow_limit_le = <<0:size(208), 0xFF, 0xFF, 0:size(32)>>
let assert Ok(pow_limit) = block.new_pow_limit(mainnet_pow_limit_le)
let assert Ok(validated_block) =
  block.validate_context_free_consensus(parsed_block, pow_limit)
```

`new_pow_limit` checks that the supplied value is nonzero and exactly 32 bytes.
It cannot determine whether the value is the correct limit for the network.

Proof-of-work and block-size failures stop validation immediately. Once those
checks pass, independent block-level and transaction-level violations are
collected in deterministic validation and wire order.

Proof-of-work failures include a reason that distinguishes malformed compact
targets, targets above the supplied limit, and insufficient header work.

## Scope

The module performs whole-value deserialization, structural inspection,
serialization, hashing, measurement, Merkle-root computation, and documented
context-free consensus checks. It does not determine the target required by
preceding headers, evaluate timestamp or transaction-finality rules, enforce
activation-based rules such as the BIP34 coinbase height or SegWit witness
commitment, or perform UTXO lookup, script execution, signature verification,
fee, or subsidy checks. Signet block-solution validation is also outside its
scope.

## Documentation

- [Merkle root](merkle_root.md)
- [Transaction domain](https://github.com/caquinn7/btc-parser/blob/main/docs/transaction/transaction.md)
- [Project overview](https://github.com/caquinn7/btc-parser)
