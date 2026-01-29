import '../../../http_cache_stream.dart';

///A class that represents a stream range with effective end validation.
///Used to ensure that the requested range does not exceed the source length.
class StreamRange {
  final IntRange range;
  final int? sourceLength;
  const StreamRange._(this.range, this.sourceLength);

  factory StreamRange(IntRange range, int? sourceLength) {
    if (sourceLength != null && range.upperBound > sourceLength) {
      throw RangeError.range(range.upperBound, 0, sourceLength, 'range end');
    }

    return StreamRange._(range, sourceLength);
  }

  factory StreamRange.construct(int? start, int? end, int? sourceLength) {
    final validatedRange = IntRange.validate(start, end, sourceLength);
    return StreamRange._(validatedRange, sourceLength);
  }

  int get start => range.start;
  int? get end => range.end;
  int? get absoluteEnd => range.end ?? sourceLength;

  @override
  String toString() => 'StreamRange(start: $start, end: $end, sourceLength: $sourceLength)';
}
