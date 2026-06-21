import 'package:flutter_test/flutter_test.dart';
import 'package:http_cache_stream/http_cache_stream.dart';

import '../support/harness.dart';
import '../support/payload.dart';

// pauseAfter == disposeAfter takes the immediate-dispose branch in release(),
// so teardown is fast and independent of readTimeout.
const _fastLifecycle = StreamLifecycleConfig(
  pauseAfter: Duration(milliseconds: 150),
  disposeAfter: Duration(milliseconds: 150),
);

void main() {
  late CacheTestHarness h;

  setUp(() async {
    h = CacheTestHarness();
    await h.setUp(
      payload: Payload.generate(128 * 1024),
      configBuilder: (cacheDir) => GlobalCacheConfig(
        cacheDirectory: cacheDir,
        lifecycleConfig: _fastLifecycle,
      ),
    );
  });

  tearDown(() => h.tearDown());

  test('getCacheUrl lazily creates a stream that auto-disposes when idle',
      () async {
    final source = h.origin.url('/a.mp3');
    final cacheUrl = h.manager.getCacheUrl(source);

    // No stream exists until the first request reaches the server.
    expect(h.manager.getExistingStream(source), isNull);

    await h.fetch(cacheUrl);
    expect(h.manager.getExistingStream(source), isNotNull);

    // After release + the (tiny) lifecycle window, the stream is disposed and
    // removed from the manager.
    await Future.delayed(const Duration(milliseconds: 500));
    expect(h.manager.getExistingStream(source), isNull);
  });

  test('retaining again before disposal keeps the stream alive', () async {
    final source = h.origin.url('/b.mp3');
    final cacheUrl = h.manager.getCacheUrl(source);

    await h.fetch(cacheUrl);
    // Re-acquire (retain) before the lifecycle timer fires; this cancels it.
    final stream = h.manager.createStream(source);
    expect(stream.isDisposed, isFalse);

    await Future.delayed(const Duration(milliseconds: 400));
    expect(stream.isDisposed, isFalse,
        reason: 'a retained stream must survive past disposeAfter');

    await stream.dispose();
  });

  test('dispose(force: true) tears the stream down immediately', () async {
    final source = h.origin.url('/c.mp3');
    final stream = h.manager.createStream(source);

    await stream.dispose(force: true);
    expect(stream.isDisposed, isTrue);
    expect(h.manager.getExistingStream(source), isNull);
  });

  test('preCacheUrl downloads the file then disposes the stream', () async {
    final source = h.origin.url('/d.mp3');
    final file = await h.manager.preCacheUrl(source);

    expect(file.existsSync(), isTrue);
    expect(Payload.hash(await file.readAsBytes()), h.payloadHash);
    expect(h.manager.getExistingStream(source), isNull,
        reason: 'preCacheUrl disposes its stream when done');
  });

  test('getCacheUrl is stable for the same source', () {
    final source = h.origin.url('/e.mp3');
    expect(h.manager.getCacheUrl(source), h.manager.getCacheUrl(source));
  });

  test('deleteCache removes cached files once no streams are active', () async {
    final source = h.origin.url('/f.mp3');
    final files = h.manager.getCacheFiles(source);

    final stream = h.manager.createStream(source);
    await stream.download();
    await stream.dispose();
    expect(files.complete.existsSync(), isTrue);

    await h.manager.deleteCache();
    expect(files.complete.existsSync(), isFalse);
  });
}
