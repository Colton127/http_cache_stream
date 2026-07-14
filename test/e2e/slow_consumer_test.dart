import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http_cache_stream/http_cache_stream.dart';

import '../support/harness.dart';
import '../support/payload.dart';

/// Regression tests for partial cache responses with slow or paused consumers.
///
/// The previous implementation buffered live download data in memory per
/// response and killed the response once the buffer reached [maxBufferSize].
/// A consumer that paused (e.g. a video player with a full playback buffer) or
/// simply read slower than the download would hit that limit and the HTTP
/// response terminated mid-body. Responses are now served by following the
/// partial cache file on disk, so a consumer may fall arbitrarily far behind.
void main() {
  late CacheTestHarness h;
  // 4MB payload with the smallest allowed maxBufferSize (1MB): the download
  // finishes (and runs ~4MB ahead of the paused consumer) almost immediately,
  // which the old in-memory buffering could not survive.
  final payload = Payload.generate(4 * 1024 * 1024);

  setUp(() async {
    h = CacheTestHarness();
    await h.setUp(
      payload: payload,
      configBuilder: (cacheDir) => GlobalCacheConfig(
        cacheDirectory: cacheDir,
        maxBufferSize: 1024 * 1024,
      ),
    );
  });

  tearDown(() => h.tearDown());

  /// Fetches [url] while deliberately reading slower than the download, by
  /// pausing the socket subscription after every received chunk.
  Future<Uint8List> slowFetch(Uri url,
      {Duration pausePerChunk = const Duration(milliseconds: 5),
      Duration? midStreamStall}) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      request.persistentConnection = false;
      final response = await request.close();
      expect(response.statusCode, 200);

      final received = BytesBuilder(copy: false);
      final done = Completer<void>();
      var stalled = false;
      late StreamSubscription<List<int>> sub;
      sub = response.listen(
        (data) {
          received.add(data);
          sub.pause();
          var delay = pausePerChunk;
          // Once mid-body, simulate a player whose playback buffer is full
          // and stops consuming entirely for a while.
          if (!stalled &&
              midStreamStall != null &&
              received.length > payload.length ~/ 4) {
            stalled = true;
            delay = midStreamStall;
          }
          Future<void>.delayed(delay, sub.resume);
        },
        onError: done.completeError,
        onDone: done.complete,
      );

      await done.future.timeout(const Duration(seconds: 60));
      return received.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  test('a consumer reading slower than the download receives the full body',
      () async {
    final cacheUrl = h.manager.getCacheUrl(h.origin.url('/media/file.mp3'));
    final body = await slowFetch(cacheUrl);

    expect(body.length, payload.length);
    expect(Payload.hash(body), h.payloadHash);
  });

  test('a mid-stream pause longer than the download does not kill the response',
      () async {
    final cacheUrl = h.manager.getCacheUrl(h.origin.url('/media/file.mp3'));
    final body = await slowFetch(
      cacheUrl,
      pausePerChunk: Duration.zero,
      midStreamStall: const Duration(seconds: 2),
    );

    expect(body.length, payload.length);
    expect(Payload.hash(body), h.payloadHash);
  });

  test(
      'a range request opened mid-download and consumed slowly stays intact',
      () async {
    final source = h.origin.url('/media/file.mp3');
    final stream = h.manager.createStream(source);
    stream.download().ignore(); // Kick off the cache download.

    // Request a range while the download is (most likely) still in flight.
    const start = 1024;
    final end = payload.length - 1;
    final res = await h.fetch(h.manager.getCacheUrl(source),
        range: 'bytes=$start-$end');
    expect(res.statusCode, 206);
    expect(res.body.length, end - start + 1);
    expect(Payload.hash(res.body),
        Payload.hash(Uint8List.sublistView(payload, start, end + 1)));

    await stream.dispose();
  });
}
