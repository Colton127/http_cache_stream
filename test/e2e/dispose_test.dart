import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  late CacheTestHarness h;

  // Uses the default lifecycle config (disposeAfter = 5 min). A regression in the
  // dispose()/release() race would block until the test framework timeout rather
  // than completing in milliseconds.
  setUp(() async {
    h = CacheTestHarness();
    await h.setUp();
  });

  tearDown(() => h.tearDown());

  test('dispose() completes promptly when a holder releases afterward',
      () async {
    final stream = h.manager.createStream(h.origin.url('/a.mp3')); // count 1
    stream.retain(); // simulate an in-flight request holding it: count 2

    final disposing = stream.dispose(); // count 1: still retained, completes later
    expect(stream.isDisposed, isFalse);

    stream.release(); // count 0: must honor the pending dispose now

    await disposing.timeout(const Duration(seconds: 5));
    expect(stream.isDisposed, isTrue);
  });

  test('a retain after dispose resurrects the stream', () async {
    final stream = h.manager.createStream(h.origin.url('/b.mp3')); // count 1
    stream.retain(); // count 2

    stream.dispose(); // count 1: pending dispose
    stream.retain(); // count 2: a new holder clears the pending dispose

    stream.release(); // count 1
    stream.release(); // count 0: lifecycle, not disposed
    expect(stream.isDisposed, isFalse);

    await stream.dispose(force: true);
    expect(stream.isDisposed, isTrue);
  });
}
