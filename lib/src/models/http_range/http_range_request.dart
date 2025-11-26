import 'http_range.dart';

class HttpRangeRequest extends HttpRange {
  const HttpRangeRequest._(super.start, super.end);

  static HttpRangeRequest? parse(final String? rangeHeader) {
    if (rangeHeader == null || rangeHeader.isEmpty) return null;
    final (int? start, int? end, int? sourceLength) = HttpRange.parse(
      rangeHeader,
    );
    if (start == null) return null;
    return HttpRangeRequest._(start, end);
  }

  /// Creates a [HttpRangeRequest] from an exclusive end range by converting it to inclusive.
  /// For example: if given start=0, end=100 (exclusive), creates a range of 0-99 (inclusive).
  factory HttpRangeRequest.inclusive(int start, int? end) {
    return HttpRangeRequest._(start, end == null ? null : end - 1);
  }

  String get header {
    return 'bytes=$start-${end ?? ""}';
  }

  @override
  String toString() {
    return 'HttpRangeRequest: $start: $start, end: $end';
  }
}
