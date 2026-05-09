# btc_tx

A reference-oriented library for parsing and modeling ₿itcoin transactions.  
Designed to closely reflect Bitcoin's wire format and protocol structure.

<!-- [![Package Version](https://img.shields.io/hexpm/v/btc_tx)](https://hex.pm/packages/btc_tx)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/btc_tx/) -->

<!-- ## Installation
```sh
gleam add btc_tx@1
``` -->

## Goals & Philosophy

This library is guided by a small set of principles:

**Correctness over convenience**  
  > Malformed or ambiguous transaction encodings are surfaced explicitly rather than being silently normalized or partially parsed.

**Reference-grade intent**  
  > The library is structured so it can be read alongside Bitcoin documentation as a reliable guide to how transactions are laid out on the wire.

**Faithful modeling of the protocol**  
  > Protocol distinctions and transaction forms are preserved rather than collapsed into convenience abstractions.

This library is intended for educational and infrastructure use.
It parses and models Bitcoin transaction data, including basic serialization
and format checks, but does not perform full transaction validation such as
script evaluation, signature verification, or UTXO-contextual consensus rules.
No security guarantees are provided.

## Key Features

- **Safe parsing**: Configurable resource limits protect against malicious inputs
- **Format detection**: Distinguish legacy and SegWit transactions
- **Rich error context**: Detailed parse errors with byte offsets and context stacks
- **Consensus validation**: Validate transaction structure against Bitcoin consensus constraints
- **Type safety**: Phantom types distinguish validated from unvalidated transactions
- **Script classification**: Identify P2PKH, P2SH, P2WPKH, P2WSH, P2TR, and other
  standard output script templates (structural only; no blockchain or UTXO context required)
- **Serialization**: Access raw stripped or witness-serialized bytes, and compute
  txid and wtxid for validated transactions
- **Cross-runtime**: Supports both Erlang and JavaScript targets

## Quick Start

```gleam
import btc_tx

// Decode from hex
pub fn process(hex: String) -> Result(BitArray, String) {
  case btc_tx.decode_hex(hex) {
    Ok(tx) -> {
      let version = btc_tx.get_version(tx)
      let inputs = btc_tx.get_inputs(tx)
      let outputs = btc_tx.get_outputs(tx)

      case btc_tx.validate_consensus(tx) {
        Error(violations) -> Error("consensus validation failed")
        Ok(validated_tx) -> Ok(btc_tx.compute_txid(validated_tx))
      }
    }
    Error(btc_tx.HexToBytesFailed) -> Error("invalid hex")
    Error(btc_tx.ParseFailed(_)) -> Error("parse failed")
  }
}
```

## Development

```sh
# Run tests on the Erlang target
gleam test -t erlang
# Run tests on the JS target
gleam test -t javascript --runtime node
gleam test -t javascript --runtime deno
gleam test -t javascript --runtime bun
```

### Fuzz Testing
See [here](https://github.com/caquinn7/btc-tx/blob/main/dev/fuzz_test/fuzz_test.md) for details.

```sh
# Run with a random seed
gleam dev --target erlang fuzz <iterations>
gleam dev --target javascript --runtime node fuzz <iterations>
gleam dev --target javascript --runtime deno fuzz <iterations>
gleam dev --target javascript --runtime bun fuzz <iterations>

# Run with a specific seed (for reproducibility)
gleam dev --target erlang fuzz <iterations> <seed>
```

