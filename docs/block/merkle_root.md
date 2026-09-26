# Transaction Merkle Roots

A Bitcoin block header does not contain every transaction. Instead, it contains
one 32-byte value that commits to the block's ordered transaction list: the
transaction Merkle root.

`btc_parser` computes this value with `block.compute_merkle_root`. The function
also reports whether the tree has Bitcoin's historical duplicate-hash ambiguity
by returning either `NonMutated(root)` or `Mutated(root)`.

---

## What a Merkle root represents

A Merkle tree repeatedly combines pairs of hashes until only one hash remains.
For a Bitcoin block:

- Each leaf is a transaction ID (`txid`) in block order. Witness transaction
  IDs (`wtxid`s) are not used.
- Each parent is the double-SHA-256 hash of two concatenated child hashes.
- Each level preserves left-to-right ordering.
- A final unpaired hash is duplicated so that it can form a pair.
- The one hash at the top is the transaction Merkle root recorded in the block
  header.

Outside three important exceptions, changing committed transaction bytes,
reordering distinct transaction IDs, or changing the transaction count changes
the root:

- Witness-only changes do not affect this tree because its leaves are `txid`s,
  not `wtxid`s. SegWit commits to witness data separately.
- Odd-node padding lets certain transaction lists with duplicated suffixes
  produce the same root. The mutation status described below detects this
  ambiguity.
- As with any cryptographic hash commitment, this reasoning assumes an attacker
  cannot find collisions in double SHA-256.

Subject to those qualifications, a node can recompute the root from the block's
transactions and compare it with the header without storing the complete
transaction list in the header.

The Merkle root is a commitment to the transaction IDs, not a substitute for
transaction or block validation.

---

## The parent-hash operation

This guide uses `H` for double SHA-256 and `P` for the parent operation:

```text
H(bytes)       = SHA256(SHA256(bytes))
P(left, right) = H(left || right)
```

`||` means byte concatenation. Each child contributes exactly 32 bytes, so a
parent hashes 64 bytes.

The library exposes transaction IDs and Merkle roots as `Hash256` values in the
same little-endian byte order used on the Bitcoin wire. Merkle construction
concatenates those raw wire-order bytes. Convert a hash with
`hash256.to_bytes_le` when raw bytes are needed, or use
`hash256.to_display_hex` for the reversed notation conventionally shown by
block explorers.

---

## Computing the tree

Given the transaction IDs in block order:

1. Start with all transaction IDs as the leaf level.
2. Read the level from left to right in pairs.
3. For every complete pair, record mutation if the two hashes are identical.
4. If one hash remains unpaired, duplicate it for padding. This padding does
   not record mutation.
5. Hash each pair with `P(left, right)` to construct the next level.
6. Repeat until one hash remains, carrying mutation status forward across all
   levels.

The final value is returned as `Mutated(root)` if any actual pair contained
identical hashes, or `NonMutated(root)` otherwise.

### Four leaves

Four transaction IDs form two complete pairs, followed by one root pair:

```text
                         R = P(AB, CD)
                        /             \
               AB = P(A, B)       CD = P(C, D)
                  /     \             /     \
                 A       B           C       D
              txid 0  txid 1      txid 2  txid 3
```

In equation form:

```text
AB = H(A || B)
CD = H(C || D)
R  = H(AB || CD)
```

If `A != B`, `C != D`, and `AB != CD`, the result is `NonMutated(R)`.
Equality is checked at every level, so identical parent hashes would also mark
the tree as mutated.

### Three leaves and odd-node padding

With three transaction IDs, `C` has no partner. It is duplicated only to build
the parent level:

```text
                         R = P(AB, CC)
                        /             \
               AB = P(A, B)       CC = P(C, C)
                  /     \             /     \
                 A       B           C      (C)
              txid 0  txid 1      txid 2   padding
```

```text
AB = H(A || B)
CC = H(C || C)
R  = H(AB || CC)
```

The parent `CC` contains equal inputs, but they are equal because the algorithm
supplied the parenthesized `C` as padding. Normal odd-node padding is therefore
not mutation, and this tree returns `NonMutated(R)`.

---

## Mutation detection

Mutation detection distinguishes padding from identical hashes that were
already present as a complete pair before padding.

Consider these two transaction-ID lists:

```text
Three leaves:  [A, B, C]
Four leaves:   [A, B, C, C]
```

They produce the same hash calculation:

```text
AB = H(A || B)
CC = H(C || C)
R  = H(AB || CC)
```

Their mutation status differs:

| Transaction IDs | Why `C` is paired with `C` | Result |
| --- | --- | --- |
| `[A, B, C]` | The algorithm supplied odd-node padding | `NonMutated(R)` |
| `[A, B, C, C]` | Both hashes were present in an actual pair | `Mutated(R)` |

The root alone cannot distinguish these shapes. The mutation status preserves
that distinction for validation. It is accumulated at every tree level, not
only among transaction IDs. For example, `[A, B, A, B]` first produces two
identical `AB` parents; pairing those actual parents marks the tree as mutated.

The status is sometimes called a "mutation flag," but it is not serialized in
the block header. It is an output of the local Merkle-tree computation.

### Why the mutation status exists

The check exists to defend against the ambiguity behind
[CVE-2012-2459](https://bitcoin.org/dos/), a denial-of-service vulnerability
reported and fixed in 2012. An attacker could add duplicate transactions in the
specific positions created by odd-node padding, producing an invalid block with
the same Merkle root—and therefore the same block-header hash—as the version
without those duplicates.

If a vulnerable node received the invalid form first, it could cache that block
hash as invalid and later refuse the valid form because both shared the same
hash. Detecting identical hashes in actual pairs lets validation reject the
ambiguous tree without treating ordinary padding as mutation. Bitcoin Core
documents this history and defense in its
[Merkle implementation](https://github.com/bitcoin/bitcoin/blob/master/src/consensus/merkle.cpp).

---

## Empty and single-transaction inputs

`block.compute_merkle_root` defines two boundary cases:

| Transactions | Result |
| --- | --- |
| None | `NonMutated` containing the all-zero `Hash256` |
| One | `NonMutated` containing that transaction's `txid` |

The empty case makes the computation total for any structurally parsed block.
It does not make an empty block consensus-valid;
`block.validate_context_free_consensus` separately rejects blocks without a
transaction.

---

## Using the result

`compute_merkle_root` returns a tagged value so callers must name the mutation
state when inspecting it:

```gleam
import btc_parser/block
import btc_parser/hash256

case block.compute_merkle_root(parsed_block) {
  block.NonMutated(root) ->
    hash256.to_display_hex(root)

  block.Mutated(root) ->
    // The root is still available for diagnostics or header comparison.
    hash256.to_display_hex(root)
}
```

Both constructors contain the computed `Hash256`. The function itself does not
compare that hash with the header or validate the block. Context-free block
validation performs both checks and preserves their diagnostic order:

1. A computed root that differs from the header produces `MerkleRootMismatch`.
2. A matching root from a mutated tree produces `MutatedMerkleTree`.

This ordering reports the most immediate commitment failure while still
rejecting a matching but ambiguous Merkle tree.
