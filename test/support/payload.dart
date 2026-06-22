import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Deterministic test payload generation + hashing helpers.
///
/// Tests assert that the bytes served/cached by the package are byte-for-byte
/// identical to what the origin produced. To make that assertion meaningful and
/// reproducible, payloads are generated from a seeded PRNG and compared by
/// SHA-256, never by re-reading the source of truth from the same code path.
class Payload {
  /// Generates [length] deterministic bytes from [seed].
  ///
  /// Uses a simple xorshift-style PRNG so the output is stable across platforms
  /// and Dart versions (unlike `dart:math` Random, which is not guaranteed to be
  /// reproducible across SDK versions).
  static Uint8List generate(int length, {int seed = 0x9E3779B1}) {
    final bytes = Uint8List(length);
    var x = (seed == 0 ? 0x1234567 : seed) & 0xFFFFFFFF;
    for (var i = 0; i < length; i++) {
      // xorshift32
      x ^= (x << 13) & 0xFFFFFFFF;
      x ^= x >> 17;
      x ^= (x << 5) & 0xFFFFFFFF;
      bytes[i] = x & 0xFF;
    }
    return bytes;
  }

  /// SHA-256 of [bytes], as a lowercase hex string.
  static String hash(List<int> bytes) => sha256.convert(bytes).toString();
}
