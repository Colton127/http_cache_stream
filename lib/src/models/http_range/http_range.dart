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

  ///Attempts to parse both range requests and range response header
  static (int? start, int? end, int? sourceLength) parse(String rangeHeader) {
    var (int? start, int? end, int? sourceLength) = (null, null, null);
    if (rangeHeader.startsWith('bytes')) {
      rangeHeader = rangeHeader.replaceAll(
        RegExp(r'[^0-9/-]'),
        '',
      ); // Clean the header to just numbers and separators
      if (rangeHeader.isNotEmpty) {
        final parts = rangeHeader.split('/');
        sourceLength = _parseIntFromList(parts, 1);
        final rangeStr = parts.first;
        if (rangeStr.isNotEmpty) {
          if (rangeStr.startsWith('-')) {
            //Attempt to Handle negative range (e.g. bytes=-500)
            final suffixLength = int.tryParse(rangeStr.substring(1));
            if (suffixLength != null &&
                suffixLength >= 0 &&
                sourceLength != null &&
                sourceLength > suffixLength) {
              start = sourceLength - suffixLength;
              end = sourceLength - 1;
            }
          } else {
            final rangeParts = rangeStr.split('-');
            start = _parseIntFromList(rangeParts, 0);
            if (start != null) {
              end = _parseIntFromList(rangeParts, 1);
              if (end != null &&
                  (end < start ||
                      (sourceLength != null && end >= sourceLength))) {
                end = null; // Reset end if invalid
              }
            }
          }
        }
      }
    }
    return (start, end, sourceLength);
  }

  /// The end byte position (exclusive).
  int? get endEx => end != null ? end! + 1 : null;

  int? get effectiveEnd => endEx ?? sourceLength;

  /// Gets content length of the range
  int? get contentLength {
    final effectiveEnd = this.effectiveEnd;
    if (effectiveEnd == null) return null;
    return effectiveEnd - start;
  }

  bool get isFull {
    return start == 0 && (end == null || endEx == sourceLength);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HttpRange &&
        start == other.start &&
        end == other.end &&
        sourceLength == other.sourceLength;
  }

  @override
  int get hashCode => start.hashCode ^ end.hashCode ^ sourceLength.hashCode;
}

int? _parseIntFromList(List<String> list, int index) {
  if (index >= list.length || list[index].isEmpty) return null;
  final result = int.tryParse(list[index]);
  return result != null && result.isFinite
      ? result
      : null; // Ensure the number is finite
}
