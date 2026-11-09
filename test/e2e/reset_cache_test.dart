import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// Waits for [condition], polling, and fails if it does not hold within 5 s.
Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 500 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

void main() {
  late CacheTestHarness h;

  setUp(() async {
    h = CacheTestHarness();
    await h.setUp();
  });

  tearDown(() => h.tearDown());

  test('resetCache while the download waits for the origin resets the cache',
      () async {
    final source = h.origin.url('/reset-waiting.mp3');
    final half = h.origin.payload.length ~/ 2;

    // A partial cache of the first half, as an interrupted download leaves it.
    final firstGate = Completer<void>();
    h.origin
      ..responseBodyGate = firstGate
      ..responseBodyGateAfterBytes = half;
    final interrupted = h.manager.createStream(source);
    interrupted.download().ignore();
    await _until(() => interrupted.cachePosition >= half);
    await interrupted.dispose(force: true);
    h.origin
      ..responseBodyGate = null
      ..responseBodyGateAfterBytes = null;
    firstGate.complete();

    // The resumed download waits for the origin's response when the cache is
    // reset: no response is open for the reset to end.
    final startGate = Completer<void>();
    h.origin.responseStartGate = startGate;
    final requestsBefore = h.origin.requestCount;
    final stream = h.manager.createStream(source);
    stream.download().ignore();
    await _until(() => h.origin.requestCount == requestsBefore + 1);
    expect(h.origin.lastRangeHeader, 'bytes=$half-');

    final reset = stream.resetCache();
    startGate.complete();
    await reset.timeout(const Duration(seconds: 5));

    // The download starts over, from the start, not from the reset partial.
    await _until(() => h.origin.requestCount == requestsBefore + 2);
    expect(h.origin.lastRangeHeader, isNull);

    await stream.dispose(force: true);
  });
}
