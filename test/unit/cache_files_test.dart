import 'dart:io';

import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CacheFiles path derivation', () {
    test('derives partial and metadata paths from a complete file', () {
      final files = CacheFiles.fromFile(File('/tmp/cache/song.mp3'));
      expect(files.complete.path, '/tmp/cache/song.mp3');
      expect(files.partial.path, '/tmp/cache/song.mp3.part');
      expect(files.metadata.path, '/tmp/cache/song.mp3.metadata');
    });

    test('normalizes a partial file back to the complete file', () {
      final files = CacheFiles.fromFile(File('/tmp/cache/song.mp3.part'));
      expect(files.complete.path, '/tmp/cache/song.mp3');
      expect(files.partial.path, '/tmp/cache/song.mp3.part');
    });

    test('normalizes a metadata file back to the complete file', () {
      final files = CacheFiles.fromFile(File('/tmp/cache/song.mp3.metadata'));
      expect(files.complete.path, '/tmp/cache/song.mp3');
      expect(files.metadata.path, '/tmp/cache/song.mp3.metadata');
    });
  });

  group('CacheFileType', () {
    test('classifies files by extension', () {
      expect(CacheFileType.isPartial(File('a.mp3.part')), isTrue);
      expect(CacheFileType.isMetadata(File('a.mp3.metadata')), isTrue);
      expect(CacheFileType.isComplete(File('a.mp3')), isTrue);
      expect(CacheFileType.parse(File('a.mp3.part')), CacheFileType.partial);
    });
  });

  group('CacheFiles.delete', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('hcs_files_');
    });

    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('deletes all files', () async {
      final files = CacheFiles.fromFile(File('${dir.path}/x.bin'));
      await files.complete.writeAsString('c');
      await files.partial.writeAsString('p');
      await files.metadata.writeAsString('m');

      final deleted = await files.delete();
      expect(deleted, isTrue);
      expect(files.complete.existsSync(), isFalse);
      expect(files.partial.existsSync(), isFalse);
      expect(files.metadata.existsSync(), isFalse);
    });

    test('partialOnly keeps a completed cache', () async {
      final files = CacheFiles.fromFile(File('${dir.path}/y.bin'));
      await files.complete.writeAsString('c');
      await files.partial.writeAsString('p');

      final deleted = await files.delete(partialOnly: true);
      expect(deleted, isFalse); // complete exists, so nothing removed
      expect(files.complete.existsSync(), isTrue);
      expect(files.partial.existsSync(), isTrue);
    });
  });
}
