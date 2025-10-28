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
  /// Default value is 5 MB.
  int? get rangeRequestSplitThreshold;
  set rangeRequestSplitThreshold(int? value);

  ///The maximum amount of data to buffer in memory before writing to disk during a download.
  ///Once this limit is reached, the cache stream will flush the buffer to disk. However, the download will continue to buffer more data. The download stream will only be paused if it is receiving more data than it can write to disk. As a result, the theoretical maximum memory usage of a cache download is double this value.
  ///Default value is 25MB.
  int get maxBufferSize;
  set maxBufferSize(int value);

  /// The preferred minimum size of chunks emitted from the cache download stream.
  /// Network data is buffered until reaching this size before being emitted downstream.
  /// Larger values improve I/O efficiency and performance at the cost of increased memory usage.
  /// Default value is 128KB.
  int get minChunkSize;
  set minChunkSize(int value);

  /// The HTTP client used to download cache.
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
