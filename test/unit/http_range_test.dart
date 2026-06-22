import 'package:http/http.dart' as http;
import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:flutter_test/flutter_test.dart';

HttpRangeResponse? parseContentRange(String? value) {
  final headers = value == null ? <String, String>{} : {'content-range': value};
  return HttpRangeResponse.parse(http.Response('', 206, headers: headers));
}

void main() {
  group('HttpRangeResponse.parse', () {
    test('parses start, end and total', () {
      final r = parseContentRange('bytes 0-99/500');
      expect(r, isNotNull);
      expect(r!.start, 0);
      expect(r.end, 99);
      expect(r.sourceLength, 500);
    });

    test('unknown total (*) yields null source length', () {
      final r = parseContentRange('bytes 0-99/*');
      expect(r, isNotNull);
      expect(r!.sourceLength, isNull);
    });

    test('unsatisfied-range form (*/500) is not supported', () {
      expect(parseContentRange('bytes */500'), isNull);
    });

    test('malformed values return null', () {
      expect(parseContentRange('bytes abc'), isNull);
      expect(parseContentRange('0-99/500'), isNull); // missing prefix
      expect(parseContentRange(null), isNull); // missing header
    });
  });

  group('HttpRangeResponse formatting', () {
    test('header round-trips with a known total', () {
      expect(
          HttpRangeResponse(0, 99, sourceLength: 500).header, 'bytes 0-99/500');
    });

    test('header uses * for unknown total', () {
      expect(HttpRangeResponse(0, 99).header, 'bytes 0-99/*');
    });

    test('inclusive factory converts an exclusive end', () {
      final r = HttpRangeResponse.inclusive(0, 100, 500);
      expect(r.end, 99);
      expect(r.contentLength, 100);
    });
  });

  group('HttpRangeRequest', () {
    test('header for a closed range', () {
      expect(HttpRangeRequest(0, 99).header, 'bytes=0-99');
    });

    test('header for an open-ended range', () {
      expect(HttpRangeRequest(100, null).header, 'bytes=100-');
    });

    test('inclusive factory converts an exclusive end', () {
      expect(HttpRangeRequest.inclusive(0, 100).header, 'bytes=0-99');
    });

    test('start greater than end throws', () {
      expect(() => HttpRangeRequest(5, 3), throwsRangeError);
    });

    test('negative start throws', () {
      expect(() => HttpRangeRequest(-1, 10), throwsRangeError);
    });

    test('content length covers the inclusive span', () {
      expect(HttpRangeRequest(0, 99).contentLength, 100);
    });
  });

  group('HttpRange.isEqual', () {
    test('equal when start/end/total match', () {
      expect(
        HttpRange.isEqual(
          HttpRangeRequest(0, 99),
          HttpRangeResponse(0, 99, sourceLength: 500),
        ),
        isTrue,
      );
    });

    test('not equal when start differs', () {
      expect(
        HttpRange.isEqual(HttpRangeRequest(0, 99), HttpRangeResponse(1, 99)),
        isFalse,
      );
    });
  });
}
