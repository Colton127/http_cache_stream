import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:http_cache_stream/src/etc/extensions/file_extensions.dart';

import '../support/harness.dart';
import '../support/payload.dart';

/// Waits for [condition], polling, and fails if it does not hold within 5 s.
Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 500 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

/// Cache files deleted or changed underneath a stream (by the device's cache
/// management, say). Each request revalidates them, and a cache they no longer
/// hold is reset and downloaded again.
void main() {
  late CacheTestHarness h;

  setUp(() async {
    h = CacheTestHarness();
    await h.setUp();
  });

  tearDown(() => h.tearDown());

  Future<Uint8List> read(HttpCacheStream stream, int start, int end) async {
    final response = await stream.request(start: start, end: end);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// The errors [stream] reports.
  List<Object> listenForErrors(HttpCacheStream stream) {
    final errors = <Object>[];
    stream.cacheStateStream.listen(null, onError: errors.add);
    return errors;
  }

  /// The [InvalidCacheSizeException]s in [errors], as their sizes.
  List<int> invalidSizes(List<Object> errors) =>
      [for (final e in errors.whereType<InvalidCacheSizeException>()) e.size];

  /// Leaves a partial cache of [source]'s first [bytes], as an interrupted
  /// download does.
  Future<void> interruptAt(Uri source, int bytes) async {
    final gate = Completer<void>();
    h.origin
      ..responseBodyGate = gate
      ..responseBodyGateAfterBytes = bytes;
    final stream = h.manager.createStream(source);
    stream.download().ignore();
    await _until(() => stream.cachePosition >= bytes);
    await stream.dispose(force: true);
    h.origin
      ..responseBodyGate = null
      ..responseBodyGateAfterBytes = null;
    gate.complete();
    expect(stream.files.partial.lengthSyncOrNull(), bytes);
  }

  test(
      'a range it had downloaded is read again after the partial file was '
      'deleted', () async {
    final half = h.origin.payload.length ~/ 2;
    final bodyGate = Completer<void>();
    h.origin
      ..responseBodyGate = bodyGate
      ..responseBodyGateAfterBytes = half;
    final stream = h.manager.createStream(h.origin.url('/deleted.mp3'));
    final errors = listenForErrors(stream);
    final download = stream.download();
    await _until(() => stream.cachePosition >= half);
    final partial = stream.files.partial;
    await _until(() => (partial.lengthSyncOrNull() ?? 0) >= half);
    await partial.delete();

    // The download writes on into the deleted file, where no response can
    // open what it holds.
    final bytes =
        await read(stream, 1000, 9000).timeout(const Duration(seconds: 10));
    expect(bytes, Uint8List.sublistView(h.origin.payload, 1000, 9000));
    expect(invalidSizes(errors), contains(-1),
        reason: 'the deletion is reported');

    bodyGate.complete();
    final file = await download.timeout(const Duration(seconds: 15));
    expect(Payload.hash(await file.readAsBytes()), h.payloadHash);
    await stream.dispose(force: true);
  });

  test(
      'a resumed download whose partial file was deleted before it wrote '
      'saves no bytes at the wrong offset', () async {
    final source = h.origin.url('/resume-deleted.mp3');
    final half = h.origin.payload.length ~/ 2;
    final quarter = h.origin.payload.length ~/ 4;
    await interruptAt(source, half);

    // The resumed download waits for the origin while its partial file is
    // deleted, then saves a quarter and stops, before any request or refresh
    // could see the file change.
    final startGate = Completer<void>();
    final bodyGate = Completer<void>();
    h.origin
      ..responseStartGate = startGate
      ..responseBodyGate = bodyGate
      ..responseBodyGateAfterBytes = quarter;
    final requestsBefore = h.origin.requestCount;
    final resumed = h.manager.createStream(source);
    final errors = listenForErrors(resumed);
    resumed.download().ignore();
    await _until(() => h.origin.requestCount > requestsBefore);
    await resumed.files.partial.delete();
    startGate.complete();
    await _until(
        () => (resumed.files.partial.lengthSyncOrNull() ?? 0) >= quarter);
    await resumed.dispose(force: true);
    expect(invalidSizes(errors), contains(0),
        reason: 'the deletion is reported');
    h.origin
      ..responseStartGate = null
      ..responseBodyGate = null
      ..responseBodyGateAfterBytes = null;
    bodyGate.complete();

    // What it saved is resumed from, and must be the content's start.
    final next = h.manager.createStream(source);
    final file = await next.download().timeout(const Duration(seconds: 15));
    expect(Payload.hash(await file.readAsBytes()), h.payloadHash);
    await next.dispose(force: true);
  });

  test('concurrent requests after the partial file was deleted reset it once',
      () async {
    final half = h.origin.payload.length ~/ 2;
    final bodyGate = Completer<void>();
    h.origin
      ..responseBodyGate = bodyGate
      ..responseBodyGateAfterBytes = half;
    final stream = h.manager.createStream(h.origin.url('/deleted-twice.mp3'));
    final errors = listenForErrors(stream);
    final download = stream.download();
    await _until(() => stream.cachePosition >= half);
    final partial = stream.files.partial;
    await _until(() => (partial.lengthSyncOrNull() ?? 0) >= half);
    final requestsBefore = h.origin.requestCount;
    await partial.delete();

    // Each request revalidates; one reset is due, not one for each.
    final ranges = [(1000, 9000), (20000, 30000), (50000, 60000)];
    final reads = await Future.wait([
      for (final (start, end) in ranges) read(stream, start, end),
    ]).timeout(const Duration(seconds: 10));
    for (final (i, (start, end)) in ranges.indexed) {
      expect(reads[i], Uint8List.sublistView(h.origin.payload, start, end));
    }
    expect(invalidSizes(errors), [-1]);
    expect(h.origin.requestCount, requestsBefore + 1,
        reason: 'the download starts over once');

    bodyGate.complete();
    final file = await download.timeout(const Duration(seconds: 15));
    expect(Payload.hash(await file.readAsBytes()), h.payloadHash);
    await stream.dispose(force: true);
  });

  test('a complete cache file of the wrong size is downloaded again', () async {
    final stream = h.manager.createStream(h.origin.url('/truncated.mp3'));
    final errors = listenForErrors(stream);
    final file = await stream.download();
    await file.writeAsBytes(Uint8List(1000));

    final bytes =
        await read(stream, 1000, 9000).timeout(const Duration(seconds: 10));
    expect(bytes, Uint8List.sublistView(h.origin.payload, 1000, 9000));
    expect(invalidSizes(errors), contains(1000));

    final downloaded =
        await stream.download().timeout(const Duration(seconds: 15));
    expect(Payload.hash(await downloaded.readAsBytes()), h.payloadHash);
    await stream.dispose(force: true);
  });

  test(
      'refreshing the state of a download of unknown length keeps its '
      'position', () async {
    final half = h.origin.payload.length ~/ 2;
    final bodyGate = Completer<void>();
    h.origin
      ..chunkedTransferEncoding = true
      ..responseBodyGate = bodyGate
      ..responseBodyGateAfterBytes = half;
    final stream = h.manager.createStream(h.origin.url('/chunked.mp3'));
    final download = stream.download();
    await _until(() => stream.cachePosition >= half);
    await _until(() => (stream.files.partial.lengthSyncOrNull() ?? 0) >= half);

    // The cache files cannot tell how far a download of unknown length got.
    final state = await stream.refreshCacheState();
    expect(state.position, half);
    expect(state.filePosition, half);
    expect(state.sourceLength, isNull);
    expect(stream.cacheState, state);

    bodyGate.complete();
    final file = await download.timeout(const Duration(seconds: 15));
    expect(Payload.hash(await file.readAsBytes()), h.payloadHash);
    await stream.dispose(force: true);
  });
}
