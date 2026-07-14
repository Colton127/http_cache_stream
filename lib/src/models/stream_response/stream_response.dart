import 'dart:async';

import '../../cache_stream/cache_downloader/partial_cache_feed.dart';
import '../cache_config/stream_cache_config.dart';
import '../cache_files/cache_files.dart';
import '../metadata/cached_response_headers.dart';
import '../stream_requests/int_range.dart';
import 'file_stream_response.dart';
import 'header_stream_response.dart';
import 'partial_cache_stream_response.dart';
import 'range_download_stream_response.dart';

/// Represents a response from the cache manager.
abstract class StreamResponse {
  /// The byte range of the response.
  final IntRange range;

  /// The headers of the source response.
  final CachedResponseHeaders sourceHeaders;
  const StreamResponse(this.range, this.sourceHeaders);

  /// The stream of data for this response.
  Stream<List<int>> get stream;

  /// The source of the response (cache, download, or combined).
  ResponseSource get source;

  /// The total length of the source content, if known.
  int? get sourceLength => sourceHeaders.sourceLength;

  factory StreamResponse.headersOnly(
    final IntRange range,
    final CachedResponseHeaders responseHeaders,
  ) {
    return HeaderStreamResponse(range, responseHeaders);
  }

  /// Creates a [StreamResponse] from a remote download.
  static Future<StreamResponse> fromDownload(
    final Uri url,
    final IntRange range,
    final StreamCacheConfig config,
  ) {
    return RangeDownloadStreamResponse.construct(url, range, config);
  }

  /// Creates a [StreamResponse] from a cached file.
  factory StreamResponse.fromFile(
    final IntRange range,
    final CacheFiles cacheFiles,
    final CachedResponseHeaders responseHeaders,
  ) {
    return FileStreamResponse(range, cacheFiles, responseHeaders);
  }

  /// Creates a [StreamResponse] served from the partial cache file of an
  /// active download, following the file on disk as data is flushed to it.
  factory StreamResponse.fromPartialCache(
    final IntRange range,
    final CachedResponseHeaders headers,
    final CacheFiles cacheFiles,
    final PartialCacheFeed feed, {
    required final ResponseSource source,
  }) {
    return PartialCacheStreamResponse.construct(
      range,
      headers,
      cacheFiles,
      feed,
      source: source,
    );
  }

  ///The length of the content in the response. This may be different from the source length.
  int? get contentLength {
    final effectiveEnd = this.effectiveEnd;
    if (effectiveEnd == null) return null;
    return effectiveEnd - effectiveStart;
  }

  ///The effective end of the response. If no end is specified, this will be the source length.
  int? get effectiveEnd {
    return range.end ?? sourceLength;
  }

  int get effectiveStart {
    return range.start;
  }

  bool get isPartial => !isFull;

  bool get isFull {
    return range.start == 0 && (range.end == null || range.end == sourceLength);
  }

  bool get isEmpty {
    return effectiveStart == effectiveEnd;
  }

  void cancel();

  @override
  String toString() {
    return 'StreamResponse{range: $range, source: $source contentLength: $contentLength, sourceLength: $sourceLength}';
  }
}

enum ResponseSource {
  /// A [StreamResponse] that contains an empty data stream
  /// Typically used to complete HEAD requests, where no body data is expected.
  headerOnly,

  ///A stream response used to fulfill range requests that exceed [rangeRequestSplitThreshold].
  ///This is an independent download stream from the source URL.
  rangeDownload,

  ///A stream response that is served exclusively from cached data saved to a file.
  cacheFile,

  ///A stream response for a range at or beyond the current download position.
  ///Data is served by following the partial cache file on disk as the download flushes to it, so nothing is buffered in memory and slow consumers are fully supported.
  ///
  ///The stream must be read to completion or cancelled to release its file handle. If you no longer need the stream, call [cancel].
  cacheDownload,

  ///A stream response for a range that begins within already-cached data and extends into the active download. Served identically to [cacheDownload]: by following the partial cache file on disk.
  ///
  ///The stream must be read to completion or cancelled to release its file handle. If you no longer need the stream, call [cancel].
  combined,
}
