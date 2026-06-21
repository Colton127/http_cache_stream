import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http_cache_stream/src/cache_stream/cache_downloader/buffered_io_sink.dart';
import 'package:flutter_test/flutter_test.dart';

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
    await sink.close();
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

  test('waitForPosition completes once the target is flushed', () async {
    final data = Payload.generate(10 * 1024);
    final sink = BufferedIOSink(tmp('wait.bin'), 0);
    sink.add(data);
    final f = sink.waitForPosition(5 * 1024);
    await sink.flush();
    await f; // should not throw
    await sink.close();
  });

  test('waitForPosition times out when the target is never reached', () async {
    final sink = BufferedIOSink(tmp('timeout.bin'), 0);
    sink.add(Payload.generate(1024));
    await sink.flush();
    await expectLater(
      sink.waitForPosition(1 << 30, const Duration(milliseconds: 100)),
      throwsA(isA<TimeoutException>()),
    );
    await sink.close();
  });

  test('waitForPosition fails if the sink closes before reaching it', () async {
    final sink = BufferedIOSink(tmp('closed.bin'), 0);
    sink.add(Payload.generate(1024));
    final f = sink.waitForPosition(10 * 1024 * 1024);
    await sink.close();
    await expectLater(f, throwsA(isA<StateError>()));
  });

  test('adding to a closed sink throws', () async {
    final sink = BufferedIOSink(tmp('afterclose.bin'), 0);
    await sink.close();
    expect(() => sink.add(Payload.generate(8)), throwsStateError);
    expect(sink.isClosed, isTrue);
  });
}
