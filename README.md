# btc_tx

A reference-oriented library for parsing and modeling ₿itcoin transaction data.

> ⚠️ **Status:** This library is under active development and is not yet ready for general use.

<!-- [![Package Version](https://img.shields.io/hexpm/v/btc_tx)](https://hex.pm/packages/btc_tx)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/btc_tx/) -->

## Goals & Philosophy

This library is guided by a small set of principles:

- **Correctness over convenience**  
  Malformed or ambiguous transaction encodings are surfaced explicitly rather than being silently normalized or partially parsed.

- **Reference-grade intent**  
  The library is structured so it can be read alongside Bitcoin documentation as a reliable guide to how transactions are laid out on the wire.

- **Faithful modeling of the protocol**  
  Protocol distinctions and transaction forms are preserved rather than collapsed into convenience abstractions.

This library is intended for educational and infrastructure use.
It parses and models Bitcoin transaction data, including basic serialization
and format checks, but does not perform full transaction validation such as
script evaluation, signature verification, or UTXO-contextual consensus rules.
No security guarantees are provided.

<!-- ```sh
gleam add btc_tx@1
``` -->

## Key Features

- **Safe parsing**: Configurable resource limits protect against malicious inputs
- **Format detection**: Distinguish legacy and SegWit transactions
- **Rich error context**: Detailed parse errors with byte offsets and context stacks
- **Consensus validation**: Check transactions against Bitcoin's consensus rules
- **Type safety**: Phantom types distinguish validated from unvalidated transactions
- **Script classification**: Identify P2PKH, P2SH, P2WPKH, P2WSH, P2TR, and other
  standard output script templates
- **Serialization**: Access raw stripped or witness-serialized bytes, and compute
  txid and wtxid for validated transactions

## Quick Start

```gleam
import btc_tx

// Decode from hex
case btc_tx.decode_hex("0100000001...") {
  Ok(tx) -> {
    // Inspect transaction
    let version = btc_tx.get_version(tx)
    let inputs = btc_tx.get_inputs(tx)
    let outputs = btc_tx.get_outputs(tx)

    // Validate consensus rules
    case btc_tx.validate_consensus(tx) {
      Ok(validated_tx) -> // Transaction is consensus-valid
      Error(errors) -> // Handle validation failures
    }
  }
  Error(btc_tx.ParseFailed(err)) -> // Handle parse error
  Error(btc_tx.HexToBytesFailed) -> // Handle hex error
}
```

<!-- Further documentation can be found at <https://hexdocs.pm/btc_tx>. -->

## Development

```sh
gleam test -t javascript  # Run tests on the JS target
gleam test -t erlang  # Run tests on the Erlang target
```
