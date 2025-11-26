import 'dart:io';

import 'package:http/http.dart';
import 'package:http_cache_stream/src/models/http_range/http_range.dart';

import '../models/http_range/http_range_request.dart';
import '../models/http_range/http_range_response.dart';

class InvalidCacheException {
  final Uri uri;
  final String message;
  InvalidCacheException(this.uri, this.message);
  @override
  String toString() => 'InvalidCacheException: $message';
}

class CacheDeletedException extends InvalidCacheException {
  CacheDeletedException(Uri uri) : super(uri, 'Cache deleted');
}

class CacheSourceChangedException extends InvalidCacheException {
  CacheSourceChangedException(Uri uri) : super(uri, 'Cache source changed');
}

class HttpRangeException extends InvalidCacheException {
  HttpRangeException(
    Uri uri,
    HttpRangeRequest request,
    HttpRangeResponse? response,
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
}

class InvalidCacheLengthException extends InvalidCacheException {
  InvalidCacheLengthException(Uri uri, int length, int expected)
      : super(
          uri,
          'Invalid cache length | Length: $length, expected $expected (Diff: ${expected - length})',
        );
}

class CacheStreamDisposedException extends StateError {
  final Uri uri;
  CacheStreamDisposedException(this.uri)
      : super('HttpCacheStream disposed | $uri');
}

class HttpStatusCodeException extends HttpException {
  HttpStatusCodeException(Uri url, int expected, int result)
      : super(
          'Invalid HTTP status code | Expected: $expected | Result: $result',
          uri: url,
        );

  static void validate(
    final Uri url,
    final int expected,
    final int result,
  ) {
    if (result != expected) {
      throw HttpStatusCodeException(url, expected, result);
    }
  }

  static void validateCompleteResponse(
    final Uri url,
    final BaseResponse response,
  ) {
    if (response.statusCode == HttpStatus.ok) return;

    if (response.statusCode == HttpStatus.partialContent) {
      if (HttpRangeResponse.parse(response)?.isFull == true) {
        return;
      }
    }

    throw HttpStatusCodeException(url, HttpStatus.ok, response.statusCode);
  }
}
