# btc_tx

<!-- [![Package Version](https://img.shields.io/hexpm/v/btc_tx)](https://hex.pm/packages/btc_tx)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/btc_tx/) -->

A reference-oriented library for parsing and modeling Bitcoin transactions.

Designed to closely reflect Bitcoin's wire format and protocol structure.

This library is intended for educational and infrastructure use.
It parses and models Bitcoin transaction data, including basic serialization
and format checks, but does not perform full transaction validation such as
script evaluation, signature verification, or UTXO-contextual consensus rules.
No security guarantees are provided.

## Key Features

- **Safe parsing**: Configurable resource limits constrain work and allocation
  when parsing untrusted inputs

- **Rich error context**: Detailed parse errors with byte offsets and context stacks

- **Format detection**: Distinguish legacy and SegWit transactions

- **Transaction inspection**: Access versions, lock times, inputs, outputs, prevouts,
  script bytes, output values, and SegWit witness stacks

- **Script classification**: Identify P2PKH, P2SH, P2WPKH, P2WSH, P2TR, and other
  standard output script templates (structural only; no blockchain or UTXO context required)

- **Context-free consensus validation**: Check transaction-local consensus rules
  such as input/output presence, output value ranges, coinbase structure, and duplicate inputs

- **Validation-aware API**: Phantom types distinguish parsed transactions from
  transactions that have passed context-free consensus validation

- **Serialization**: Serialize decoded transactions in stripped or full wire
  form, and compute their txid and wtxid

- **Cross-runtime**: Supports both Erlang and JavaScript targets

<!-- ## Installation
```sh
gleam add btc_tx@1
``` -->

## Quick Start

```gleam
import btc_tx
import gleam/result

pub fn txid_from_bytes(
  bytes: BitArray,
) -> Result(BitArray, btc_tx.DecodeError) {
  bytes
  |> btc_tx.decode
  |> result.map(btc_tx.compute_txid)
}
```

## Goals & Philosophy

This library is guided by a small set of principles:

### Correctness over convenience

  > Malformed or ambiguous transaction encodings are surfaced explicitly rather than being silently normalized or partially parsed.

### Reference-grade intent
  
  > The library is structured so it can be read alongside Bitcoin documentation as a reliable guide to how transactions are laid out on the wire.

### Faithful modeling of the protocol

  > Protocol distinctions and transaction forms are preserved rather than collapsed into convenience abstractions.

## Use Cases

- **Explorers and blockchain indexers**:
  Turn externally obtained raw transactions into structured data for display,
  search, and downstream analysis.

- **Monitoring and research**:
  Examine caller-provided mempool feeds or datasets for transaction shapes,
  output types, and witness usage.

- **Wallet and protocol tooling**:
  Add a transaction decoding layer ahead of application-specific
  transaction processing.

- **Testing and education**:
  Study Bitcoin transaction encoding and test software against
  malformed transaction data.

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
arbitrary bytes. See [dev/fuzz/README.md](dev/fuzz/README.md)
for commands, seed replay, and scope.

### Performance Testing

The perf harness benchmarks public transaction workflows to detect performance
slowdowns in decoding, inspection, validation, hashing, and serialization.
Compare results only between runs on the same machine, target, and runtime. See
[dev/perf/README.md](dev/perf/README.md) for commands, benchmark coverage, and
result interpretation.
