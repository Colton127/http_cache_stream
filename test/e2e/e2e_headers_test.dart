import 'package:flutter_test/flutter_test.dart';
import 'package:http_cache_stream/src/etc/mime_types.dart';

import '../support/harness.dart';
import '../support/payload.dart';

void main() {
  late CacheTestHarness h;

  setUp(() async {
    h = CacheTestHarness();
    await h.setUp(payload: Payload.generate(256 * 1024));
  });

  tearDown(() => h.tearDown());

  // These assert the headers the cache server sets (RequestHandler._setHeaders),
  // which are identical whether the body is served from an in-flight download or
  // a completed file. They fetch lazily (no pre-download) so the body streams
  // back as it is fetched.

  test('a full response carries content-type, length and accept-ranges',
      () async {
    final cacheUrl = h.manager.getCacheUrl(h.origin.url('/media/clip.mp3'));
    final res = await h.fetch(cacheUrl);
    expect(res.statusCode, 200);
    expect(res.header('content-type'), 'audio/mpeg');
    expect(int.parse(res.header('content-length')!), h.origin.payload.length);
    expect(res.header('accept-ranges'), 'bytes');
  });

  test('a range response carries content-range and the correct length',
      () async {
    final total = h.origin.payload.length;
    final cacheUrl = h.manager.getCacheUrl(h.origin.url('/media/clip.mp3'));
    final res = await h.fetch(cacheUrl, range: 'bytes=10-109');
    expect(res.statusCode, 206);
    expect(res.header('content-range'), 'bytes 10-109/$total');
    expect(int.parse(res.header('content-length')!), 100);
  });

  test('an out-of-range request returns 416', () async {
    // Pre-cache so the source length is known and the range can be rejected.
    final source = h.origin.url('/media/clip.mp3');
    final stream = h.manager.createStream(source);
    await stream.download();
    final total = h.origin.payload.length;

    final res = await h.fetch(h.manager.getCacheUrl(source),
        range: 'bytes=${total + 10}-${total + 20}');
    expect(res.statusCode, 416);

    await stream.dispose();
  });

  test('HEAD returns headers with an empty body', () async {
    final cacheUrl = h.manager.getCacheUrl(h.origin.url('/media/clip.mp3'));
    final res = await h.fetch(cacheUrl, method: 'HEAD');
    expect(res.body, isEmpty);
    expect(int.parse(res.header('content-length')!), h.origin.payload.length);
  });

  test('content-type falls back to the path when the origin omits it',
      () async {
    h.origin.contentType = null;
    final cacheUrl = h.manager.getCacheUrl(h.origin.url('/media/clip.mp3'));
    final res = await h.fetch(cacheUrl);
    expect(res.header('content-type'), MimeTypes.fromPath('clip.mp3'));
    expect(res.header('content-type'), isNot(MimeTypes.octetStream));
  });
}
