# btc_parser

<!-- [![Package Version](https://img.shields.io/hexpm/v/btc_parser)](https://hex.pm/packages/btc_parser)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/btc_parser/) -->

A Gleam library for decoding, inspecting, and structurally validating Bitcoin wire-format data in Gleam.

`btc_parser` is designed to reflect Bitcoin's wire formats and protocol
structures closely, expose malformed encodings as structured errors, and remain
portable across Erlang and JavaScript targets.

## Project Status

The following Bitcoin wire-format data structures are currently implemented:

- [`btc_parser/transaction`](docs/transaction/transaction.md) decodes, inspects, validates,
  and serializes legacy and SegWit transactions.
- [`btc_parser/block`](src/btc_parser/block.gleam) decodes complete blocks,
  exposes their headers and wire-order legacy and SegWit transactions.

The block module is still in progress and will expand as its API matures.

Additional domains may be added as the library expands.

<!-- ## Installation
```sh
gleam add btc_parser@1
``` -->

## Goals and Philosophy

### Correctness over convenience

> Malformed or ambiguous encodings are surfaced explicitly rather than being
> silently normalized or partially parsed.

### Reference-grade intent

> The library is structured so it can be read alongside Bitcoin documentation
> as a reliable guide to wire formats and protocol data structures.

### Faithful protocol modeling

> Protocol distinctions and encoded forms are preserved rather than collapsed
> into convenience abstractions.

### Cross-runtime portability

> Public behavior remains consistent across Erlang and JavaScript targets

## Scope

This project parses and models caller-provided Bitcoin data. It is not a wallet,
full node, RPC client, or networking library. Domain-specific documentation
describes the exact parsing, validation, and policy boundaries for each
implemented module.

No security guarantees are provided.

## Development

Run the unit tests on Erlang and the supported JavaScript runtimes:

```sh
gleam test -t erlang
gleam test -t javascript --runtime node
gleam test -t javascript --runtime deno
gleam test -t javascript --runtime bun
```

### Fuzz Testing

The [fuzz harness](dev/fuzz/README.md) exercises parser safety against malformed
and mutated wire-format inputs. Domain suites can provide their own seed inputs
and structural mutations while sharing the project-level command workflow.

### Benchmarking

The [performance harness](dev/perf/README.md) measures public decoding and
inspection workflows across representative inputs, scaling dimensions, and
fail-fast paths. Domain-specific benchmark suites can be added as the library
grows.
