import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CacheState.zero', () {
    test('has no position, length or progress', () {
      const s = CacheState.zero();
      expect(s.position, 0);
      expect(s.sourceLength, isNull);
      expect(s.isComplete, isFalse);
      expect(s.progress, isNull);
      expect(s.remainingBytes, isNull);
    });
  });

  group('CacheState.incomplete', () {
    test('reports fractional progress and remaining bytes', () {
      const s = CacheState.incomplete(50, 100);
      expect(s.progress, closeTo(0.5, 1e-9));
      expect(s.remainingBytes, 50);
      expect(s.isComplete, isFalse);
    });

    test('progress is capped below 1.0 until finalized', () {
      const s = CacheState.incomplete(100, 100);
      expect(s.progress, lessThan(1.0));
      expect(s.progress, closeTo(0.99, 1e-9));
      expect(s.isComplete, isFalse);
    });

    test('unknown source length means null progress and remaining', () {
      const s = CacheState.incomplete(50, null);
      expect(s.progress, isNull);
      expect(s.remainingBytes, isNull);
    });

    test('zero source length means null progress', () {
      const s = CacheState.incomplete(0, 0);
      expect(s.progress, isNull);
    });
  });

  group('CacheState.complete', () {
    test('is fully complete with progress 1.0', () {
      const s = CacheState.complete(100);
      expect(s.isComplete, isTrue);
      expect(s.progress, 1.0);
      expect(s.position, 100);
      expect(s.remainingBytes, 0);
    });
  });

  group('equality', () {
    test('incomplete states compare by position and length', () {
      expect(const CacheState.incomplete(10, 100),
          const CacheState.incomplete(10, 100));
      expect(const CacheState.incomplete(10, 100),
          isNot(const CacheState.incomplete(20, 100)));
    });

    test('complete states compare by source length', () {
      expect(const CacheState.complete(100), const CacheState.complete(100));
      expect(const CacheState.complete(100),
          isNot(const CacheState.complete(200)));
    });

    test('a complete and incomplete state are never equal', () {
      expect(const CacheState.complete(100),
          isNot(const CacheState.incomplete(100, 100)));
    });
  });
}
