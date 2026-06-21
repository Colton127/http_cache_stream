import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';
import '../support/payload.dart';

void main() {
  late CacheTestHarness h;

  setUp(() async {
    h = CacheTestHarness();
    await h.setUp(payload: Payload.generate(512 * 1024));
  });

  tearDown(() => h.tearDown());

  test('full download produces a byte-identical cache file', () async {
    final source = h.origin.url('/media/file.mp3');
    final stream = h.manager.createStream(source);
    final file = await stream.download();

    final bytes = await file.readAsBytes();
    expect(bytes.length, h.origin.payload.length);
    expect(Payload.hash(bytes), h.payloadHash);

    await stream.dispose();
  });

  test('streamed read through the cache server matches the origin', () async {
    final source = h.origin.url('/media/file.mp3');
    final cacheUrl = h.manager.getCacheUrl(source);

    final res = await h.fetch(cacheUrl);
    expect(res.statusCode, 200);
    expect(Payload.hash(res.body), h.payloadHash);
    expect(res.header('accept-ranges'), 'bytes');
    expect(int.parse(res.header('content-length')!), h.origin.payload.length);
  });

  test('range request returns exactly the requested bytes', () async {
    final source = h.origin.url('/media/file.mp3');
    final cacheUrl = h.manager.getCacheUrl(source);

    final res = await h.fetch(cacheUrl, range: 'bytes=100-199');
    expect(res.statusCode, 206);
    expect(res.body.length, 100);
    expect(res.header('content-range'),
        'bytes 100-199/${h.origin.payload.length}');

    final expected = Uint8List.sublistView(h.origin.payload, 100, 200);
    expect(Payload.hash(res.body), Payload.hash(expected));
  });

  test('open-ended range streams to the end of the file', () async {
    final source = h.origin.url('/media/file.mp3');
    final cacheUrl = h.manager.getCacheUrl(source);
    final total = h.origin.payload.length;

    final res = await h.fetch(cacheUrl, range: 'bytes=${total - 50}-');
    expect(res.statusCode, 206);
    expect(res.body.length, 50);

    final expected = Uint8List.sublistView(h.origin.payload, total - 50, total);
    expect(Payload.hash(res.body), Payload.hash(expected));
  });

  test('concurrent overlapping requests all return correct bytes', () async {
    final source = h.origin.url('/media/file.mp3');
    final cacheUrl = h.manager.getCacheUrl(source);
    final total = h.origin.payload.length;

    final results = await Future.wait([
      h.fetch(cacheUrl),
      h.fetch(cacheUrl, range: 'bytes=0-1023'),
      h.fetch(cacheUrl, range: 'bytes=${total ~/ 2}-'),
    ]);

    expect(Payload.hash(results[0].body), h.payloadHash);

    expect(results[1].body.length, 1024);
    expect(Payload.hash(results[1].body),
        Payload.hash(Uint8List.sublistView(h.origin.payload, 0, 1024)));

    expect(
        Payload.hash(results[2].body),
        Payload.hash(
            Uint8List.sublistView(h.origin.payload, total ~/ 2, total)));
  });

  test('resumes from an existing partial cache instead of re-downloading',
      () async {
    final source = h.origin.url('/media/file.mp3');
    final total = h.origin.payload.length;
    const k = 100 * 1024;

    // Pre-seed a valid partial cache + metadata so the next download must
    // resume from byte k rather than start over.
    final files = h.manager.getCacheFiles(source);
    await files.partial.parent.create(recursive: true);
    await files.partial
        .writeAsBytes(Uint8List.sublistView(h.origin.payload, 0, k));
    await files.metadata.writeAsString(jsonEncode({
      'Url': source.toString(),
      'headers': {
        'content-length': '$total',
        'accept-ranges': 'bytes',
        'etag': h.origin.etag,
      },
    }));

    final stream = h.manager.createStream(source);
    final file = await stream.download();

    expect(Payload.hash(await file.readAsBytes()), h.payloadHash);
    expect(h.origin.rangeHeaders.contains('bytes=$k-'), isTrue,
        reason: 'download should resume from the partial cache offset');
    expect(h.origin.rangeHeaders.contains('bytes=0-'), isFalse,
        reason: 'a full re-download should not occur');

    await stream.dispose();
  });

  test('a completed cache is reused without re-hitting the origin', () async {
    final source = h.origin.url('/media/file.mp3');
    final stream = h.manager.createStream(source);

    final file1 = await stream.download();
    expect(Payload.hash(await file1.readAsBytes()), h.payloadHash);
    final originRequestsAfterDownload = h.origin.requestCount;

    // Accessing the completed cache again must serve from disk, byte-identical,
    // without contacting the origin.
    final file2 = await stream.download();
    expect(Payload.hash(await file2.readAsBytes()), h.payloadHash);
    expect(h.origin.requestCount, originRequestsAfterDownload,
        reason: 'a completed cache must not re-contact the origin');

    await stream.dispose();
  });
}
