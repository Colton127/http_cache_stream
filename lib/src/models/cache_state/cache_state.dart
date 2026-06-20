sealed class CacheState {
  const CacheState();

  const factory CacheState.zero() = IncompleteCacheState.zero;

  const factory CacheState.incomplete(int position, int? sourceLength) =
      IncompleteCacheState;

  const factory CacheState.complete(int sourceLength) = CompleteCacheState;

  /// Bytes currently available in the cache (downloaded or on disk).
  /// For an active download, this may be ahead of the current read position. For a completed cache, this will match [sourceLength].
  int get position;

  /// Total source size in bytes, or null if the server hasn't reported it yet.
  int? get sourceLength;

  /// Whether the cache file has been fully downloaded and finalized (renamed).
  bool get isComplete;

  /// Progress from 0.0 to 1.0.
  ///
  /// Returns null when [sourceLength] is unknown.
  /// Returns exactly 1.0 only when the complete file is available on disk. Even if [position] has advanced to match [sourceLength], [progress] will still be less than 1.0 until the file is finalized, at which point a [CompleteCacheState] will be emitted.
  double? get progress;

  /// Bytes remaining until the download is complete.
  /// Null when [sourceLength] is unknown.
  int? get remainingBytes;

  @override
  String toString() =>
      'CacheState(position: $position, sourceLength: $sourceLength, isComplete: $isComplete)';
}

/// Cache state while a download is in progress, paused, or not yet started.
final class IncompleteCacheState extends CacheState {
  const IncompleteCacheState(this.position, this.sourceLength);

  const IncompleteCacheState.zero() : this(0, null);

  @override
  final int position;

  @override
  final int? sourceLength;

  @override
  bool get isComplete => false;

  /// Capped at [maxProgress] — strictly less than 1.0 — because the cache
  /// file is not yet finalized regardless of how far [position] has advanced.
  @override
  double? get progress {
    final length = sourceLength;
    if (length == null || length == 0) return null;
    return (position / length).clamp(0.0, maxProgress);
  }

  @override
  int? get remainingBytes {
    final length = sourceLength;
    if (length == null) return null;
    return (length - position).clamp(0, length);
  }

  /// The maximum value [progress] will ever return for an incomplete state.
  /// Progress only reaches 1.0 once [CompleteCacheState] is emitted.
  static const double maxProgress = 0.99;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is IncompleteCacheState &&
        position == other.position &&
        sourceLength == other.sourceLength;
  }

  @override
  int get hashCode => Object.hash(position, sourceLength);
}

/// Cache state once the file has been fully downloaded and renamed into place.
final class CompleteCacheState extends CacheState {
  const CompleteCacheState(this.sourceLength);

  @override
  final int sourceLength;

  @override
  int get position => sourceLength;

  @override
  bool get isComplete => true;

  @override
  double get progress => 1.0;

  @override
  int get remainingBytes => 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CompleteCacheState && sourceLength == other.sourceLength;
  }

  @override
  int get hashCode => sourceLength.hashCode;
}
