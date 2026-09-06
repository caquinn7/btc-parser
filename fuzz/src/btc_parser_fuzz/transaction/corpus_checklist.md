# Bitcoin Transaction Fuzz Corpus Checklist

## Purpose

This checklist tracks the real mainnet transactions used as mutation seeds by
the standalone transaction fuzz suite. Its goal is to maximize structural and
scaling coverage observable through the public transaction API.

The current corpus contains 77 transactions and covers 19 of the 41 codes in
the canonical legend. The 22 uncovered codes are intentional, measurable work
items rather than subjective collection buckets.

The corpus supports:

- fuzzing seed inputs
- regression reproduction
- parser, serializer, and identifier validation
- performance investigation
- preservation of structurally distinct real-world transaction encodings

Codes describe properties of the original seed transaction. They do not
describe invalid states that mutations can synthesize, such as non-minimal
CompactSize values, truncated fields, trailing bytes, invalid SegWit markers,
or superfluous witness records. The harness does not use codes when selecting or
mutating seeds; they document coverage and support deliberate corpus review.

Every satisfied code must be applied to every seed. A code is a reusable
boolean predicate, never a provenance label or a unique seed identifier.

## Corpus Record Format

The transaction corpus uses one pipe-delimited record per line:

```text
display_txid|codes|raw_hex
```

Multiple codes are comma-separated in canonical legend order. The display txid
identifies the seed; the codes are exhaustive coverage tags. Code definitions
in [`seed_txs_codes.txt`](../../../corpus/transaction/seed_txs_codes.txt) are
the canonical legend, and the records are in
[`seed_txs.txt`](../../../corpus/transaction/seed_txs.txt).

## Status Legend

- `[ ]` TODO
- `[x]` HAVE
- `[~]` EXPAND

## Current Corpus

All 77 records deserialize under the default policy, pass the available
context-free consensus checks, reproduce their original bytes through complete
serialization, and match their recorded display txids. Together they contain
226,666 raw bytes and 338 exhaustive code assignments.

The `Bytes` column is complete serialized size. More detailed base-size,
witness, script, stack, identifier, and classifier metrics are available from
the repeatable metrics command documented under Seed Evaluation and
Verification.

| Display txid | Codes | Format | Inputs | Outputs | Bytes |
| --- | --- | --- | ---: | ---: | ---: |
| `00000000026de5b8e58cbf9877b905fdbe0d0030d3e7375a6ae4f7b10e4c7123` | `T02,I01,F04,F08` | SegWit | 1 | 4 | 275 |
| `00e6e635f1b4aa423b86240900c3b97a22cc9c903abf042b7e8464feeda96845` | `T02,I01,F06,F08` | SegWit | 1 | 3 | 294 |
| `14f3055162df2330cd07488f78d5917f9f66253911d5283e6711c17a7a4c10d3` | `T01,I01,F02,F04` | Legacy | 1 | 10 | 473 |
| `169bee0546af80def5e7de9ec2c534e2ddc70f98690ee2eafea3b5f165263a3d` | `T02,I01,O01,F04` | SegWit | 1 | 1 | 151 |
| `17afd9db959d70f8b159d1ee1e7943b0e3e3c0d2a16d8b12a77df11732f04838` | `T02,F02,F03,F04,F05,F06` | SegWit | 2 | 128 | 4,487 |
| `18b361c4eac447caf914761ba1d4f14019b7ceaff97186da21b361b86c99a00b` | `T02,W09,F04,F06,F08` | SegWit | 3 | 3 | 541 |
| `19c076a9003465ec61ed5083eb9b94a4b058d1e202e6d8dde1a36ead84ce1a3f` | `T02,O01,W09,F03` | SegWit | 12 | 1 | 2,101 |
| `1a108ff0ea39c0f190a5526984482fd9b81bb3debccae298771c8c444335380e` | `T02,O01,W09,F04` | SegWit | 5 | 1 | 786 |
| `1c69151db358975b1471a64fb080f6c09504d4ea0be64c620c1ac7c5f6f065da` | `T02,I01,F02,F04,F05` | SegWit | 1 | 24 | 969 |
| `2447376590bfdc6a043745773d69ce6deb4c3095491cca0c173fcbd710d6e9a9` | `T01,O01,F03` | Legacy | 23 | 1 | 3,423 |
| `25e1ed03531c23d4ef49f8b13979627d4327e1f85e20632a61a64b09e9ff1b68` | `T02,I01,F06,F08` | SegWit | 1 | 3 | 294 |
| `26a1a488ce3dc6d810d504b4f24c51f9ab5a44ea419925c11deee9f868ea0a5b` | `T02,I01,F04,F08` | SegWit | 1 | 2 | 221 |
| `2ccc58d725421d768790fbfbb8fe0a8d2f772b4cd8a335061b7be1ebac437dc1` | `T02,I01,O01,F04` | SegWit | 1 | 1 | 150 |
| `30178b29fd5e16e80897caecebed7485c96ff127b0d59b296fa525477fa1397b` | `T02,O01,W09,F04` | SegWit | 5 | 1 | 786 |
| `31660a8b216bf88b9231864e5cd69dd6ce029d47e000c2dbb0c33f2cd135e2a9` | `T02,T03,I01,F02,F08,C02` | SegWit | 1 | 8 | 535 |
| `32c2f3df1f469281a47fba802f3a2bdf09b421bb93bec4c4157ca2c0f80d1275` | `T01,I01,F02,F04` | Legacy | 1 | 2 | 223 |
| `36d5063d5f12caafb868c9002855f91273d73934f3df968b6db0b370aba86d94` | `T02,I01,F06,F10,F11` | SegWit | 1 | 2 | 482 |
| `413ad022a450daaef6ddd214f0b7425fc55482d180cf0a3616a636e6c15f7f96` | `T01,I01,F02,F04` | Legacy | 1 | 2 | 223 |
| `440acfd72a35192c0f17b7a601159989aa3a7de84e57a17a2bfa23e1af32a742` | `T01,O01,F04` | Legacy | 7 | 1 | 1,070 |
| `4765c476e2869202e56272e28c534a9f755c5c9ad73f8cda084b68192ae35834` | `T02,O01,W09,F03` | SegWit | 15 | 1 | 2,617 |
| `53bacc54b8478d8e302e8d72e99b63a8d04bc2bc4a82b38b85199ec70154fd81` | `T02,F04,F06` | SegWit | 31 | 41 | 5,243 |
| `557f589a0988a1a6d349b1ec6711c8ca7f5045937993b6926f59eb35cbdc81f6` | `T02,I01,O01,W09,F05` | SegWit | 1 | 1 | 783 |
| `5d5ce2a1f485e9da2b99f612db14517a2e9038d27355d33d73087b6442026d7a` | `T01,I01,F02,F04` | Legacy | 1 | 13 | 569 |
| `5eeae98819b71ef9823d5b645b3f32abc758fd321396d35c069f5ce84912deaf` | `T02,I01,F04,F08` | SegWit | 1 | 2 | 221 |
| `66259c802ceae9d82ae75772940663981752c56a6f310cb03f81e52276f37f0a` | `T02,I04,O04,F04,F06,S02` | SegWit | 292 | 376 | 49,444 |
| `697389aa45f1e37eadf52ebfc5970e0581a2634f24bae69ca54e41e41d486641` | `T02,I01,F04,F08` | SegWit | 1 | 3 | 359 |
| `69b2c46d2034f7e8d6ca3b313665787cb6a0350a6fe690f7f51d5a8e6fd505be` | `T01,F02,F04` | Legacy | 2 | 4 | 434 |
| `6ed993d617f52b672d9774d768be2246f9eb4baee5c04e01686a4bbbd2fe76bc` | `T02,W02,F04,F06,F10,F11` | SegWit | 2 | 13 | 1,089 |
| `7281dc8c8700a514c3e9bfb6e34329d86e3affed391cd6984f8634e9291c78bf` | `T02,I01,F04,F08` | SegWit | 1 | 2 | 221 |
| `73c6aec52dbea9f4266e258853f2f431578b7879114bb7a59dbed29eff86bf6c` | `T02,I01,O01,W09,F05` | SegWit | 1 | 1 | 908 |
| `760c6610c8c1851da3ce505b4f21f4ad154be5f62d8193a9bf76af55df3c0b0b` | `T01,O01,F04` | Legacy | 4 | 1 | 629 |
| `7bb4925c67699f070ae5f9f81b56b6df6875696401a944ff207fdd988835f787` | `T01,I01,O01,F04` | Legacy | 1 | 1 | 188 |
| `852bbdbe2d21752f7da84db44eb660f252ca4aa09953b478c9944a6d65b4bcd0` | `T02,F04,F06` | SegWit | 40 | 51 | 6,781 |
| `871cda3f7699e38d01c444011a6088752d223dd1fbb896ab4fd1088599c56251` | `T02,W02,W09,F03,F05` | SegWit | 4 | 2 | 1,687 |
| `906a8d7d3d5f1816a0544938f6706f045a3f0f81e00892bd9df1c4ad25146d16` | `T02,I01,O01,F04` | SegWit | 1 | 1 | 150 |
| `90761f460e0501f06733868905056eb3f71504c31e1b88c8bbdb0f16ae15eeb2` | `T02,T03,I01,F05,F08` | SegWit | 1 | 4 | 378 |
| `919b883a6ee22f2ee3dbad088694c091508800bb3e567a61935ae967f5ad34bb` | `T02,I01,F04,F10,F11` | SegWit | 1 | 5 | 1,301 |
| `921cee7a330bc9f174e096249f661fb2b15a51ab4ed3f321a800001a00288388` | `T02,I01,O01,W09,F05` | SegWit | 1 | 1 | 782 |
| `929017ce4d7b31ea14bcddeb87408f3d52c7c908e56e9e2ef7793357fdd1a4e1` | `T02,I01,O01,W09,F05` | SegWit | 1 | 1 | 791 |
| `92a82bb88d7bb9aa85a81f003629ec758a1ed980920fa1a6625ee67751f8fdbf` | `T02,I01,F02,F03,F04,F06` | SegWit | 1 | 13 | 579 |
| `932fd65174beaa946d99d410196a7fcd70819cb044d16511e9c1adf719ab11f3` | `T02,W09,F04` | SegWit | 20 | 2 | 3,045 |
| `954d885973a996f4492e95ff20129afd194d789c7ab64483e6e7f84e33aa454a` | `T02,I01,F04` | SegWit | 1 | 3 | 253 |
| `962a12ec0d3cc4f7a73f34df6b7a5a4976c88c40bdb464abd34dc473db2774dd` | `T02,O01,W09,F03` | SegWit | 10 | 1 | 1,758 |
| `98564289ec31242cf0b382a262ba1747c93a1ea6e9b9724cbd420ab363ba2043` | `T02,I01,W02,W09,F05,F06` | SegWit | 1 | 2 | 358 |
| `985ff0049ea05a078a4524e822e21399bcbf73e2517e2e22dac081c995bec33d` | `T02,O01,W09,F04` | SegWit | 6 | 1 | 934 |
| `9b145f5956e52bf400979a09d50653c9b97ae32cb91eed097bc0e9227a08f755` | `T02,W09,F04` | SegWit | 83 | 2 | 12,403 |
| `9e3ac70f6cbcf20c4988bd9f09d9002fe18fbdac5ae486ab496f558b79be482f` | `T01,F02,F03,F04` | Legacy | 94 | 10 | 14,197 |
| `a01fe39b32b5afb68c7e4d7c5b4c61e4166c3aa987192c64fbdf20b0439afe61` | `T02,I01,F06,F10,F11` | SegWit | 1 | 2 | 1,383 |
| `a055e8ef0e4fe3b5e34851547f219c2ed7daf6a610185affb51c63ffc36a5cea` | `T02,I01,F02,F03,F04,F05` | SegWit | 1 | 35 | 1,286 |
| `a7e7860e6e804f0e0c8a26833f9256014be5be63833b99636d389e076e0f93a6` | `T02,W09,F02,F04` | SegWit | 17 | 11 | 3,263 |
| `ab88823183324578ef46292f9dd6f34cee2df24ab01ffeecf188db5a41af394d` | `T01,I01,O01,F04` | Legacy | 1 | 1 | 189 |
| `b03f41ca7ab71a3257693e4b1ac84966e9d7acd37850666b9c8dadcc423a00e0` | `T02,I01,F04,F10,F11` | SegWit | 1 | 5 | 1,301 |
| `b1ec2056293f89276dc5f3f23f8cae529739cdeb50272d6f916fb23d773bf74d` | `T02,O01,F06` | SegWit | 2 | 1 | 269 |
| `b5e817f3fda3b1f282598f992587f6f13abeaa510fadfe7f0a929971a263480f` | `T02,I01,O01,W09,F02` | SegWit | 1 | 1 | 195 |
| `c0cb7f8934077ef0b84cb645d832a21b46d9a3897383589cd833caee8b66274a` | `T02,F04,F06,F10,F11` | SegWit | 2 | 4 | 1,238 |
| `c375c07f51227219f56893e91fa1f3e25afecdc47308a062e334e9c4942ca8e7` | `T02,W02,W09,F02,F04,F05` | SegWit | 5 | 4 | 1,622 |
| `c37d7c51dcefe52c012a916106b7d31f959be83b672f4b1bc53d49f08aa6ae90` | `T01,I04,O01,F02` | Legacy | 200 | 1 | 29,547 |
| `ca22c52250e844aae77ab5940068432e9d1ea198faecc685aead45bbf614710b` | `T02,W09,F04` | SegWit | 175 | 2 | 26,057 |
| `d0e2a928bcc4ed36af6da66651bd243f829f475100cc2af928fa0e0cb584bd3d` | `T02,I01,W02,W09,F04,F05` | SegWit | 1 | 2 | 380 |
| `d1f84e5b53182152e2a81e4e539248d3575349b64ef49c551a30413e3d8de833` | `T02,I01,F02,F04,F06` | SegWit | 1 | 9 | 413 |
| `d2ca5d9f3a46f4c7a4bfd147fe7c107f23695584b82570b851ce7ba77a0aff4f` | `T02,I01,O01,F04` | SegWit | 1 | 1 | 150 |
| `d84eca789acfa45a6abd16c154adac20ad1230ae02aec842cfbb74303242e606` | `T02,I01,O01,W09,F02` | SegWit | 1 | 1 | 195 |
| `dae246531cebbb536d6e835629a7c69ebf7e22c09b0d7d265c27b68a45ace89b` | `T02,I01,F02,F04,F05,F06` | SegWit | 1 | 32 | 1,205 |
| `dd23c29aee33da575f80391c590a70b178cb45d503bea19183db90b41e16ffad` | `T02,T03,I01,F02,F08,C02` | SegWit | 1 | 8 | 535 |
| `de595adb4b7ef794f0595a5a0fe0a81c6e38be52afd41475e665878b17b478b3` | `T02,I01,O01,W09,F05` | SegWit | 1 | 1 | 884 |
| `e056751c8fbd239043498ba7b2f56a089b153a01017bff98b4bdf88fba74b44b` | `T02,W09,F04` | SegWit | 150 | 2 | 22,353 |
| `e64392bc740e2f5a098627a7e7547dd857c6d3ccb8615f87e237757d2623b535` | `T01,O01,F03` | Legacy | 12 | 1 | 1,806 |
| `e7336d7d326fc186036276e50edc2c805b34788c0e7a82f9198a58815c080c09` | `T02,I01,O01,W09,F02` | SegWit | 1 | 1 | 194 |
| `e965f36a740434ad92417744fe9ebe6f31634488b73e262739d9fce8545729a8` | `T02,I01,F04,F06` | SegWit | 1 | 2 | 234 |
| `ef23f90aa4703a2958a971b4041714d1282fb131a179fff6421db176adbf5f11` | `T02,I01,F06,F08` | SegWit | 1 | 19 | 1,350 |
| `f03d36702fa6463484e517a564f1500e82d0973f2efc9ff2a2925fc553967a38` | `T02,I01,O01,F04` | SegWit | 1 | 1 | 150 |
| `f1b32f6e237a412a4595cb45fdcd26d3db8bd0daba5e50f905f07406af3c78d6` | `T02,F02,F03,F04,F05` | SegWit | 4 | 102 | 3,845 |
| `f50d144afd1c444def34e08b8a212619773c2fc857a6fb331f09758d33f37923` | `T02,I01,O01,F04` | SegWit | 1 | 1 | 150 |
| `f6a041bffca9e7dd7fef5ef32a35c6e752ce3f3326094cb5bc254985f020fbef` | `T01,I01,O01,F04` | Legacy | 1 | 1 | 189 |
| `fa1f7ee9290c65c5e103c1969b5bb151a4c56492319004857222cd4951be29f6` | `T02,I01,F04,F08` | SegWit | 1 | 2 | 221 |
| `fbddf2f3a18005992b662271d8a9ff88a9ff3164d229761fde600c8d0c8d4108` | `T02,I01,O01,W09,F04` | SegWit | 1 | 1 | 191 |
| `fdab5874f64665f34692fad551d120e12e4ecab62a973c8ff34209b79fc4dd45` | `T01,I01,F02,F03,F04` | Legacy | 1 | 4 | 285 |

## Serialization and Role

- [x] **T01 — Uses legacy serialization**
  - 15 transactions, ranging from 188 to 29,547 bytes.
  - Includes the 200-input legacy scaling seed
    `c37d7c51dcefe52c012a916106b7d31f959be83b672f4b1bc53d49f08aa6ae90`.
- [x] **T02 — Uses SegWit serialization**
  - 62 transactions, ranging from 150 to 49,444 bytes.
  - Covers one through 292 witness stacks and several witness-dominated shapes.
- [x] **T03 — Coinbase shape**
  - Three SegWit coinbases have scriptSig lengths 93, 100, and 100 bytes.
  - No legacy coinbase is currently present.

## Input Count

- [x] **I01 — Exactly one input**
  - 48 transactions cover both legacy and SegWit serialization.
- [ ] **I02 — Exactly 252 inputs**
  - Missing the largest one-byte CompactSize input count.
- [ ] **I03 — Exactly 253 inputs**
  - Missing the smallest three-byte CompactSize input count.
- [x] **I04 — At least 200 inputs**
  - `c37d7c51dcefe52c012a916106b7d31f959be83b672f4b1bc53d49f08aa6ae90`
    is legacy with exactly 200 inputs.
  - `66259c802ceae9d82ae75772940663981752c56a6f310cb03f81e52276f37f0a`
    is SegWit with 292 inputs and also supplies the current maximum output count.

The corpus reaches the three-byte input-count path through 292 inputs, but it
does not isolate either side of the 252/253 width transition.

## Output Count

- [x] **O01 — Exactly one output**
  - 30 transactions cover legacy and SegWit serializations and several output
    classifications.
- [ ] **O02 — Exactly 252 outputs**
  - Missing the largest one-byte CompactSize output count.
- [ ] **O03 — Exactly 253 outputs**
  - Missing the smallest three-byte CompactSize output count.
- [x] **O04 — At least 200 outputs**
  - `66259c802ceae9d82ae75772940663981752c56a6f310cb03f81e52276f37f0a`
    has 376 outputs.

The corpus reaches the three-byte output-count path through 376 outputs, but it
does not isolate either side of the 252/253 width transition.

## Witness Structure

- [ ] **W01 — Mixed empty and nonempty witness stacks**
  - No SegWit transaction currently has both shapes across its inputs.
- [x] **W02 — Contains a zero-length witness item**
  - Five transactions carry this shape; their zero-length item counts are 1,
    4, 1, 5, and 1.
- [ ] **W03 — Contains an exactly 252-byte witness item**
  - Missing the largest one-byte CompactSize item length.
- [ ] **W04 — Contains an exactly 253-byte witness item**
  - Missing the smallest three-byte CompactSize item length.
- [ ] **W05 — Contains an exactly 65,535-byte witness item**
  - Missing the largest three-byte CompactSize item length.
- [ ] **W06 — Contains an exactly 65,536-byte witness item**
  - Missing the smallest five-byte CompactSize item length.
- [ ] **W07 — Contains a witness stack with exactly 252 items**
  - Missing the largest one-byte CompactSize stack count.
- [ ] **W08 — Contains a witness stack with exactly 253 items**
  - Missing the smallest three-byte CompactSize stack count.
- [x] **W09 — Witness serialized size is at least base size**
  - 25 transactions are witness-dominated.
  - `ca22c52250e844aae77ab5940068432e9d1ea198faecc685aead45bbf614710b`
    has 18,810 witness bytes and 7,247 base bytes.
  - `73c6aec52dbea9f4266e258853f2f431578b7879114bb7a59dbed29eff86bf6c`
    has the largest ratio: 814 witness bytes to 94 base bytes.

Five existing witness items exercise a three-byte CompactSize length with
sizes from 453 through 579 bytes, but none isolates an exact boundary. The
largest witness stack has only five items, and the largest stack payload is 804
bytes.

## Script Length

- [ ] **L01 — Contains an exactly 252-byte scriptSig**
- [ ] **L02 — Contains an exactly 253-byte scriptSig**
- [ ] **L03 — Contains an exactly 252-byte scriptPubKey**
- [ ] **L04 — Contains an exactly 253-byte scriptPubKey**
- [ ] **L05 — Contains a 9,000-through-10,000-byte scriptSig**
- [ ] **L06 — Contains a 9,000-through-10,000-byte scriptPubKey**

The largest current scriptSig is 107 bytes. Five scriptPubKeys exercise a
three-byte CompactSize length at 309, 814, 1,005, 1,006, and 1,210 bytes, but
none isolates an exact 252/253 boundary. The 1,210-byte maximum remains far
below the default 10,000-byte per-script policy limit.

## Output Classification

- [ ] **F01 — Contains a `P2PK` output**
- [x] **F02 — Contains a `P2PKH` output**
  - 22 transactions.
- [x] **F03 — Contains a `P2SH` output**
  - 12 transactions.
- [x] **F04 — Contains a `P2WPKH` output**
  - 52 transactions.
- [x] **F05 — Contains a `P2WSH` output**
  - 15 transactions.
- [x] **F06 — Contains a `P2TR` output**
  - 18 transactions.
- [ ] **F07 — Contains a `BareMultisig` output**
- [x] **F08 — Contains a `NullData` output**
  - 13 transactions.
- [ ] **F09 — Contains an `UnknownWitnessProgram` output**
- [x] **F10 — Contains a `NonStandard` output**
  - Six transactions.
- [x] **F11 — Contains an OP_RETURN-prefixed `NonStandard` output**
  - The same six transactions currently supply both F10 and F11. Their
    OP_RETURN-prefixed scripts fail `NullData` classification because they are
    oversized or otherwise not recognized as push-only.

The classifier is called for every output after successful deserialization.
F01, F07, and F09 are high-priority additions because random mutation is
unlikely to synthesize their exact templates.

## Transaction Scale

- [ ] **S01 — Total serialized size is 360,000 through 400,000 bytes**
  - The current maximum is only 49,444 bytes, 12.4% of the default 400,000-byte
    decode-policy limit.
- [x] **S02 — At least 200 inputs and at least 200 outputs**
  - `66259c802ceae9d82ae75772940663981752c56a6f310cb03f81e52276f37f0a`
    has 292 inputs, 376 outputs, 27,638 base bytes, and 21,806 witness bytes.

## Coinbase Boundaries

- [ ] **C01 — Coinbase scriptSig is exactly 2 bytes long**
  - The block corpus transaction from mainnet height 84,661 is a natural
    candidate and would also add compact legacy coinbase coverage.
- [x] **C02 — Coinbase scriptSig is exactly 100 bytes long**
  - `31660a8b216bf88b9231864e5cd69dd6ce029d47e000c2dbb0c33f2cd135e2a9`
    and
    `dd23c29aee33da575f80391c590a70b178cb45d503bea19183db90b41e16ffad`
    are both 535-byte SegWit coinbases.

## Corpus Maintenance

Overlapping codes are intentional when transactions isolate different
boundaries, combine independently covered properties in a materially different
shape, or increase the probability that random mutation reaches an extreme
field. Do not remove a seed based only on label overlap.

Before adding or replacing a seed, prefer a candidate that does at least one of
the following:

- covers a code not represented by the current corpus
- targets an exact CompactSize, consensus, or decode-policy boundary
- combines independently covered properties in a materially different shape
- isolates an extreme field in a small transaction so random mutation reaches
  it frequently
- exercises a scaling dimension substantially more cheaply than existing seeds
- preserves a distinct legacy, SegWit, witness, or output-classifier shape

Prune only after comparing the complete derived code set and actual structural
metrics. Similar total size or identical codes alone are not sufficient
evidence of redundancy.

## Seed Evaluation and Verification

Generate the canonical 50-column TSV inventory from the repository root:

```sh
./fuzz/run -m btc_parser_fuzz/transaction/corpus_metrics
```

The extractor uses only the public transaction API and emits records in corpus
order. Run the same report on Node when changing metric logic:

```sh
./fuzz/run -t javascript --runtime node \
  -m btc_parser_fuzz/transaction/corpus_metrics
```

Record or derive these values before accepting a candidate:

- recorded and computed display txid and computed display wtxid
- serialization format and context-free coinbase shape
- input and output counts and their CompactSize widths
- base size, total size, witness serialized size, and weight
- maximum scriptSig and scriptPubKey sizes plus exact boundary occurrences
- empty and nonempty witness-stack counts
- maximum witness-stack item count and payload size
- zero-length and exact-boundary witness-item occurrences
- maximum witness-item size
- count of every public `OutputScriptType` variant
- OP_RETURN-prefixed outputs classified as `NonStandard`
- the complete derived taxonomy code set in canonical order

Before committing a seed, verify that:

- every corpus record has exactly three pipe-delimited fields
- its txid is unique and the raw hex is byte-aligned valid hex
- every recorded code exists in the canonical legend
- recorded codes exactly equal the extractor's derived codes
- it deserializes under the default policy and passes the available
  context-free consensus checks
- complete serialization reproduces the raw bytes
- stripped serialization hashes to the recorded display txid
- wtxid computation succeeds
- the Erlang and Node metric rows are identical

After corpus changes, run the focused fuzz validation from the handoff with one
fixed seed on both targets and confirm identical traces and zero failures.
