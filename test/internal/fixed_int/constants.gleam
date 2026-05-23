/// 2^53 - 1
pub const max_safe_js_int = 9_007_199_254_740_991

/// 2^53 - 1
pub const min_safe_js_int = -9_007_199_254_740_991

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

/// -(2^53 - 1)
pub const min_safe_js_int_bytes = <<
  0x01,
  0,
  0,
  0,
  0,
  0,
  0xE0,
  0xFF,
>>
