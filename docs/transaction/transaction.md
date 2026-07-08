# `btc_parser/transaction`

The transaction domain decodes, inspects, validates, and serializes Bitcoin
transactions while preserving Bitcoin's wire representation.

## Features

- **Safe decoding**: Configurable resource limits constrain work and allocation
  when decoding untrusted transaction bytes.
- **Rich decode diagnostics**: Decode errors include byte offsets and stable
  structural paths.
- **Format detection**: Legacy and SegWit transaction encodings remain distinct.
- **Transaction inspection**: Access versions, lock times, inputs, outputs,
  outpoints, script bytes, output values, and SegWit witness stacks.
- **Script classification**: Structurally identify P2PKH, P2SH, P2WPKH, P2WSH,
  P2TR, and other output script templates.
- **Context-free consensus validation**: Check transaction-local rules such as
  input/output presence, output value ranges, coinbase structure, and duplicate
  inputs.
- **Validation-aware API**: Phantom types distinguish decoded transactions from
  transactions that passed context-free consensus validation.
- **Serialization and identifiers**: Produce stripped or full wire bytes and
  compute txids and wtxids.

## Quick Start

```gleam
import btc_parser/transaction
import gleam/result

pub fn txid_from_bytes(
  bytes: BitArray,
) -> Result(BitArray, transaction.DecodeError) {
  bytes
  |> transaction.decode
  |> result.map(transaction.compute_txid)
}

pub fn txid_from_hex(
  hex: String,
) -> Result(BitArray, transaction.DecodeHexError) {
  hex
  |> transaction.decode_hex
  |> result.map(transaction.compute_txid)
}
```

## Scope

The module performs structural decoding, inspection, serialization, output script
classification, and documented context-free consensus checks. It does not
perform full transaction validation requiring UTXO lookup, script execution,
signature verification, block context, mempool policy, or network/RPC access.

## Use Cases

- **Explorers and blockchain indexers**: Turn externally obtained transaction
  bytes into structured data for display, search, and downstream analysis.
- **Monitoring and research**: Examine caller-provided mempool feeds or datasets
  for transaction shapes, output types, and witness usage.
- **Wallet and protocol tooling**: Add a decoding layer ahead of
  application-specific transaction processing.
- **Testing and education**: Study Bitcoin transaction encoding and exercise
  software with malformed transaction data.

## Documentation

- [Project overview](../../README.md)
- [Output script classification](output_script_classification.md)
