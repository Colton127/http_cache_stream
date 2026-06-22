import 'package:http_cache_stream/src/models/http_range/http_range.dart';

import '../http_range/http_range_request.dart';
import '../http_range/http_range_response.dart';

class InvalidCacheException implements Exception {
  final Uri uri;
  final String message;
  const InvalidCacheException(this.uri, this.message);
  @override
  String toString() => 'InvalidCacheException: $message';
}

class CacheResetException extends InvalidCacheException {
  const CacheResetException(Uri uri)
      : super(uri, 'Cache reset by user request');
}

class CacheSourceChangedException extends InvalidCacheException {
  const CacheSourceChangedException(Uri uri)
      : super(uri, 'Cache source changed');
}

class HttpRangeException extends InvalidCacheException implements RangeError {
  final HttpRangeRequest request;
  final HttpRangeResponse? response;
  const HttpRangeException(
    Uri uri,
    this.request,
    this.response,
  ) : super(
          uri,
          'Invalid Download Range Response | Request: $request | Response: $response',
        );

  static void validate(
    final Uri url,
    final HttpRangeRequest request,
    final HttpRangeResponse? response,
  ) {
    if (response == null || !HttpRange.isEqual(request, response)) {
      throw HttpRangeException(url, request, response);
    }
  }

  @override
  num? get invalidValue {
    if (request.start != response?.start) {
      return request.start;
    } else if (request.end != response?.end) {
      return request.end;
    } else {
      return null;
    }
  }

  @override
  String? get name => 'HttpRangeException';

  @override
  StackTrace? get stackTrace => null;
  @override
  num? get start => request.start;
  @override
  num? get end => request.end;
}

class InvalidCacheSizeException extends InvalidCacheException {
  final int size;
  final int expected;
  const InvalidCacheSizeException(Uri uri, this.size, this.expected)
      : super(
          uri,
          'Invalid cache size | Length: $size, expected $expected (Difference: ${expected - size})',
        );

  static void validate(
    final Uri url,
    final int size,
    final int expected,
  ) {
    if (size == expected) return;

    if (expected == 0 && size == -1) {
      //Accept non-existent cache as valid if expected length is 0
      return;
    }

    throw InvalidCacheSizeException(url, size, expected);
  }
}
