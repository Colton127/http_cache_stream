import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// A download whose writes to the cache file fail (a full disk, here a
/// directory where the file goes) gives up its attempt. The next one waits,
/// rather than requesting the source again at once, again and again.
void main() {
  late CacheTestHarness h;

  setUp(() async {
    h = CacheTestHarness();
    await h.setUp();
  });

  tearDown(() => h.tearDown());

  test(
      'an attempt whose cache writes fail is retried after a wait, not at once',
      () async {
    final stream = h.manager.createStream(h.origin.url('/a.mp3'));
    await Directory(stream.files.partial.path).create(recursive: true);
    final errors = <Object>[];
    final subscription =
        stream.cacheStateStream.listen(null, onError: errors.add);

    stream.download().ignore();
    await Future<void>.delayed(const Duration(seconds: 3));

    expect(errors, isNotEmpty, reason: 'the failed write is reported');
    expect(h.origin.requestCount, 1, reason: 'the next attempt waits 5 s');
    await subscription.cancel();
    await stream.dispose(force: true);
  });

  test('the attempt after the wait downloads once the cache can be written',
      () async {
    final stream = h.manager.createStream(h.origin.url('/a.mp3'));
    final blocker = Directory(stream.files.partial.path);
    await blocker.create(recursive: true);
    final failed = Completer<void>();
    final subscription = stream.cacheStateStream.listen(null, onError: (_) {
      if (!failed.isCompleted) failed.complete();
    });
    final download = stream.download();
    await failed.future.timeout(const Duration(seconds: 5));
    await blocker.delete();

    final file = await download.timeout(const Duration(seconds: 15));
    expect(await file.length(), h.origin.payload.length);
    expect(h.origin.requestCount, 2);
    await subscription.cancel();
    await stream.dispose(force: true);
  });
}
