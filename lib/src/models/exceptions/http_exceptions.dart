import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../http_range/http_range_response.dart';

class ResponseTimedOutException extends http.ClientException implements TimeoutException {
  @override
  final Duration duration;
  ResponseTimedOutException(Uri uri, this.duration) : super('Response timed out after $duration', uri);
}

class ReadTimedOutException extends http.ClientException implements TimeoutException {
  @override
  final Duration duration;
  ReadTimedOutException(Uri uri, this.duration) : super('Read timed out after $duration', uri);
}

class DownloadResponseException extends http.ClientException {
  final Object originalError;
  DownloadResponseException(Uri uri, this.originalError) : super('Download response error: $originalError', uri);
}

class HttpStatusCodeException extends HttpException {
  final int expected;
  final int result;
  HttpStatusCodeException(Uri url, this.expected, this.result)
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
    final http.BaseResponse response,
  ) {
    if (response.statusCode == HttpStatus.ok) {
      return;
    }

    if (response.statusCode == HttpStatus.partialContent) {
      if (HttpRangeResponse.parse(response)?.isFull ?? true) {
        return;
      }
    }

    throw HttpStatusCodeException(url, HttpStatus.ok, response.statusCode);
  }
}
