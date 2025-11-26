import 'dart:io';

import 'package:http/http.dart';

import 'http_range.dart';

class HttpRangeResponse extends HttpRange {
  const HttpRangeResponse._(super.start, super.end, {super.sourceLength});

  /// Parses the Content-Range header from a response.
  /// If the header is not present or is invalid, returns null.
  static HttpRangeResponse? parse(final BaseResponse response) {
    final String? contentRangeHeader =
        response.headers[HttpHeaders.contentRangeHeader];
    if (contentRangeHeader == null) return null;

    var (int? start, int? end, int? sourceLength) =
        HttpRange.parse(contentRangeHeader);
    if (start == null && end == null && sourceLength == null) {
      return null;
    }
    start ??= 0;
    final int? contentLength = response.contentLength;
    if (sourceLength == null &&
        start == 0 &&
        end == null &&
        contentLength != null &&
        contentLength > 0) {
      sourceLength =
          contentLength; // If the source length is unknown, use the content length
    }

    return HttpRangeResponse._(start, end, sourceLength: sourceLength);
  }

  /// Creates a [HttpRangeResponse] from an exclusive end range by converting it to inclusive.
  /// For example: if given start=0, end=100 (exclusive), creates a range of 0-99 (inclusive).
  factory HttpRangeResponse.inclusive(
    final int start,
    final int? end, {
    final int? sourceLength,
  }) {
    return HttpRangeResponse._(
      start,
      end == null ? null : end - 1,
      sourceLength: sourceLength,
    );
  }

  String get header {
    final bytes = 'bytes $start-${end ?? ""}';
    return '$bytes/${sourceLength ?? "*"}';
  }

  @override
  String toString() {
    return 'HttpRangeResponse: $start: $start, end: $end, sourceLength: $sourceLength';
  }
}
