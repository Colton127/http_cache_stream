import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_cache_stream/src/etc/extensions/string_extensions.dart';

import 'http_range.dart';

class HttpRangeResponse extends HttpRange {
  const HttpRangeResponse._(super.start, super.end, {super.sourceLength});

  factory HttpRangeResponse(
    final int start,
    final int? end, {
    final int? sourceLength,
  }) {
    HttpRange.validate(start, end, sourceLength);
    return HttpRangeResponse._(
      start,
      end,
      sourceLength: sourceLength,
    );
  }

  /// Parses the Content-Range header from a response. Does not support 416 responses.
  /// If the header is not present or is invalid, returns null.
  static HttpRangeResponse? parse(final http.BaseResponse response) {
    String? contentRangeHeader = response.headers[HttpHeaders.contentRangeHeader];
    if (contentRangeHeader == null) return null;

    contentRangeHeader = contentRangeHeader.removeWhitespace();
    if (!contentRangeHeader.startsWith(rangeHeaderPrefix)) {
      return null;
    }

    final value = contentRangeHeader.substring(rangeHeaderPrefix.length);
    final valueParts = value.split('/');
    if (valueParts.length != 2) {
      return null;
    }
    final rangeParts = valueParts[0].split('-');
    if (rangeParts.length != 2) {
      return null;
    }
    final int? start = int.tryParse(rangeParts[0]);
    final int? end = int.tryParse(rangeParts[1]);
    if (start == null || end == null) {
      return null;
    }
    final lengthPart = valueParts[1];
    int? sourceLength;
    if (lengthPart != '*' && lengthPart.isNotEmpty) {
      sourceLength = int.tryParse(lengthPart);
      if (sourceLength == null) return null;
    }

    return HttpRangeResponse(start, end, sourceLength: sourceLength);
  }

  /// Creates a [HttpRangeResponse] from an exclusive end range by converting it to inclusive.
  /// For example: if given start=0, end=100 (exclusive), creates a range of 0-99 (inclusive).
  factory HttpRangeResponse.inclusive(
    final int start,
    final int? end,
    final int? sourceLength,
  ) {
    return HttpRangeResponse(
      start,
      end == null ? null : end - 1,
      sourceLength: sourceLength,
    );
  }

  static const rangeHeaderPrefix = 'bytes';

  String get header {
    final bytes = '$rangeHeaderPrefix $start-${end ?? ""}';
    return '$bytes/${sourceLength ?? "*"}';
  }

  @override
  String toString() {
    return 'HttpRangeResponse: $start: $start, end: $end, sourceLength: $sourceLength';
  }
}
