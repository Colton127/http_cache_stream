import 'package:http_cache_stream/src/cache_server/local_cache_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LocalCacheServer server;

  setUp(() async {
    server = await LocalCacheServer.init(port: 0);
  });

  tearDown(() async {
    await server.close(force: true);
  });

  void expectRoundTrip(Uri source) {
    final encoded = server.encodeSourceUrl(source);
    expect(server.validateCacheUrl(encoded), isTrue,
        reason: 'encoded URL should validate: $encoded');
    final decoded = server.decodeSourceUrl(encoded);
    expect(decoded.toString(), source.toString());
  }

  group('encode/decode round-trip', () {
    test('https with default port', () {
      expectRoundTrip(Uri.parse('https://example.com/media/file.mp3'));
    });

    test('http with a non-default port preserves the port', () {
      final source = Uri.parse('http://example.com:8080/a/b/c.ts');
      final encoded = server.encodeSourceUrl(source);
      // The non-default port is carried in the host path segment.
      expect(encoded.pathSegments[1], 'example.com:8080');
      expectRoundTrip(source);
    });

    test('query string is preserved', () {
      expectRoundTrip(Uri.parse('https://cdn.example.com/v.m3u8?token=abc&x=1'));
    });

    test('multi-segment path is preserved', () {
      expectRoundTrip(Uri.parse('https://h.example.com/a/b/c/d/e.mp4'));
    });
  });

  group('validation', () {
    test('re-encoding an already-encoded URL is a no-op', () {
      final source = Uri.parse('https://example.com/file.mp3');
      final encoded = server.encodeSourceUrl(source);
      expect(server.encodeSourceUrl(encoded), encoded);
    });

    test('a foreign URL does not validate as a cache URL', () {
      expect(
        server.validateCacheUrl(Uri.parse('http://127.0.0.1:9/not/a/cache/url')),
        isFalse,
      );
    });

    test('decoding a non-cache URI returns null', () {
      // Too few path segments to encode a source scheme + host.
      expect(server.decodeSourceUrl(server.serverUri.replace(path: '/x')),
          isNull);
    });
  });
}
