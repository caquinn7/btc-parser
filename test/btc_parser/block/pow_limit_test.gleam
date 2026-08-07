import btc_parser/block.{InvalidBitCount, ZeroPowLimit}

pub fn new_pow_limit_accepts_nonzero_32_byte_value_test() {
  let assert Ok(_) = block.new_pow_limit(<<0x01, 0:248>>)
}

pub fn new_pow_limit_reports_incorrect_bit_counts_test() {
  assert block.new_pow_limit(<<0:248>>)
    == Error(InvalidBitCount(actual: 248, expected: 256))

  assert block.new_pow_limit(<<0:255>>)
    == Error(InvalidBitCount(actual: 255, expected: 256))

  assert block.new_pow_limit(<<0:257>>)
    == Error(InvalidBitCount(actual: 257, expected: 256))

  assert block.new_pow_limit(<<0:264>>)
    == Error(InvalidBitCount(actual: 264, expected: 256))
}

pub fn new_pow_limit_rejects_zero_32_byte_value_test() {
  assert block.new_pow_limit(<<0:256>>) == Error(ZeroPowLimit)
}
