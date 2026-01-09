import 'package:http/http.dart';

abstract interface class CacheConfiguration {
  ///Custom headers to be sent when downloading cache.
  Map<String, String> get requestHeaders;

  ///Custom headers to add to every cached HTTP response.
  Map<String, String> get responseHeaders;
  set requestHeaders(Map<String, String> requestHeaders);
  set responseHeaders(Map<String, String> responseHeaders);

  ///When true, copies [CachedResponseHeaders] to [responseHeaders].
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

  ///The maximum amount of data to buffer in memory per cache response stream
  ///
  ///Default is 25 MB.
  int get maxBufferSize;
  set maxBufferSize(int value);

  /// The preferred minimum size of chunks emitted from the cache download stream.
  /// Network data is buffered until reaching this size before being emitted downstream.
  /// Larger values improve I/O efficiency at the cost of increased memory usage.
  ///
  /// Default is 64 KB.
  int get minChunkSize;
  set minChunkSize(int value);

  /// The HTTP client used to download cache.
  Client get httpClient;

  ///Whether to save all response headers in the cached response metadata.
  ///
  ///When false, only essential headers are saved. This can reduce metadata size, but may omit headers needed for certain use cases.
  ///
  ///Default is true.
  bool get saveAllHeaders;
  set saveAllHeaders(bool value);

  /// When false, deletes partial cache files (including metadata) when a http cache stream is disposed before cache is complete.
  /// Default is true.
  bool get savePartialCache;
  set savePartialCache(bool value);

  /// When false, deletes the metadata file after the cache is complete.
  /// Metadata is always saved for incomplete cache files when [savePartialCache] is true, so the download can be resumed.
  /// This value should only be set to false if you have no intention of creating a cache stream for the cache file again.
  bool get saveMetadata;
  set saveMetadata(bool value);

  /// The delay between retry attempts when a download fails.
  Duration get retryDelay;
  set retryDelay(Duration value);

  /// The timeout duration for queued cache requests. Requests that are not fulfilled within this duration will throw a timeout exception.
  ///
  /// Default is 30 seconds.
  Duration get cacheRequestTimeout;
  set cacheRequestTimeout(Duration value);

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
