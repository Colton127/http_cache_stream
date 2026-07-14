import 'dart:async';

import '../../cache_stream/cache_downloader/partial_cache_feed.dart';
import '../../cache_stream/response_streams/partial_cache_file_stream.dart';
import '../cache_files/cache_files.dart';
import '../exceptions/stream_response_exceptions.dart';
import '../metadata/cached_response_headers.dart';
import '../stream_requests/int_range.dart';
import 'stream_response.dart';
import 'stream_response_range.dart';

/// A stream response served by following the partial cache file on disk as an
/// active download flushes data to it.
///
/// Data already on disk is streamed immediately; data still downloading is
/// streamed as soon as it is flushed. Nothing is buffered in memory, so the
/// response tolerates arbitrarily slow or paused consumers.
class PartialCacheStreamResponse extends StreamResponse {
  final PartialCacheFileStream _stream;
  @override
  final ResponseSource source;
  PartialCacheStreamResponse._(
      super.range, super.responseHeaders, this._stream, this.source);

  factory PartialCacheStreamResponse.construct(
    final IntRange range,
    final CachedResponseHeaders responseHeaders,
    final CacheFiles cacheFiles,
    final PartialCacheFeed feed, {
    required final ResponseSource source,
  }) {
    assert(
        source == ResponseSource.cacheDownload ||
            source == ResponseSource.combined,
        'PartialCacheStreamResponse: invalid source: $source');
    return PartialCacheStreamResponse._(
      range,
      responseHeaders,
      PartialCacheFileStream(
        range: StreamRange(range, responseHeaders.sourceLength), //Validate range
        cacheFiles: cacheFiles,
        feed: feed,
      ),
      source,
    );
  }

  @override
  void cancel() => _stream.cancel(const StreamResponseCancelledException());

  @override
  Stream<List<int>> get stream => _stream;
}
