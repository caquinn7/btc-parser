import { Result$Ok, Result$Error, BitArray } from '../../gleam.mjs';

export function uint64LeToInt(bytes_le) {
  /*
  BitArray {
    bitSize: 64,
    byteSize: 8,
    bitOffset: 0,
    rawBuffer: Uint8Array(8) [
      255, 255, 255, 255,
      255, 255,  31,   0
    ]
  }
  */

  if (!bytes_le || bytes_le.byteSize !== 8) {
    return Result$Error(undefined);
  }

  const u8 = bytes_le.rawBuffer;
  if (!(u8 instanceof Uint8Array) || u8.length < 8) {
    return Result$Error(undefined);
  }

  const x = toBigInt(u8);

  if (x <= BigInt(Number.MAX_SAFE_INTEGER)) {
    return Result$Ok(Number(x));
  }

  return Result$Error(undefined);
}

export function uint64LeToString(bytes_le) {
  if (!bytes_le || bytes_le.byteSize !== 8) {
    throw new Error('Expected 8-byte BitArray');
  }

  const u8 = bytes_le.rawBuffer;
  if (!(u8 instanceof Uint8Array) || u8.length < 8) {
    throw new Error('Invalid BitArray buffer');
  }

  const x = toBigInt(u8);
  return x.toString(10);
}

export function int64LeToInt(bytes_le) {
  if (!bytes_le || bytes_le.byteSize !== 8) {
    return Result$Error(undefined);
  }

  const u8 = bytes_le.rawBuffer;
  if (!(u8 instanceof Uint8Array) || u8.length < 8) {
    return Result$Error(undefined);
  }

  const x = toBigIntSigned(u8);

  if (x >= BigInt(Number.MIN_SAFE_INTEGER) && x <= BigInt(Number.MAX_SAFE_INTEGER)) {
    return Result$Ok(Number(x));
  }

  return Result$Error(undefined);
}

export function int64LeToString(bytes_le) {
  if (!bytes_le || bytes_le.byteSize !== 8) {
    throw new Error('Expected 8-byte BitArray');
  }

  const u8 = bytes_le.rawBuffer;
  if (!(u8 instanceof Uint8Array) || u8.length < 8) {
    throw new Error('Invalid BitArray buffer');
  }

  const x = toBigIntSigned(u8);
  return x.toString(10);
}

function toBigInt(u8) {
  let x = 0n;
  for (let i = 0; i < 8; i++) {
    x |= BigInt(u8[i]) << (8n * BigInt(i));
  }
  return x;
}

function toBigIntSigned(u8) {
  let x = toBigInt(u8);
  // Check if the sign bit (bit 63) is set
  if (x >= 0x8000000000000000n) {
    // Two's complement: subtract 2^64
    x -= 0x10000000000000000n;
  }
  return x;
}

export function uint64FromInt(i) {
  if (typeof i !== 'number' || !Number.isInteger(i)) {
    throw new Error("Expected an integer");
  }

  // Non-negative unsafe integers may already be rounded by the time they reach
  // this function, so Gleam maps this generic failure to UnsafeInteger.
  if (i < 0 || i > Number.MAX_SAFE_INTEGER) {
    return Result$Error(undefined);
  }

  const x = BigInt(i);

  const u8 = new Uint8Array(8);
  for (let k = 0; k < 8; k++) {
    u8[k] = Number((x >> (8n * BigInt(k))) & 0xffn);
  }

  return Result$Ok(new BitArray(u8));
}

export function runningOnJavaScript() {
  return true;
}

export function int64FromInt(i) {
  // On JavaScript, validate that the value is within the safe integer range.
  // Even though all valid Int values from parsing fit in 64 bits, user code
  // or computations can produce values outside the safe range (±2^53 - 1),
  // which will have already lost precision. We must reject these to prevent
  // silent data corruption.

  if (typeof i !== 'number' || !Number.isInteger(i)) {
    throw new Error("Expected an integer");
  }

  // Check safe integer range to prevent precision loss
  if (i < Number.MIN_SAFE_INTEGER || i > Number.MAX_SAFE_INTEGER) {
    return Result$Error(undefined);
  }

  // Convert to BigInt for proper two's complement encoding
  const x = BigInt(i);

  // Encode to 8 bytes little-endian, two's complement
  let u = x;
  if (u < 0n) {
    u = (1n << 64n) + u;  // Two's complement for negative values
  }

  const u8 = new Uint8Array(8);
  for (let k = 0; k < 8; k++) {
    u8[k] = Number((u >> (8n * BigInt(k))) & 0xffn);
  }

  return Result$Ok(new BitArray(u8));
}
