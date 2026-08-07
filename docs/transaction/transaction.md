# `btc_parser/transaction`

The transaction domain deserializes, inspects, validates, and serializes Bitcoin
transactions while preserving Bitcoin's wire representation.

## Features

- **Safe deserialization**: Configurable resource limits constrain work and
  allocation when deserializing untrusted transaction bytes.
- **Rich decode diagnostics**: Decode errors include byte offsets and stable
  structural paths.
- **Format detection**: Legacy and SegWit transaction encodings remain distinct.
- **Transaction inspection**: Access versions, lock times, inputs, outputs,
  outpoints, script bytes, output values, and SegWit witness stacks.
- **Script classification**: Structurally identify P2PKH, P2SH, P2WPKH, P2WSH,
  P2TR, and other output script templates.
- **Context-free consensus validation**: Check transaction-local rules such as
  input/output presence, Bitcoin Core's transaction base-size check (at most
  1,000,000 stripped bytes, excluding witness data), output value ranges,
  coinbase structure, and duplicate inputs. Witness data excluded by that
  base-size check still contributes to the separate 4,000,000-WU block-weight
  limit.
- **Validation-aware API**: Phantom types distinguish parsed transactions from
  transactions that passed context-free consensus validation.
- **Serialization, measurements, and identifiers**: Produce stripped or full
  wire bytes, compute BIP 141 base size, total size, and weight, and compute
  txids and wtxids.

## Quick Start

```gleam
import btc_parser/transaction
import gleam/result

pub fn txid_from_bytes(
  bytes: BitArray,
) -> Result(BitArray, transaction.DecodeError) {
  bytes
  |> transaction.deserialize
  |> result.map(transaction.compute_txid)
}

pub fn txid_from_hex(
  hex: String,
) -> Result(BitArray, transaction.DeserializeHexError) {
  hex
  |> transaction.deserialize_hex
  |> result.map(transaction.compute_txid)
}
```

Outpoint txids and computed txids and wtxids are exposed as 32-byte values in
the same little-endian order used on the Bitcoin wire. Reverse them before
displaying the conventional hexadecimal identifier notation used by explorers.

## Scope

The module performs whole-value deserialization, structural inspection,
serialization, output script classification, and documented context-free
consensus checks. It does not perform full transaction validation requiring UTXO
lookup, script execution, signature verification, block context, mempool policy,
or network/RPC access.

## Documentation

- [Project overview](../../README.md)
- [Output script classification](output_script_classification.md)
