import btc_parser/block.{InvalidByteCount, ZeroPowLimit}

pub fn new_pow_limit_accepts_nonzero_32_byte_value_test() {
  let assert Ok(_) = block.new_pow_limit(<<0x01, 0:248>>)
}

pub fn new_pow_limit_rejects_31_byte_value_test() {
  assert block.new_pow_limit(<<0:248>>)
    == Error(InvalidByteCount(actual: 31, expected: 32))
}

pub fn new_pow_limit_rejects_33_byte_value_test() {
  assert block.new_pow_limit(<<0:264>>)
    == Error(InvalidByteCount(actual: 33, expected: 32))
}

pub fn new_pow_limit_rejects_zero_32_byte_value_test() {
  assert block.new_pow_limit(<<0:256>>) == Error(ZeroPowLimit)
}
