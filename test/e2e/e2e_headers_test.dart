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

  test('a full response carries content-type, length and accept-ranges',
      () async {
    final source = h.origin.url('/media/clip.mp3');
    final stream = h.manager.createStream(source);
    await stream.download();

    final res = await h.fetch(h.manager.getCacheUrl(source));
    expect(res.statusCode, 200);
    expect(res.header('content-type'), 'audio/mpeg');
    expect(int.parse(res.header('content-length')!), h.origin.payload.length);
    expect(res.header('accept-ranges'), 'bytes');

    await stream.dispose();
  });

  test('a range response carries content-range and the correct length',
      () async {
    final source = h.origin.url('/media/clip.mp3');
    final stream = h.manager.createStream(source);
    await stream.download();
    final total = h.origin.payload.length;

    final res =
        await h.fetch(h.manager.getCacheUrl(source), range: 'bytes=10-109');
    expect(res.statusCode, 206);
    expect(res.header('content-range'), 'bytes 10-109/$total');
    expect(int.parse(res.header('content-length')!), 100);

    await stream.dispose();
  });

  test('an out-of-range request returns 416', () async {
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
    final source = h.origin.url('/media/clip.mp3');
    final stream = h.manager.createStream(source);
    await stream.download();

    final res = await h.fetch(h.manager.getCacheUrl(source), method: 'HEAD');
    expect(res.body, isEmpty);
    expect(int.parse(res.header('content-length')!), h.origin.payload.length);

    await stream.dispose();
  });

  test('content-type falls back to the path when the origin omits it',
      () async {
    h.origin.contentType = null;
    final source = h.origin.url('/media/clip.mp3');
    final stream = h.manager.createStream(source);
    await stream.download();

    final res = await h.fetch(h.manager.getCacheUrl(source));
    expect(res.header('content-type'), MimeTypes.fromPath('clip.mp3'));
    expect(res.header('content-type'), isNot(MimeTypes.octetStream));

    await stream.dispose();
  });
}
