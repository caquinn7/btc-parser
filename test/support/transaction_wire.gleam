//// Test-only helpers for constructing transaction wire encodings.
////
//// Helper names describe the abstraction they return:
////
//// - `build_*_bytes` constructs an encoded component from field values.
//// - `build_minimal_*_section_bytes` returns a count-prefixed minimal fixture.
//// - `assemble_*_bytes` combines existing encodings into a container.
////
//// Names use full domain terminology and an explicit `_bytes` suffix when
//// returning wire bytes so their result is clear at the call site.

import gleam/bit_array
import gleam/list
import support/bitcoin_wire.{compact_size}

/// The minimum encoded input size: a 32-byte txid, 4-byte output index,
/// one-byte empty script length, and 4-byte sequence.
pub const min_input_size_bytes = 41

/// The minimum encoded output size: an 8-byte value and one-byte empty script
/// length.
pub const min_output_size_bytes = 9

/// The four-byte wire encoding of transaction version 1.
pub const transaction_version_1_bytes = <<1:little-size(32)>>

/// Produce a `BitArray` consisting of `n` repetitions of byte `b`.
pub fn repeat_byte(b: Int, n: Int) -> BitArray {
  case n {
    0 -> <<>>
    _ -> <<b:little-size(8), repeat_byte(b, n - 1):bits>>
  }
}

/// Build one encoded transaction input from its field values.
pub fn build_input_bytes(
  outpoint_txid: BitArray,
  outpoint_vout: Int,
  script_sig: BitArray,
  sequence: Int,
) -> BitArray {
  let outpoint_vout_bytes = <<outpoint_vout:little-size(32)>>
  let script_length = compact_size(bit_array.byte_size(script_sig))
  let sequence_bytes = <<sequence:little-size(32)>>

  <<
    outpoint_txid:bits,
    outpoint_vout_bytes:bits,
    script_length:bits,
    script_sig:bits,
    sequence_bytes:bits,
  >>
}

/// Build one encoded transaction output from its field values.
pub fn build_output_bytes(
  value: BitArray,
  script_pubkey: BitArray,
) -> BitArray {
  let script_length = compact_size(bit_array.byte_size(script_pubkey))

  <<
    value:bits,
    script_length:bits,
    script_pubkey:bits,
  >>
}

/// Return an input section containing a count and one minimal encoded input.
pub fn build_minimal_input_section_bytes() -> BitArray {
  let input_count = compact_size(1)
  let input = build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)
  <<input_count:bits, input:bits>>
}

/// Return an output section containing a count and one minimal encoded output.
pub fn build_minimal_output_section_bytes() -> BitArray {
  let output_count = compact_size(1)
  let output = build_output_bytes(<<0:little-size(64)>>, <<>>)
  <<output_count:bits, output:bits>>
}

/// Build a minimal legacy transaction with the supplied version.
pub fn build_minimal_legacy_transaction_bytes(version: Int) -> BitArray {
  <<
    version:little-size(32),
    build_minimal_input_section_bytes():bits,
    build_minimal_output_section_bytes():bits,
    0:little-size(32),
  >>
}

/// Build a minimal SegWit transaction with one zero-length witness item.
pub fn build_minimal_segwit_transaction_bytes() -> BitArray {
  let witness_stack = <<compact_size(1):bits, compact_size(0):bits>>

  assemble_segwit_transaction_bytes(
    [build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)],
    [build_output_bytes(<<0:little-size(64)>>, <<>>)],
    [witness_stack],
  )
}

/// Assemble SegWit transaction bytes from encoded components without validating them.
pub fn assemble_segwit_transaction_bytes(
  inputs: List(BitArray),
  outputs: List(BitArray),
  witness_stacks: List(BitArray),
) -> BitArray {
  let input_count = compact_size(list.length(inputs))
  let output_count = compact_size(list.length(outputs))

  <<
    transaction_version_1_bytes:bits,
    0x00,
    0x01,
    input_count:bits,
    bit_array.concat(inputs):bits,
    output_count:bits,
    bit_array.concat(outputs):bits,
    bit_array.concat(witness_stacks):bits,
    0:little-size(32),
  >>
}
