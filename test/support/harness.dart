import 'dart:io';
import 'dart:typed_data';

import 'package:http_cache_stream/http_cache_stream.dart';

import 'payload.dart';
import 'test_origin.dart';

/// The result of fetching a URL through the local cache server.
class FetchResult {
  FetchResult(this.statusCode, this.body, this.headers);
  final int statusCode;
  final Uint8List body;
  final HttpHeaders headers;

  String? header(String name) => headers.value(name);
}

/// Shared setup/teardown for end-to-end cache tests.
///
/// Creates a fresh temp cache directory and a [TestOrigin] per test, and inits
/// the [HttpCacheManager] singleton against them. Because the manager is a
/// process-wide singleton with no dedicated reset hook, [tearDown] disposes it
/// (which nulls the static instance) so the next test starts clean.
class CacheTestHarness {
  late final Directory cacheDir;
  late final TestOrigin origin;
  late final HttpCacheManager manager;

  final _client = HttpClient();

  Future<void> setUp({
    Uint8List? payload,
    GlobalCacheConfig Function(Directory cacheDir)? configBuilder,
  }) async {
    cacheDir = await Directory.systemTemp.createTemp('hcs_test_');
    origin = await TestOrigin.start(payload ?? Payload.generate(256 * 1024));
    if (configBuilder != null) {
      manager = await HttpCacheManager.init(config: configBuilder(cacheDir));
    } else {
      manager = await HttpCacheManager.init(cacheDir: cacheDir);
    }
  }

  Future<void> tearDown() async {
    _client.close(force: true);
    if (HttpCacheManager.isInitialized) {
      await HttpCacheManager.instance.dispose();
    }
    await origin.close();
    if (cacheDir.existsSync()) {
      await cacheDir.delete(recursive: true);
    }
  }

  /// Fetches [url] (typically a `cacheUrl`) through the local cache server and
  /// buffers the full response.
  Future<FetchResult> fetch(
    Uri url, {
    String method = 'GET',
    String? range,
  }) async {
    final request = await _client.openUrl(method, url);
    if (range != null) {
      request.headers.set(HttpHeaders.rangeHeader, range);
    }
    final response = await request.close();
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return FetchResult(
        response.statusCode, builder.takeBytes(), response.headers);
  }

  /// Convenience: the expected SHA-256 of the full origin payload.
  String get payloadHash => Payload.hash(origin.payload);
}
