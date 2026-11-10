import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http_cache_stream/src/cache_stream/cache_downloader/buffered_io_sink.dart';
import 'package:http_cache_stream/src/cache_stream/response_streams/partial_cache_feed.dart';
import 'package:http_cache_stream/src/models/exceptions/partial_cache_feed_exceptions.dart';

import '../support/payload.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hcs_sink_');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  File tmp(String name) => File('${dir.path}/$name');

  test('writes chunks in order with byte-for-byte integrity', () async {
    final data = Payload.generate(300 * 1024);
    final file = tmp('out.bin');
    final sink = BufferedIOSink(file, 0);

    // Feed the payload in uneven chunks.
    var offset = 0;
    for (final size in [1, 1024, 65535, 200000, data.length - 266560]) {
      sink.add(Uint8List.sublistView(data, offset, offset + size));
      offset += size;
    }
    expect(offset, data.length);

    await sink.close();
    final written = await file.readAsBytes();
    expect(written.length, data.length);
    expect(Payload.hash(written), Payload.hash(data));
  });

  test('flushedBytes accounts for everything written', () async {
    final data = Payload.generate(100 * 1024);
    final file = tmp('count.bin');
    final sink = BufferedIOSink(file, 0);

    sink.add(data);
    expect(sink.bufferSize, data.length);
    await sink.flush();
    expect(sink.bufferSize, 0);
    expect(sink.flushedBytes, data.length);
    expect(sink.feed.position, data.length);
    await sink.close();
    expect(sink.feed.isClosed, isTrue);
  });

  test('append mode resumes from an existing partial file', () async {
    final first = Payload.generate(50 * 1024, seed: 1);
    final second = Payload.generate(50 * 1024, seed: 2);
    final file = tmp('resume.bin');
    await file.writeAsBytes(first);

    final sink = BufferedIOSink(file, first.length);
    sink.add(second);
    await sink.close();

    final written = await file.readAsBytes();
    expect(written.length, first.length + second.length);
    final expected = Uint8List.fromList([...first, ...second]);
    expect(Payload.hash(written), Payload.hash(expected));
  });

  test('resuming a file that does not end where the sink resumes it fails',
      () async {
    final saved = Payload.generate(50 * 1024, seed: 1);
    for (final changed in <Uint8List?>[
      null, // deleted
      Uint8List.sublistView(saved, 0, 1024), // truncated
      Uint8List.fromList([...saved, 1, 2, 3]), // written to
    ]) {
      final file = tmp('changed.bin');
      if (changed != null) await file.writeAsBytes(changed);
      if (changed == null && file.existsSync()) await file.delete();

      final sink = BufferedIOSink(file, saved.length);
      sink.add(Payload.generate(1024, seed: 2));
      await expectLater(
        sink.flush(),
        throwsA(isA<SinkFileLengthException>()
            .having((e) => e.length, 'length', changed?.length ?? 0)
            .having((e) => e.expected, 'expected', saved.length)),
      );
      expect(sink.flushedBytes, saved.length);
      expect(await file.length(), changed?.length ?? 0,
          reason: 'nothing is written to it');
      await sink.close().catchError((_) {});
    }
  });

  test('waitForPosition completes once the target is flushed', () async {
    final data = Payload.generate(10 * 1024);
    final sink = BufferedIOSink(tmp('wait.bin'), 0);
    sink.add(data);
    final f = sink.waitForPosition(5 * 1024);
    await sink.flush();
    await f.future; // should not throw
    await sink.close();
  });

  test('feed waitForPosition completes once the target is flushed', () async {
    final data = Payload.generate(10 * 1024);
    final sink = BufferedIOSink(tmp('feed-wait.bin'), 0);
    final feed = sink.feed;
    sink.add(data);

    final wait = feed.waitForPosition(5 * 1024);
    await sink.flush();
    await wait.future; // should not throw

    expect(feed.position, data.length);
    await sink.close();
    expect(feed.isClosed, isTrue);
  });

  test('cancel fails the waiter and releases it from the feed', () async {
    final sink = BufferedIOSink(tmp('cancel.bin'), 0);
    final waiter = sink.waitForPosition(10 * 1024);
    expect(waiter.isCompleted, isFalse);

    // Attach the matcher before cancelling: an unobserved error future would
    // otherwise crash the test.
    final expectation = expectLater(
        waiter.future, throwsA(isA<PositionWaiterCancelledException>()));
    waiter.cancel();
    expect(waiter.isCompleted, isTrue);
    await expectation;

    // The waiter is no longer tracked, so reaching its position does nothing.
    sink.add(Payload.generate(10 * 1024));
    await sink.flush();
    expect(sink.feed.position, 10 * 1024);
    expect(sink.feed.failure, isNull);

    await sink.close(isDone: true);
  });

  test('cancel is a no-op once the waiter has been satisfied', () async {
    final sink = BufferedIOSink(tmp('cancel-late.bin'), 0);
    sink.add(Payload.generate(4 * 1024));

    final waiter = sink.waitForPosition(2 * 1024);
    await sink.flush();
    await waiter.future;

    waiter.cancel(); // Must not turn a satisfied wait into a failure
    expect(waiter.isCompleted, isTrue);
    await waiter.future; // Still completes normally

    await sink.close(isDone: true);
  });

  test('cancel is a no-op for a position that was already reached', () async {
    final sink = BufferedIOSink(tmp('cancel-reached.bin'), 0);
    sink.add(Payload.generate(4 * 1024));
    await sink.flush();

    final waiter = sink.waitForPosition(1024);
    expect(waiter.isCompleted, isTrue);
    waiter.cancel();
    await waiter.future; // Completed waiters ignore cancel

    await sink.close(isDone: true);
  });

  test('waitForPosition fails as aborted if the sink closes before reaching it',
      () async {
    final sink = BufferedIOSink(tmp('closed.bin'), 0);
    sink.add(Payload.generate(1024));
    // Attach the matcher before closing: close() fails the waiter synchronously,
    // and an unobserved error future would otherwise crash the test.
    final expectation = expectLater(
        sink.waitForPosition(10 * 1024 * 1024).future,
        throwsA(isA<PartialCacheAbortedException>()));
    await sink.close();
    await expectation;

    // The feed carries the failure, so a reader with no known end position can
    // tell the truncated content apart from an end of stream.
    expect(sink.feed.failure, isA<PartialCacheAbortedException>());
  });

  test(
      'waitForPosition fails as closed when the sink is done before reaching it',
      () async {
    final sink = BufferedIOSink(tmp('closed-done.bin'), 0);
    sink.add(Payload.generate(1024));
    final expectation = expectLater(
        sink.waitForPosition(10 * 1024 * 1024).future,
        throwsA(isA<StateError>()));
    await sink.close(isDone: true);
    await expectation;

    // Reaching the end of the content is not a failure: flushedBytes is the
    // true end, so readers must treat it as an end of stream.
    expect(sink.feed.failure, isNull);
  });

  test('adding to a closed sink throws', () async {
    final sink = BufferedIOSink(tmp('afterclose.bin'), 0);
    await sink.close();
    expect(() => sink.add(Payload.generate(8)), throwsStateError);
    expect(sink.isClosed, isTrue);
  });
}
