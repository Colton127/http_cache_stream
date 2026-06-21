import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/payload.dart';

CachedResponseHeaders headersWithLength(int length) {
  return CachedResponseHeaders.fromBaseResponse(
    http.Response('', 200, headers: {'content-length': '$length'}),
  );
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hcs_meta_');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  CacheFiles filesFor(String name) =>
      CacheFiles.fromFile(File('${dir.path}/$name'));

  group('CacheMetadata.cacheState', () {
    test('a complete file of the expected size reports complete', () async {
      final files = filesFor('a.bin');
      await files.complete.writeAsBytes(Payload.generate(100));
      final meta = CacheMetadata(
          files, Uri.parse('https://e.com/a.bin'), headersWithLength(100));

      final state = await meta.cacheState();
      expect(state.isComplete, isTrue);
      expect(state.position, 100);
    });

    test('a short partial file reports incomplete', () async {
      final files = filesFor('b.bin');
      await files.partial.writeAsBytes(Payload.generate(40));
      final meta = CacheMetadata(
          files, Uri.parse('https://e.com/b.bin'), headersWithLength(100));

      final state = await meta.cacheState();
      expect(state.isComplete, isFalse);
      expect(state.position, 40);
      expect(state.sourceLength, 100);
    });

    test('an oversized partial file is rejected as invalid', () async {
      final files = filesFor('c.bin');
      await files.partial.writeAsBytes(Payload.generate(150));
      final meta = CacheMetadata(
          files, Uri.parse('https://e.com/c.bin'), headersWithLength(100));

      await expectLater(
        meta.cacheState(),
        throwsA(isA<InvalidCacheSizeException>()),
      );
    });

    test('a full-size partial file is promoted to complete', () async {
      final files = filesFor('d.bin');
      await files.partial.writeAsBytes(Payload.generate(100));
      final meta = CacheMetadata(
          files, Uri.parse('https://e.com/d.bin'), headersWithLength(100));

      final state = await meta.cacheState();
      expect(state.isComplete, isTrue);
      expect(files.complete.existsSync(), isTrue);
      expect(files.partial.existsSync(), isFalse);
    });

    test('unknown source length reports zero', () async {
      final files = filesFor('e.bin');
      final meta = CacheMetadata(files, Uri.parse('https://e.com/e.bin'), null);
      final state = await meta.cacheState();
      expect(state, const CacheState.zero());
    });
  });

  group('CachedResponseHeaders.fromFile', () {
    test('synthesizes length, range support and content-type from the file',
        () async {
      final file = File('${dir.path}/clip.mp3');
      final bytes = Payload.generate(2048);
      await file.writeAsBytes(bytes);

      final headers = CachedResponseHeaders.fromFile(file);
      expect(headers, isNotNull);
      expect(headers!.sourceLength, bytes.length);
      expect(headers.acceptsRangeRequests, isTrue);
      expect(headers.contentType, isNotNull);
    });

    test('returns null for a missing or empty file', () async {
      expect(CachedResponseHeaders.fromFile(File('${dir.path}/nope.bin')),
          isNull);
      final empty = File('${dir.path}/empty.bin');
      await empty.writeAsBytes(Uint8List(0));
      expect(CachedResponseHeaders.fromFile(empty), isNull);
    });
  });
}
