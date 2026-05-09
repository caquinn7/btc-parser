# Fuzz Testing Purpose — btc_tx Library

## Overview

The purpose of fuzz testing in the `btc_tx` library is to ensure that the transaction parser behaves **safely, predictably, and robustly** when given arbitrary byte input.

This includes malformed, adversarial, and edge-case data—not just valid Bitcoin transactions.

> **Core Goal:**  
> Guarantee that *any input* results in either a correct parse or a well-defined error—never a crash, hang, or undefined behavior.

---

## Primary Objectives

### 1. Robustness Against Arbitrary Input

The parser operates on raw, potentially untrusted transaction bytes.

Fuzz testing ensures that:
- The parser **never panics or crashes**
- No **infinite loops or hangs** occur
- Memory usage stays within **defined policy limits**

This validates the effectiveness of safeguards such as:
- `max_tx_size`
- `max_vin_count`
- `max_vout_count`
- Optional witness limits

---

### 2. Discovery of Unexpected Edge Cases

Even well-designed parsers can miss rare or unusual structures.

Fuzzing helps uncover:
- Unusual script lengths
- Unexpected witness stack shapes
- Edge-case varint encodings
- Boundary conditions near policy limits

These are often combinations that are:
- Valid but uncommon
- Invalid in subtle ways
- Not covered by hand-written tests

---

### 3. Validation of Failure Modes

Correct failure behavior is just as important as successful parsing.

Fuzz testing ensures:
- Invalid input → returns a **structured error (`Result`)**
- Policy violations → return **`PolicyLimitExceeded`**
- No partial or inconsistent parsing results are exposed

The parser must:
- Fail **cleanly**
- Fail **deterministically**
- Never leave data in an inconsistent state

---

### 4. Preservation of Internal Invariants

The parser enforces structural guarantees such as:
- Length prefixes match actual data
- Input/output counts are consistent
- Witness stack sizes align with declared counts
- No out-of-bounds reads occur

Fuzz testing continuously attempts to break these invariants.

Any violation indicates a **critical bug**.

---

### 5. Performance and Resource Stress Testing

Fuzzing helps identify pathological cases that may:
- Cause excessive allocations
- Trigger slow parsing paths
- Exploit algorithmic inefficiencies

This is especially relevant for:
- Large transactions near `max_tx_size`
- High input/output counts
- Large scripts or witness data

---

## Role of the Seed Corpus

The fuzzing strategy uses a **seed corpus of real Bitcoin transactions** sourced from two pools: non-coinbase transactions captured from the mempool, and coinbase transactions extracted from mined blocks.

### Why this matters:
- Pure random input is mostly invalid and low-signal
- Real transactions provide **valid structural baselines**
- Mutations explore **realistic edge cases**

### Result:
Higher-quality fuzzing with better coverage of meaningful scenarios.

---

## Scope and Non-Goals

Fuzz testing in this project **does NOT** aim to:

- Validate full Bitcoin consensus correctness
- Classify transaction types
- Use external blockchain context (e.g., UTXO set, previous outputs)

### Important Constraint:
The parser operates **in isolation**, using only the transaction bytes.

---

## Summary

Fuzz testing ensures that the `btc_tx` parser:

- Handles **any byte input safely**
- Produces **correct results or well-defined errors**
- Maintains **internal consistency**
- Respects **resource constraints**

> In short:  
> The parser should be **impossible to break with input alone**.

---