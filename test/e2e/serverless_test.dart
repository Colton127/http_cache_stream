import 'dart:io';

import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/payload.dart';
import '../support/test_origin.dart';

/// `HttpCacheManager.init(startServer: false)` binds no socket (a sandbox
/// without the incoming-network entitlement refuses one): streams still
/// download and cache, read through `createStream`, and there is no cache URL.
void main() {
  late Directory cacheDir;
  late TestOrigin origin;
  final payload = Payload.generate(256 * 1024);

  setUp(() async {
    cacheDir = await Directory.systemTemp.createTemp('hcs_serverless_');
    origin = await TestOrigin.start(payload);
  });

  tearDown(() async {
    if (HttpCacheManager.isInitialized) await HttpCacheManager.instance.dispose();
    await origin.close();
    if (cacheDir.existsSync()) await cacheDir.delete(recursive: true);
  });

  test('a stream downloads and caches without a server, and there is no cache URL', () async {
    final manager = await HttpCacheManager.init(cacheDir: cacheDir, startServer: false);
    final source = origin.url('/audio.mp3');
    final stream = manager.createStream(source);
    expect(stream.cacheUrl, source, reason: 'no server to encode it');

    final file = await stream.download();
    expect(await file.readAsBytes(), payload);
    expect(() => manager.getCacheUrl(source), throwsStateError);
    await manager.ensureActive();
    stream.dispose().ignore();
  });
}
