abstract class HttpRange {
  final int start;
  final int? end;
  final int? sourceLength;

  const HttpRange(this.start, this.end, {this.sourceLength})
      : assert(start >= 0, 'start must be null or non-negative'),
        assert(
          end == null || (end >= start),
          'end must be null or greater than or equal to start (start: $start, end: $end, sourceLength: $sourceLength)',
        );

  static void validate(int start, int? end, [int? sourceLength]) {
    RangeError.checkNotNegative(start, 'start');

    if (end != null && start > end) {
      throw RangeError.range(end, start, null, 'end', 'End must be >= start');
    }

    if (sourceLength != null) {
      if (start >= sourceLength) {
        throw RangeError.range(start, 0, sourceLength - 1, 'start', 'Start must be < sourceLength');
      }

      if (end != null && end >= sourceLength) {
        throw RangeError.range(end, start, sourceLength - 1, 'end', 'End must be < sourceLength');
      }
    }
  }

  ///Validates if two ranges are equal
  static bool isEqual(HttpRange previous, HttpRange next) {
    if (previous.start != next.start) {
      return false;
    }
    if (previous.end != null && next.end != null) {
      if (previous.end != next.end) return false;
    }
    if (previous.sourceLength != null && next.sourceLength != null) {
      if (previous.sourceLength != next.sourceLength) return false;
    }
    return true;
  }

  /// The end byte position (exclusive).
  int? get endEx => end != null ? end! + 1 : null;

  int? get effectiveEnd => endEx ?? sourceLength;

  /// Gets content length of the range
  int? get contentLength {
    final effectiveEnd = this.effectiveEnd;
    if (effectiveEnd == null) return null;
    return effectiveEnd > start ? effectiveEnd - start : 0;
  }

  bool get isFull {
    return start == 0 && (end == null || endEx == sourceLength);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HttpRange && start == other.start && end == other.end && sourceLength == other.sourceLength;
  }

  @override
  int get hashCode => start.hashCode ^ end.hashCode ^ sourceLength.hashCode;
}

int? parseIntFromList(List<String> list, int index) {
  if (index >= list.length || list[index].isEmpty) return null;
  return int.tryParse(list[index]);
}
