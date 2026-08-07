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
- **Measurements and Merkle trees**: Compute BIP 141 base size, total size, and
  weight, as well as the transaction Merkle root and mutation flag.
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
import gleam/result

pub fn block_hash_from_bytes(
  bytes: BitArray,
) -> Result(BitArray, block.DecodeError) {
  bytes
  |> block.deserialize
  |> result.map(block.compute_block_hash)
}

pub fn block_hash_from_hex(
  hex: String,
) -> Result(BitArray, block.DeserializeHexError) {
  hex
  |> block.deserialize_hex
  |> result.map(block.compute_block_hash)
}
```

Previous-block hashes, Merkle roots, and computed block hashes are exposed as
32-byte values in the same little-endian order used on the Bitcoin wire. Reverse
them before displaying the conventional block-hash notation used by explorers.

## Context-Free Consensus Validation

Deserialization produces a `Block(Parsed)`. Pass that block and the intended
network's proof-of-work limit to `validate_context_free_consensus` to obtain a
`Block(ContextFreeValidated)`:

```gleam
let assert Ok(pow_limit) = block.new_pow_limit(network_pow_limit_le)
let assert Ok(validated_block) =
  block.validate_context_free_consensus(parsed_block, pow_limit)
```

`network_pow_limit_le` must contain the network's nonzero maximum target as
exactly 32 little-endian bytes. `new_pow_limit` validates that representation;
it cannot determine whether the supplied value is the correct limit for the
network.

Proof-of-work and block-size failures stop validation immediately. Once those
checks pass, independent block-level and transaction-level violations are
collected in deterministic validation and wire order.

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

- [Project overview](../../README.md)
- [Transaction domain](../transaction/transaction.md)
