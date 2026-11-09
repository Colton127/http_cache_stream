import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:http_cache_stream/src/etc/extensions/file_extensions.dart';

import '../support/harness.dart';
import '../support/payload.dart';

/// The partial cache file deleted while it downloads (by the device's cache
/// management, say): the download writes on into the deleted file, where no
/// response can open what it holds. A request resets the cache, and its range
/// downloads again.
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

  test('a range it had downloaded is read again after the file was deleted',
      () async {
    final half = h.origin.payload.length ~/ 2;
    final bodyGate = Completer<void>();
    h.origin
      ..responseBodyGate = bodyGate
      ..responseBodyGateAfterBytes = half;
    final stream = h.manager.createStream(h.origin.url('/deleted.mp3'));
    final reachedHalf = Completer<void>();
    final errors = <Object>[];
    final subscription = stream.cacheStateStream.listen((state) {
      if (state.position >= half && !reachedHalf.isCompleted) {
        reachedHalf.complete();
      }
    }, onError: errors.add);
    final download = stream.download();
    await reachedHalf.future.timeout(const Duration(seconds: 5));
    final partial = stream.files.partial;
    for (var i = 0; i < 100 && (partial.lengthSyncOrNull() ?? 0) < half; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await partial.delete();

    final bytes =
        await read(stream, 1000, 9000).timeout(const Duration(seconds: 10));
    expect(bytes, Uint8List.sublistView(h.origin.payload, 1000, 9000));
    expect(errors.whereType<InvalidCacheSizeException>().map((e) => e.size),
        contains(-1),
        reason: 'the deletion is reported');

    bodyGate.complete();
    final file = await download.timeout(const Duration(seconds: 15));
    expect(Payload.hash(await file.readAsBytes()), h.payloadHash);
    await subscription.cancel();
    await stream.dispose(force: true);
  });
}
