pub const zero_bytes = <<0, 0, 0, 0, 0, 0, 0, 0>>

pub const one_bytes = <<1, 0, 0, 0, 0, 0, 0, 0>>

/// 2^32
pub const two_to_32 = 4_294_967_296

/// 2^32
pub const two_to_32_bytes = <<0, 0, 0, 0, 1, 0, 0, 0>>

/// 2^53 - 1
pub const max_safe_js_int = 9_007_199_254_740_991

/// 2^53 - 1
pub const max_safe_js_int_bytes = <<
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0x1F,
  0,
>>

/// 2^53
pub const max_safe_js_int_plus_one_bytes = <<
  0,
  0,
  0,
  0,
  0,
  0,
  0x20,
  0,
>>
