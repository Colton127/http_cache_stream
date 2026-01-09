import 'dart:io';

import '../../etc/extensions/string_extensions.dart';
import 'http_range.dart';

class HttpRangeRequest extends HttpRange {
  const HttpRangeRequest._(super.start, super.end);

  factory HttpRangeRequest(
    final int start,
    final int? end,
  ) {
    HttpRange.validate(start, end);
    return HttpRangeRequest._(start, end);
  }

  static HttpRangeRequest? parse(final HttpRequest request) {
    String? rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    if (rangeHeader == null) return null;

    rangeHeader = rangeHeader.removeWhitespace();
    if (!rangeHeader.startsWith(rangeHeaderPrefix)) {
      return null;
    }
    final rangeValue = rangeHeader.substring(rangeHeaderPrefix.length);
    if (rangeValue.startsWith('-')) {
      //Currently not supporting negative ranges in requests
      throw RangeError('Negative ranges are not supported in HttpRangeRequest');
    }
    final rangeParts = rangeValue.split('-');
    if (rangeParts.length != 2) {
      return null;
    }
    final int? start = int.tryParse(rangeParts[0]);
    if (start == null) return null;
    final int? end = int.tryParse(rangeParts[1]);
    return HttpRangeRequest(start, end);
  }

  /// Creates a [HttpRangeRequest] from an exclusive end range by converting it to inclusive.
  /// For example: if given start=0, end=100 (exclusive), creates a range of 0-99 (inclusive).
  factory HttpRangeRequest.inclusive(int start, int? end) {
    return HttpRangeRequest(
      start,
      end == null ? null : end - 1,
    );
  }

  static const rangeHeaderPrefix = 'bytes=';

  String get header {
    return '$rangeHeaderPrefix$start-${end ?? ""}';
  }

  @override
  String toString() {
    return 'HttpRangeRequest: start: $start, end: $end';
  }
}
