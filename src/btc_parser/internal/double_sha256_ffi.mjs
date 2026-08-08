import { BitArray } from '../../gleam.mjs';
import * as crypto from 'node:crypto';

const sha256 = typeof crypto.hash === 'function'
  ? (bytes) => crypto.hash('sha256', bytes, 'buffer')
  : (bytes) => crypto.createHash('sha256').update(bytes).digest();

export function hash(bytes) {
  const digest = sha256(sha256(bytes.rawBuffer));
  return new BitArray(new Uint8Array(digest));
}
