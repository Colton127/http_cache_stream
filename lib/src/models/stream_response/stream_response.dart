import 'dart:async';
import 'dart:io';

import 'package:http_cache_stream/http_cache_stream.dart';

import 'cache_download_stream_response.dart';
import 'combined_stream_response.dart';
import 'download_stream_response.dart';
import 'empty_stream_response.dart';
import 'file_stream_response.dart';

abstract class StreamResponse {
  final IntRange range;
  final CachedResponseHeaders sourceHeaders;
  const StreamResponse(this.range, this.sourceHeaders);
  Stream<List<int>> get stream;
  ResponseSource get source;
  int? get sourceLength => sourceHeaders.sourceLength;

  static Future<StreamResponse> fromDownload(
    final Uri url,
    final IntRange range,
    final StreamCacheConfig config,
  ) {
    return DownloadStreamResponse.construct(url, range, config);
  }

  factory StreamResponse.fromFile(
    final IntRange range,
    final File file,
    final CachedResponseHeaders headers,
  ) {
    if (range.isEmptyAt(headers.sourceLength)) {
      return EmptyCacheStreamResponse(range, headers);
    } else {
      return FileStreamResponse(file, range, headers);
    }
  }

  factory StreamResponse.fromStream(
    final IntRange range,
    final CachedResponseHeaders headers,
    final Stream<List<int>> dataStream,
    final int dataStreamPosition,
    final StreamCacheConfig streamConfig,
  ) {
    if (range.isEmptyAt(headers.sourceLength)) {
      return EmptyCacheStreamResponse(range, headers);
    } else if (dataStreamPosition > range.start) {
      throw RangeError.range(
        range.start,
        0,
        dataStreamPosition,
        'dataStreamPosition',
        'Data stream position must be at or before the start of the range.',
      );
    } else {
      return CacheDownloadStreamResponse(
        range,
        headers,
        dataStream: dataStream,
        dataStreamPosition: dataStreamPosition,
        streamConfig: streamConfig,
      );
    }
  }

  factory StreamResponse.fromFileAndStream(
    final IntRange range,
    final CachedResponseHeaders headers,
    final File partialCacheFile,
    final Stream<List<int>> dataStream,
    final int dataStreamPosition,
    final StreamCacheConfig streamConfig,
  ) {
    final effectiveEnd = range.end ?? headers.sourceLength;
    if (effectiveEnd != null && dataStreamPosition >= effectiveEnd) {
      //We can fully serve the request from the file
      return StreamResponse.fromFile(
        range,
        partialCacheFile,
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
      );
    } else {
      return CombinedCacheStreamResponse(
        range,
        headers,
        partialCacheFile,
        dataStream,
        dataStreamPosition,
        streamConfig,
      );
    }
  }

  factory StreamResponse.empty(
    final IntRange range,
    final CachedResponseHeaders headers,
  ) {
    return EmptyCacheStreamResponse(range, headers);
  }

  ///The length of the content in the response. This may be different from the source length.
  int? get contentLength {
    final effectiveEnd = this.effectiveEnd;
    if (effectiveEnd == null) return null;
    return effectiveEnd > effectiveStart ? effectiveEnd - effectiveStart : 0;
  }

  ///The effective end of the response. If no end is specified, this will be the source length.
  int? get effectiveEnd {
    return range.end ?? sourceLength;
  }

  int get effectiveStart {
    return range.start;
  }

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
  ///A stream response that contains no data.
  ///This is an acceptable response for requests for which there is no data to serve. For example, requests at the end of a file, or HEAD requests.
  empty,

  ///A stream response that is served from an independent download stream.
  ///This is separate download stream from the active cache download stream, and is used to fulfill range requests starting beyond the active cache position.
  download,

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
