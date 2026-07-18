import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:http_cache_stream/src/cache_stream/cache_downloader/partial_cache_feed.dart';
import 'package:http_cache_stream/src/cache_stream/response_streams/partial_cache_file_stream.dart';
import 'package:http_cache_stream/src/models/stream_response/stream_response_range.dart';

import '../support/payload.dart';

void main() {
  late Directory dir;
  late CacheFiles files;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hcs_tail_');
    files = CacheFiles.fromFile(File('${dir.path}/media.bin'));
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  /// Appends [data] to the partial cache file and publishes it to [feed],
  /// mimicking a BufferedIOSink flush.
  Future<void> flush(PartialCacheFeed feed, List<int> data) async {
    await files.partial.parent.create(recursive: true);
    await files.partial.writeAsBytes(data,
        mode: FileMode.append, flush: true);
    feed.update(feed.flushedPosition + data.length);
  }

  PartialCacheFileStream streamFor(
    PartialCacheFeed feed, {
    int start = 0,
    int? end,
    int? sourceLength,
    int chunkSize = 16 * 1024,
  }) {
    return PartialCacheFileStream(
      range: StreamRange.validate(start, end, sourceLength),
      cacheFiles: files,
      feed: feed,
      chunkSize: chunkSize,
    );
  }

  Future<Uint8List> collect(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    await stream.forEach(builder.add);
    return builder.takeBytes();
  }

  test('serves data that is flushed after the listener attaches', () async {
    final payload = Payload.generate(200 * 1024);
    final feed = PartialCacheFeed(0);
    await flush(feed, Uint8List.sublistView(payload, 0, 64 * 1024));

    final stream = streamFor(feed, sourceLength: payload.length);
    final result = collect(stream);

    // Flush the rest progressively while the reader is live.
    for (var offset = 64 * 1024; offset < payload.length; offset += 48 * 1024) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final end = (offset + 48 * 1024).clamp(0, payload.length);
      await flush(feed, Uint8List.sublistView(payload, offset, end));
    }
    feed.finish();

    final bytes = await result;
    expect(bytes.length, payload.length);
    expect(Payload.hash(bytes), Payload.hash(payload));
  });

  test('a paused consumer buffers nothing and loses nothing', () async {
    final payload = Payload.generate(512 * 1024);
    final feed = PartialCacheFeed(0);
    await flush(feed, Uint8List.sublistView(payload, 0, 16 * 1024));

    final stream = streamFor(feed, sourceLength: payload.length);
    final received = BytesBuilder(copy: false);
    final done = Completer<void>();

    late StreamSubscription<List<int>> sub;
    sub = stream.listen(
      (data) {
        received.add(data);
        if (received.length <= 16 * 1024) {
          sub.pause(); // Pause immediately, like a stalled video player.
        }
      },
      onError: done.completeError,
      onDone: done.complete,
    );

    // While paused, the download races far ahead (well past what an in-memory
    // buffer capped at the payload size would tolerate proportionally).
    while (feed.flushedPosition < payload.length) {
      final start = feed.flushedPosition;
      final end = (start + 64 * 1024).clamp(0, payload.length);
      await flush(feed, Uint8List.sublistView(payload, start, end));
    }
    feed.finish();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    sub.resume();
    await done.future;
    expect(Payload.hash(received.takeBytes()), Payload.hash(payload));
  });

  test('serves a sub-range spanning cached and live data exactly', () async {
    final payload = Payload.generate(300 * 1024);
    final feed = PartialCacheFeed(0);
    await flush(feed, Uint8List.sublistView(payload, 0, 100 * 1024));

    const start = 50 * 1024, end = 250 * 1024;
    final stream =
        streamFor(feed, start: start, end: end, sourceLength: payload.length);
    final result = collect(stream);

    await flush(
        feed, Uint8List.sublistView(payload, 100 * 1024, payload.length));

    final bytes = await result;
    expect(bytes.length, end - start);
    expect(Payload.hash(bytes),
        Payload.hash(Uint8List.sublistView(payload, start, end)));
  });

  test('completes without error when the feed finishes an unknown-length download',
      () async {
    final payload = Payload.generate(90 * 1024);
    final feed = PartialCacheFeed(0);
    final stream = streamFor(feed); // No end, no source length.
    final result = collect(stream);

    await flush(feed, payload);
    feed.finish();

    expect(Payload.hash(await result), Payload.hash(payload));
  });

  test('serves all flushed data before surfacing a download failure',
      () async {
    final payload = Payload.generate(80 * 1024);
    final feed = PartialCacheFeed(0);
    final stream = streamFor(feed, sourceLength: 160 * 1024);

    final received = BytesBuilder(copy: false);
    final done = Completer<void>();
    Object? streamError;
    stream.listen(
      received.add,
      onError: (Object e) => streamError = e,
      onDone: done.complete,
    );

    await flush(feed, payload);
    feed.finish(DownloadStoppedException(Uri.parse('http://origin/file')));

    await done.future;
    expect(Payload.hash(received.takeBytes()), Payload.hash(payload),
        reason: 'all flushed bytes must be delivered before the error');
    expect(streamError, isA<DownloadStoppedException>());
  });

  test('cancelling the subscription stops the reader mid-follow', () async {
    final payload = Payload.generate(128 * 1024);
    final feed = PartialCacheFeed(0);
    await flush(feed, Uint8List.sublistView(payload, 0, 64 * 1024));

    final stream = streamFor(feed, sourceLength: payload.length);
    final received = BytesBuilder(copy: false);
    var closed = false;
    final sub = stream.listen(received.add, onDone: () => closed = true);

    // Let it drain the flushed data, then cancel while it waits for more.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(received.length, 64 * 1024);
    await sub.cancel();

    // Later download activity must not reach the cancelled subscription.
    await flush(feed, Uint8List.sublistView(payload, 64 * 1024));
    feed.finish();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(received.length, 64 * 1024);
    expect(closed, isFalse, reason: 'no done event after an explicit cancel');
  });

  test('is reusable: every listen gets an independent full read', () async {
    final payload = Payload.generate(150 * 1024);
    final feed = PartialCacheFeed(0);
    await flush(feed, payload);
    feed.finish();

    final stream = streamFor(feed, sourceLength: payload.length);
    // Two concurrent listeners, then a third after the others completed.
    final concurrent = await Future.wait([collect(stream), collect(stream)]);
    final sequential = await collect(stream);

    for (final bytes in [...concurrent, sequential]) {
      expect(Payload.hash(bytes), Payload.hash(payload));
    }
  });

  test('waits for readAhead at the download frontier instead of waking per flush',
      () async {
    final payload = Payload.generate(64 * 1024);
    final feed = PartialCacheFeed(0);
    // chunkSize 16KB -> readAhead 32KB.
    final stream = streamFor(feed, sourceLength: 256 * 1024);
    final received = BytesBuilder(copy: false);
    stream.listen(received.add);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    // A trivial flush below the readAhead threshold must not wake the reader.
    await flush(feed, Uint8List.sublistView(payload, 0, 10 * 1024));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(received.length, 0);

    // Crossing the threshold wakes it and everything available is served.
    await flush(feed, Uint8List.sublistView(payload, 10 * 1024, 40 * 1024));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(received.length, 40 * 1024);

    // Termination wakes it regardless of the threshold.
    await flush(feed, Uint8List.sublistView(payload, 40 * 1024));
    feed.finish();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(Payload.hash(received.takeBytes()), Payload.hash(payload));
  });

  test('a range end closer than readAhead wakes the reader as soon as it is reachable',
      () async {
    final payload = Payload.generate(10 * 1024);
    final feed = PartialCacheFeed(0);
    // Range (10KB) is smaller than readAhead (32KB); flushing exactly the
    // range must complete the stream without waiting for more data or finish.
    final stream =
        streamFor(feed, end: 10 * 1024, sourceLength: 256 * 1024);
    final result = collect(stream);

    await flush(feed, payload);
    final bytes = await result.timeout(const Duration(seconds: 5));
    expect(Payload.hash(bytes), Payload.hash(payload));
  });

  test('survives the partial file being renamed to complete mid-stream',
      () async {
    final payload = Payload.generate(256 * 1024);
    final feed = PartialCacheFeed(0);
    await flush(feed, Uint8List.sublistView(payload, 0, 128 * 1024));

    final stream = streamFor(feed, sourceLength: payload.length);
    final received = BytesBuilder(copy: false);
    final done = Completer<void>();
    late StreamSubscription<List<int>> sub;
    sub = stream.listen(
      (data) {
        received.add(data);
        sub.pause(); // Force the reader to hold its file handle across events.
        Future<void>.delayed(const Duration(milliseconds: 1), sub.resume);
      },
      onError: done.completeError,
      onDone: done.complete,
    );

    // Give the reader time to open the partial file, then finish the download
    // and rename partial -> complete, exactly like CacheDownloader does.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await files.partial.writeAsBytes(
        Uint8List.sublistView(payload, 128 * 1024),
        mode: FileMode.append,
        flush: true);
    await files.partial.rename(files.complete.path);
    feed.update(payload.length);
    feed.finish();

    await done.future;
    expect(Payload.hash(received.takeBytes()), Payload.hash(payload));
  });
}
