import 'package:http_cache_stream/src/models/http_range/http_range_request.dart';

///A class that represents a range of exclusive integers
class IntRange {
  final int start;
  final int? end;
  const IntRange([this.start = 0, this.end]) : upperBound = end ?? start;
  final int upperBound;

  static IntRange full() => const IntRange(0);

  ///Constructs an IntRange with validation.
  static IntRange validate(int? start, int? end, int? max) {
    start = start == null ? 0 : RangeError.checkNotNegative(start, 'start');
    if (start == 0 && end == null) {
      return IntRange.full();
    }
    if (end != null && start > end) {
      throw RangeError.range(end, start, null, 'end');
    }
    if (max != null) {
      if (start > max) {
        throw RangeError.range(start, 0, max, 'start');
      }
      if (end != null && end > max) {
        throw RangeError.range(end, start, max, 'end');
      }
    }
    return IntRange(start, end);
  }

  bool exceeds(int value) {
    return upperBound > value;
  }

  int? get range {
    if (end == null) return null;
    return end! - start;
  }

  bool get isFull => start == 0 && end == null;
  bool get isEmpty => start == end;

  HttpRangeRequest get rangeRequest => HttpRangeRequest.inclusive(start, end);

  @override
  String toString() => 'IntRange($start, $end)';

  @override
  bool operator ==(Object other) => other is IntRange && start == other.start && end == other.end;

  @override
  int get hashCode => start.hashCode ^ end.hashCode;
}
