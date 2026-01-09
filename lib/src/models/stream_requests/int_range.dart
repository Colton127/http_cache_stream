import 'package:http_cache_stream/src/models/http_range/http_range_request.dart';

///A class that represents a range of exclusive integers, used for stream ranges.
class IntRange {
  final int start;
  final int? end;
  const IntRange([this.start = 0, this.end]) : assert(start >= 0 && (end == null || end >= start));

  static IntRange full() => const IntRange(0);

  ///Constructs an IntRange with validation.
  ///Prefers to use this method instead of the constructor directly to ensure valid ranges.
  static IntRange validate(int? start, int? end, [int? max]) {
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
    return rangeMax > value;
  }

  bool isEmptyAt(int? maxValue) {
    if (maxValue != null && rangeMax > maxValue) {
      throw RangeError.range(rangeMax, 0, maxValue, 'rangeMax');
    }
    return start == (end ?? maxValue);
  }

  int get rangeMax => end ?? start;

  int? get range {
    if (end == null) return null;
    return end! - start;
  }

  bool get isFull => start == 0 && end == null;
  bool get isEmpty => start == end;

  HttpRangeRequest get rangeRequest => HttpRangeRequest.inclusive(start, end);

  IntRange copyWith({int? start, int? end}) {
    return IntRange.validate(start ?? this.start, end ?? this.end);
  }

  @override
  String toString() => 'IntRange($start, $end)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is IntRange && start == other.start && end == other.end;
  }

  @override
  int get hashCode => start.hashCode ^ end.hashCode;
}
