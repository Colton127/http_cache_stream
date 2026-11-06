import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http_cache_stream/http_cache_stream.dart';

import '../support/payload.dart';
import '../support/test_origin.dart';

/// `HttpCacheManager.init(startServer: false)` binds no socket (a sandbox
/// without the incoming-network entitlement refuses one): streams still
/// download and cache, read through `createStream` and `request`, and there is
/// no cache URL.
void main() {
  late Directory cacheDir;
  late TestOrigin origin;
  final payload = Payload.generate(256 * 1024);

  setUp(() async {
    cacheDir = await Directory.systemTemp.createTemp('hcs_serverless_');
    origin = await TestOrigin.start(payload);
  });

  tearDown(() async {
    if (HttpCacheManager.isInitialized) {
      await HttpCacheManager.instance.dispose();
    }
    await origin.close();
    if (cacheDir.existsSync()) await cacheDir.delete(recursive: true);
  });

  Future<List<int>> readAll(StreamResponse response) async {
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
    }
    return bytes;
  }

  test('init without a server binds no socket', () async {
    // Hold a port, then ask the manager for it: with a server, init would fail
    // to bind; without one, the port is never touched.
    final held = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(held.close);

    final manager = await HttpCacheManager.init(
      cacheDir: cacheDir,
      port: held.port,
      startServer: false,
    );
    expect(manager.hasServer, isFalse);
    expect(HttpCacheManager.instanceOrNull, same(manager));
  });

  test(
    'a stream downloads, caches and serves from cache without a server',
    () async {
      final manager = await HttpCacheManager.init(
        cacheDir: cacheDir,
        startServer: false,
      );
      final source = origin.url('/audio.mp3');
      final stream = manager.createStream(source);

      // First read streams from the origin while caching.
      final first = await stream.request();
      expect(await readAll(first), payload);

      final file = await stream.download();
      expect(await file.readAsBytes(), payload);
      final originRequests = origin.requestCount;

      // A ranged read is now served from the cache file, not the origin.
      final ranged = await stream.request(start: 100, end: 200);
      expect(ranged.source, ResponseSource.cacheFile);
      expect(await readAll(ranged), payload.sublist(100, 200));
      expect(origin.requestCount, originRequests);

      expect(manager.getExistingStream(source), same(stream));
      await stream.dispose(force: true);

      // A fresh stream for the same URL picks up the completed cache.
      final again = manager.createStream(source);
      final cached = await again.request();
      expect(cached.source, ResponseSource.cacheFile);
      expect(await readAll(cached), payload);
      expect(origin.requestCount, originRequests);
      await again.dispose(force: true);
    },
  );

  test('preCacheUrl works without a server', () async {
    final manager = await HttpCacheManager.init(
      cacheDir: cacheDir,
      startServer: false,
    );
    final file = await manager.preCacheUrl(origin.url('/pre.mp3'));
    expect(await file.readAsBytes(), payload);
  });

  test(
    'cache URLs throw CacheServerUnavailableException without a server',
    () async {
      final manager = await HttpCacheManager.init(
        cacheDir: cacheDir,
        startServer: false,
      );
      final source = origin.url('/audio.mp3');

      expect(
        () => manager.getCacheUrl(source),
        throwsA(
          isA<CacheServerUnavailableException>().having(
            (e) => e.sourceUrl,
            'sourceUrl',
            source,
          ),
        ),
      );

      final stream = manager.createStream(source);
      expect(stream.hasCacheUrl, isFalse);
      expect(
        () => stream.cacheUrl,
        throwsA(isA<CacheServerUnavailableException>()),
      );
      // A StateError, so existing `on StateError` handlers still catch it.
      expect(() => stream.cacheUrl, throwsStateError);
      expect(stream.toString(), contains('cacheUrl: null'));
      await stream.dispose(force: true);
    },
  );

  test('ensureActive does nothing without a server', () async {
    final held = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(held.close);
    final manager = await HttpCacheManager.init(
      cacheDir: cacheDir,
      port: held.port,
      startServer: false,
    );

    // Completes without trying to start or rebind a server on the held port.
    await manager.ensureActive();
    await manager.ensureActive();
    expect(manager.hasServer, isFalse);

    // Streams still work afterwards.
    final file = await manager.preCacheUrl(origin.url('/after.mp3'));
    expect(await file.readAsBytes(), payload);
  });

  test('dispose works without a server', () async {
    final manager = await HttpCacheManager.init(
      cacheDir: cacheDir,
      startServer: false,
    );
    final stream = manager.createStream(origin.url('/audio.mp3'));
    await stream.download();

    await manager.dispose();
    expect(manager.isDisposed, isTrue);
    expect(HttpCacheManager.isInitialized, isFalse);
    await stream.future.timeout(const Duration(seconds: 5));
    expect(stream.isDisposed, isTrue);
    expect(
      () => manager.ensureActive(),
      throwsA(isA<CacheManagerDisposedException>()),
    );

    // A disposed serverless manager can be replaced by one with a server.
    final next = await HttpCacheManager.init(cacheDir: cacheDir);
    expect(next.hasServer, isTrue);
  });

  test('init after dispose returns a new manager', () async {
    // Serverless init with a cacheDir completes without an await; the pending
    // init future must still be cleared so the next init does not hand back
    // the disposed manager.
    final first = await HttpCacheManager.init(
      cacheDir: cacheDir,
      startServer: false,
    );
    await first.dispose();
    final second = await HttpCacheManager.init(
      config: GlobalCacheConfig(cacheDirectory: cacheDir),
      startServer: false,
    );
    expect(second, isNot(same(first)));
    expect(second.isDisposed, isFalse);
    expect(HttpCacheManager.instance, same(second));
  });

  test('concurrent inits share one manager', () async {
    final results = await Future.wait([
      HttpCacheManager.init(cacheDir: cacheDir, startServer: false),
      HttpCacheManager.init(cacheDir: cacheDir, startServer: false),
    ]);
    expect(results[0], same(results[1]));
  });

  test('the default init still starts the server', () async {
    final manager = await HttpCacheManager.init(cacheDir: cacheDir);
    expect(manager.hasServer, isTrue);
    final source = origin.url('/audio.mp3');
    final stream = manager.createStream(source);
    expect(stream.hasCacheUrl, isTrue);
    expect(stream.cacheUrl, manager.getCacheUrl(source));
    expect(stream.cacheUrl.host, InternetAddress.loopbackIPv4.address);
    await manager.ensureActive();
  });
}
