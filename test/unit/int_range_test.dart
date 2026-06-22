import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IntRange.validate', () {
    test('null start/end yields the full range', () {
      final r = IntRange.validate(null, null, null);
      expect(r.isFull, isTrue);
      expect(r.start, 0);
      expect(r.end, isNull);
    });

    test('start 0 with null end yields the full range', () {
      expect(IntRange.validate(0, null, null).isFull, isTrue);
    });

    test('a bounded range is preserved', () {
      final r = IntRange.validate(0, 100, 500);
      expect(r.start, 0);
      expect(r.end, 100);
      expect(r.isFull, isFalse);
    });

    test('start greater than end throws', () {
      expect(() => IntRange.validate(5, 3, null), throwsRangeError);
    });

    test('negative start throws', () {
      expect(() => IntRange.validate(-1, null, null), throwsRangeError);
    });

    test('start beyond max throws', () {
      expect(() => IntRange.validate(10, null, 5), throwsRangeError);
    });

    test('end beyond max throws', () {
      expect(() => IntRange.validate(0, 600, 500), throwsRangeError);
    });
  });

  group('IntRange.compareTo (backs sorted request queueing)', () {
    test('orders by start then end', () {
      final list = [
        const IntRange(10, 20),
        const IntRange(0, 50),
        const IntRange(0, 10),
      ]..sort();
      expect(list, [
        const IntRange(0, 10),
        const IntRange(0, 50),
        const IntRange(10, 20),
      ]);
    });

    test('an open-ended range sorts after a closed one with the same start',
        () {
      expect(const IntRange(0, null).compareTo(const IntRange(0, 100)), 1);
      expect(const IntRange(0, 100).compareTo(const IntRange(0, null)), -1);
    });
  });
}
