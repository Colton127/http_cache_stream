import 'dart:io';

import 'package:http_cache_stream/src/models/http_range/http_range.dart';

import '../http_range/http_range_request.dart';
import '../http_range/http_range_response.dart';

class InvalidCacheException {
  final Uri uri;
  final String message;
  InvalidCacheException(this.uri, this.message);
  @override
  String toString() => 'InvalidCacheException: $message';
}

class CacheResetException extends InvalidCacheException {
  CacheResetException(Uri uri) : super(uri, 'Cache reset by user request');
}

class CacheSourceChangedException extends InvalidCacheException {
  CacheSourceChangedException(Uri uri) : super(uri, 'Cache source changed');
}

class HttpRangeException extends InvalidCacheException implements HttpException, RangeError {
  final HttpRangeRequest request;
  final HttpRangeResponse? response;
  HttpRangeException(
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

class InvalidCacheLengthException extends InvalidCacheException {
  InvalidCacheLengthException(Uri uri, int length, int expected)
      : super(
          uri,
          'Invalid cache length | Length: $length, expected $expected (Diff: ${expected - length})',
        );
}
