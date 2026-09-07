# `btc_parser` examples

This standalone Erlang project demonstrates the public `btc_parser` API with
raw mainnet data fetched from [mempool.space](https://mempool.space). It is not
part of the library package and adds no networking API to `btc_parser`.

Run commands from the repository root. Each completed example writes one JSON
document to stdout. Invalid command-line input and network failures are written
to stderr and exit unsuccessfully.

```sh
./examples/run -- transaction-json \
  4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b

./examples/run -- block-metrics 0
./examples/run -- validate-block 0
./examples/run -- safe-decode
```

## Commands

### `transaction-json <txid>`

Downloads `/api/tx/<txid>/raw`, deserializes the transaction, and emits a
JSON-friendly view of its identifiers, inputs, outputs, structural script
classifications, and witness data.

### `block-metrics <height>`

Resolves `/api/block-height/<height>`, downloads the corresponding raw block,
and emits aggregate transaction, script-template, SegWit, size, weight, and
virtual-size metrics.

### `validate-block <height>`

Downloads a raw mainnet block and runs `block.validate_context_free_consensus`
with Bitcoin mainnet's proof-of-work limit. Its JSON report also states whether
the locally computed display block hash matches mempool.space's resolved hash
and whether serialization reproduces the downloaded bytes.

`context_free_valid` is not full node validation. It does not check prior
headers, required difficulty, timestamps, UTXOs, fees, subsidy, scripts,
signatures, or address ownership.

### `safe-decode [transaction-hex]`

Attempts to deserialize user-supplied transaction hex. Without an argument it
uses the deliberately truncated `010203` input. Decode failures expose the
parser's byte offset, structural path, and kind-specific details as JSON.

## Notes

- All live endpoints are mainnet-only and unauthenticated.
- mempool.space is an external data source; availability and responses are not
  guaranteed by this repository.
- Identifiers and hashes in JSON use Bitcoin's conventional display byte order.
  Raw `btc_parser` hash values preserve wire byte order.
