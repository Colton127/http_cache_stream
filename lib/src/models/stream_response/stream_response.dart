import 'dart:async';

import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:http_cache_stream/src/models/stream_response/combined_cache_stream_response.dart';

import 'cache_download_stream_response.dart';
import 'file_stream_response.dart';
import 'head_stream_response.dart';
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

  factory StreamResponse.fromStream(
    final IntRange range,
    final CachedResponseHeaders headers,
    final Stream<List<int>> dataStream,
    final int dataStreamPosition,
    final StreamCacheConfig streamConfig,
    final CacheFiles cacheFiles,
  ) {
    return CacheDownloadStreamResponse(
      range,
      headers,
      dataStream: dataStream,
      dataStreamPosition: dataStreamPosition,
      streamConfig: streamConfig,
      cacheFiles: cacheFiles,
    );
  }

  factory StreamResponse.fromFileAndStream(
    final IntRange range,
    final CachedResponseHeaders headers,
    final CacheFiles cacheFiles,
    final Stream<List<int>> dataStream,
    final int dataStreamPosition,
    final StreamCacheConfig streamConfig,
  ) {
    final effectiveEnd = range.end ?? headers.sourceLength;
    if (effectiveEnd != null && dataStreamPosition >= effectiveEnd) {
      //We can fully serve the request from the file
      return StreamResponse.fromFile(
        range,
        cacheFiles,
        headers,
      );
    } else if (range.start >= dataStreamPosition) {
      //We can fully serve the request from the cache stream
      return StreamResponse.fromStream(
        range,
        headers,
        dataStream,
        dataStreamPosition,
        streamConfig,
        cacheFiles,
      );
    } else {
      return CombinedCacheStreamResponse.construct(
        range,
        headers,
        cacheFiles,
        dataStream,
        dataStreamPosition,
        streamConfig,
      );
    }
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

  bool get isPartial {
    return contentLength != null && contentLength! < sourceLength!;
  }

  ///If the returned [stream] contains no data.
  ///This is always true for [HeaderStreamResponse], even if the specified [range] is not empty.
  bool get isEmpty {
    return contentLength == 0;
  }

  void cancel();

  @override
  String toString() {
    return 'StreamResponse{range: $range, source: $source contentLength: $contentLength, sourceLength: $sourceLength}';
  }
}

enum ResponseSource {
  ///The response is served exclusively from cached headers
  /// without any body data. Typically used for HEAD requests.
  headersOnly,

  ///A stream response used to fulfill range requests that exceed [rangeRequestSplitThreshold].
  ///This is an independent download stream from the source URL.
  rangeDownload,

  ///A stream response that is served exclusively from cached data saved to a file.
  cacheFile,

  ///A stream response that is served exclusively from the cache download stream.
  ///
  ///Data from the cache download stream is buffered until a listener is added. The stream must be read to completion or cancelled to release buffered data. If you no longer need the stream, you must manually call [cancel] to avoid memory leaks.
  cacheDownload,

  ///A stream response that combines [cacheFile] and [cacheDownload] sources. When a listener is added, data is streamed from the cache file first, and once the file stream is done, it switches to the cache download stream.
  ///
  ///Data from the cache download stream is buffered until a listener is added. The stream must be read to completion or cancelled to release buffered data. If you no longer need the stream, you must manually call [cancel] to avoid memory leaks.
  combined,
}
