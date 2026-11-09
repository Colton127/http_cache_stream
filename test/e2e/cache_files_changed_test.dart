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

  /// The [InvalidCacheSizeException]s [stream] reports, as their sizes.
  List<int> listenForInvalidSizes(HttpCacheStream stream) {
    final sizes = <int>[];
    stream.cacheStateStream.listen(null, onError: (Object e) {
      if (e is InvalidCacheSizeException) sizes.add(e.size);
    });
    return sizes;
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
    final invalidSizes = listenForInvalidSizes(stream);
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
    expect(invalidSizes, contains(-1), reason: 'the deletion is reported');

    bodyGate.complete();
    final file = await download.timeout(const Duration(seconds: 15));
    expect(Payload.hash(await file.readAsBytes()), h.payloadHash);
    await stream.dispose(force: true);
  });

  test('a complete cache file of the wrong size is downloaded again', () async {
    final stream = h.manager.createStream(h.origin.url('/truncated.mp3'));
    final invalidSizes = listenForInvalidSizes(stream);
    final file = await stream.download();
    await file.writeAsBytes(Uint8List(1000));

    final bytes =
        await read(stream, 1000, 9000).timeout(const Duration(seconds: 10));
    expect(bytes, Uint8List.sublistView(h.origin.payload, 1000, 9000));
    expect(invalidSizes, contains(1000));

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
