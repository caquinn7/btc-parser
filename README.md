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
- **Rich error context**: Detailed parse errors with byte offsets and context stacks
- **Format detection**: Distinguish legacy and SegWit transactions
- **Transaction inspection**: Access versions, lock times, inputs, outputs, prevouts,
  script bytes, output values, and SegWit witness stacks
- **Script classification**: Identify P2PKH, P2SH, P2WPKH, P2WSH, P2TR, and other
  standard output script templates (structural only; no blockchain or UTXO context required)
- **Context-free consensus validation**: Check transaction-local consensus rules
  such as input/output presence, MoneyRange, coinbase structure, and duplicate inputs
- **Validation-aware API**: Separate parsed transactions from operations that
  require consensus validation
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

### Unit Tests
```sh
# Run tests on the Erlang target
gleam test -t erlang
# Run tests on the JS target
gleam test -t javascript --runtime node
gleam test -t javascript --runtime deno
gleam test -t javascript --runtime bun
```

### Fuzz Testing
The fuzz harness mutates real transactions to stress parser safety against
arbitrary bytes. See [dev/fuzz_test/README.md](dev/fuzz_test/README.md)
for commands, seed replay, and scope.

### Performance Testing
The perf harness benchmarks public transaction workflows to catch broad
regressions within the same machine, target, and runtime. See
[dev/perf_test/README.md](dev/perf_test/README.md) for commands, benchmark
coverage, and result interpretation.
