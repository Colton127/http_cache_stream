import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds [CachedResponseHeaders] from a synthetic HTTP response. Header keys
/// must be lowercase to match the `HttpHeaders.*` constants the package looks up.
CachedResponseHeaders headers(Map<String, String> map, {int status = 200}) {
  return CachedResponseHeaders.fromBaseResponse(
      http.Response('', status, headers: map));
}

void main() {
  group('essential header extraction', () {
    test('content-length, content-type, accept-ranges, etag, last-modified',
        () {
      final lm = DateTime.utc(2024, 1, 1, 12);
      final h = headers({
        'content-length': '500',
        'content-type': 'audio/mpeg',
        'accept-ranges': 'bytes',
        'etag': '"abc"',
        'last-modified': HttpDate.format(lm),
      });

      expect(h.contentLength, 500);
      expect(h.sourceLength, 500);
      expect(h.contentType?.mimeType, 'audio/mpeg');
      expect(h.acceptsRangeRequests, isTrue);
      expect(h.canResumeDownload(), isTrue);
      expect(h.eTag, '"abc"');
      expect(h.lastModified, lm);
    });

    test('content-length of 0 is treated as unknown', () {
      final h = headers({'content-length': '0'});
      expect(h.contentLength, isNull);
      expect(h.sourceLength, isNull);
    });

    test('missing accept-ranges means range requests unsupported', () {
      final h = headers({'content-length': '10'});
      expect(h.acceptsRangeRequests, isFalse);
      expect(h.canResumeDownload(), isFalse);
    });
  });

  group('compressed / chunked responses have unknown source length', () {
    test('gzip', () {
      final h = headers({'content-length': '500', 'content-encoding': 'gzip'});
      expect(h.isCompressedOrChunked, isTrue);
      expect(h.sourceLength, isNull);
      expect(h.canResumeDownload(), isFalse);
    });

    test('chunked', () {
      final h = headers({'transfer-encoding': 'chunked'});
      expect(h.isCompressedOrChunked, isTrue);
      expect(h.sourceLength, isNull);
    });
  });

  group('content-range responses', () {
    test('source length is taken from the content-range total', () {
      final h = headers(
        {'content-range': 'bytes 0-99/500', 'content-length': '100'},
        status: HttpStatus.partialContent,
      );
      expect(h.sourceLength, 500);
      expect(h.acceptsRangeRequests, isTrue);
      // The content-range header itself is stripped from the stored headers.
      expect(h.get(HttpHeaders.contentRangeHeader), isNull);
    });
  });

  group('setSourceLength', () {
    test('sets length + accept-ranges and strips encoding/range headers', () {
      final original = headers({
        'content-encoding': 'gzip',
        'transfer-encoding': 'chunked',
        'content-range': 'bytes 0-99/*',
      });
      final updated = original.setSourceLength(1234);

      expect(updated.sourceLength, 1234);
      expect(updated.acceptsRangeRequests, isTrue);
      expect(updated.get(HttpHeaders.contentEncodingHeader), isNull);
      expect(updated.get(HttpHeaders.transferEncodingHeader), isNull);
      expect(updated.get(HttpHeaders.contentRangeHeader), isNull);
    });
  });

  group('essentialHeaders', () {
    test('retains only whitelisted headers', () {
      final h = headers({
        'content-length': '10',
        'content-type': 'text/plain',
        'etag': '"e"',
        'x-custom': 'should-be-dropped',
        'server': 'nginx',
      });
      final essential = h.essentialHeaders();
      expect(essential.get('content-length'), '10');
      expect(essential.get('content-type'), 'text/plain');
      expect(essential.get('etag'), '"e"');
      expect(essential.get('x-custom'), isNull);
      expect(essential.get('server'), isNull);
    });
  });

  group('revalidation / expiry', () {
    test('expires in the future means no revalidation needed', () {
      final future = DateTime.now().toUtc().add(const Duration(hours: 1));
      final h = headers({'expires': HttpDate.format(future)});
      expect(h.cacheExpirationDateTime, isNotNull);
      expect(h.shouldRevalidate(), isFalse);
    });

    test('expires in the past means revalidate', () {
      final past = DateTime.now().toUtc().subtract(const Duration(hours: 1));
      final h = headers({'expires': HttpDate.format(past)});
      expect(h.shouldRevalidate(), isTrue);
    });

    test('cache-control max-age combined with date', () {
      final date = DateTime.now().toUtc();
      final h = headers({
        'date': HttpDate.format(date),
        'cache-control': 'max-age=3600',
      });
      final expiry = h.cacheExpirationDateTime;
      expect(expiry, isNotNull);
      expect(expiry!.isAfter(date), isTrue);
      expect(h.shouldRevalidate(), isFalse);
    });

    test('no expiry information means revalidate', () {
      final h = headers({'content-length': '10'});
      expect(h.cacheExpirationDateTime, isNull);
      expect(h.shouldRevalidate(), isTrue);
    });
  });

  group('validateCacheResponse', () {
    test('matching etags validate', () {
      final a = headers({'etag': '"v1"', 'content-length': '10'});
      final b = headers({'etag': '"v1"', 'content-length': '999'});
      expect(CachedResponseHeaders.validateCacheResponse(a, b), isTrue);
    });

    test('mismatched etags invalidate', () {
      final a = headers({'etag': '"v1"'});
      final b = headers({'etag': '"v2"'});
      expect(CachedResponseHeaders.validateCacheResponse(a, b), isFalse);
    });

    test('a newer last-modified invalidates', () {
      final older = DateTime.utc(2024, 1, 1);
      final newer = DateTime.utc(2024, 6, 1);
      final a = headers({'last-modified': HttpDate.format(older)});
      final b = headers({'last-modified': HttpDate.format(newer)});
      expect(CachedResponseHeaders.validateCacheResponse(a, b), isFalse);
    });

    test('equal source length validates when no etag/last-modified', () {
      final a = headers({'content-length': '500'});
      final b = headers({'content-length': '500'});
      expect(CachedResponseHeaders.validateCacheResponse(a, b), isTrue);
    });
  });

  group('date parsing', () {
    test('invalid date header parses to null', () {
      final h = headers({'last-modified': 'not-a-date'});
      expect(h.lastModified, isNull);
    });
  });

  group('json round-trip', () {
    test('toJson then fromJson preserves header values', () {
      final original = headers({
        'content-length': '500',
        'content-type': 'audio/mpeg',
        'etag': '"v1"',
      });
      final restored = CachedResponseHeaders.fromJson(original.toJson());
      expect(restored, isNotNull);
      expect(restored!.sourceLength, 500);
      expect(restored.contentType?.mimeType, 'audio/mpeg');
      expect(restored.eTag, '"v1"');
    });

    test('fromJson joins list-valued headers', () {
      final restored = CachedResponseHeaders.fromJson({
        'content-length': '12',
        'set-cookie': ['a=1', 'b=2'],
      });
      expect(restored, isNotNull);
      expect(restored!.get('set-cookie'), 'a=1, b=2');
    });
  });
}
