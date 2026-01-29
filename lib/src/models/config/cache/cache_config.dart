import 'package:flutter/foundation.dart';
import 'package:http/http.dart';

abstract interface class CacheConfiguration {
  ///Custom headers to be sent when downloading cache.
  Map<String, String> get requestHeaders;

  ///Custom headers to add to every cached HTTP response.
  Map<String, String> get responseHeaders;
  set requestHeaders(Map<String, String> requestHeaders);
  set responseHeaders(Map<String, String> responseHeaders);

  ///When true, copies all [CachedResponseHeaders] from the cached response when serving a cached response.
  ///
  ///Default is false.
  bool get copyCachedResponseHeaders;
  set copyCachedResponseHeaders(bool value);

  ///When true, validates the cache against the server when the cache is outdated.
  ///
  ///Default is false.
  bool get validateOutdatedCache;
  set validateOutdatedCache(bool value);

  /// The minimum number of bytes that must exist between the current download position
  /// and a range request's start position before creating a separate download stream.
  /// Set to null to disable separate range downloads.
  ///
  /// Default is null.
  int? get rangeRequestSplitThreshold;
  set rangeRequestSplitThreshold(int? value);

  ///The maximum amount of data (in bytes) to buffer in memory.
  ///If an ongoing cache download is receiving data faster than it can be written to disk, and the buffer exceeds this size, the download will be paused until the buffer is flushed to disk.
  ///If a response stream is receiving data faster than it can be consumed, and the buffer exceeds this size, then the stream will be cancelled with an exception.
  ///Default is 25MB.
  int get maxBufferSize;
  set maxBufferSize(int value);

  /// The preferred minimum size of chunks emitted from the cache download stream.
  /// Network data is buffered until reaching this size before being emitted downstream.
  /// Larger values improve I/O efficiency at the cost of increased memory usage.
  /// Default value is 64KB.
  int get minChunkSize;
  set minChunkSize(int value);

  /// The HTTP client used to download cache.
  @internal
  Client get httpClient;

  /// When false, deletes partial cache files (including metadata) when a http cache stream is disposed before cache is complete.
  /// Default is true.
  bool get savePartialCache;
  set savePartialCache(bool value);

  /// When false, deletes the metadata file after the cache is complete.
  /// Metadata is always saved for incomplete cache files when [savePartialCache] is true, so the download can be resumed.
  /// This value should only be set to false if you have no intention of creating a cache stream for the cache file again.
  /// Default is true.
  bool get saveMetadata;
  set saveMetadata(bool value);

  /// The timeout duration between reads for both requests and responses.
  /// Note that this applies to paused requests to prevent them from hanging indefinitely.
  /// If no data is received within this duration, the connection will be closed.
  /// Default is 30 seconds.
  Duration get readTimeout;
  set readTimeout(Duration value);

  /// The delay duration before retrying a failed download.
  /// Default is 5 seconds.
  Duration get retryDelay;
  set retryDelay(Duration value);

  ///Whether to save all response headers in the cached response metadata.
  ///
  ///When false, only essential headers required for cache responses and validation are saved.
  ///
  ///Default is true.
  bool get saveAllHeaders;
  set saveAllHeaders(bool value);

  static int? validateRangeRequestSplitThreshold(int? value) {
    if (value == null) return null;
    return RangeError.checkNotNegative(value, 'RangeRequestSplitThreshold');
  }

  static int validateMaxBufferSize(int value) {
    const minValue = 1024 * 1024 * 1; // 1MB
    if (value < minValue) {
      throw RangeError.range(value, minValue, null, 'maxBufferSize');
    }
    return value;
  }

  static int validateMinChunkSize(int value) {
    return RangeError.checkNotNegative(value, 'minChunkSize');
  }
}
