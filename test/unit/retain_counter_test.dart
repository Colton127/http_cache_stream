import 'package:http_cache_stream/src/etc/counters/retain_counter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts retained with a count of 1', () {
    final c = RetainCounter();
    expect(c.count, 1);
    expect(c.isRetained, isTrue);
  });

  test('retain and release are symmetric', () {
    final c = RetainCounter();
    c.retain();
    c.retain();
    expect(c.count, 3);
    c.release();
    expect(c.count, 2);
    c.release();
    c.release();
    expect(c.count, 0);
    expect(c.isRetained, isFalse);
  });

  test('release does not go below zero', () {
    final c = RetainCounter();
    c.release(); // 0
    c.release(); // still 0
    expect(c.count, 0);
    expect(c.isRetained, isFalse);
  });

  test('force release drops straight to zero', () {
    final c = RetainCounter();
    c.retain();
    c.retain();
    expect(c.count, 3);
    c.release(force: true);
    expect(c.count, 0);
    expect(c.isRetained, isFalse);
  });
}
