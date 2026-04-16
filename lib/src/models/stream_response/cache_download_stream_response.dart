import 'dart:async';

import '../../cache_stream/response_streams/buffered_data_stream.dart';
import '../cache_config/stream_cache_config.dart';
import '../exceptions/stream_response_exceptions.dart';
import '../metadata/cached_response_headers.dart';
import '../stream_requests/int_range.dart';
import 'stream_response.dart';
import 'stream_response_range.dart';

/// A stream response that buffers data from the cache download stream and serves it according to the specified range.
class CacheDownloadStreamResponse extends StreamResponse {
  final BufferedDataStream _stream;
  CacheDownloadStreamResponse._(
      super.range, super.responseHeaders, this._stream);

  factory CacheDownloadStreamResponse(
    final IntRange range,
    final CachedResponseHeaders responseHeaders, {
    required final Stream<List<int>> dataStream,
    required final int dataStreamPosition,
    required final StreamCacheConfig streamConfig,
  }) {
    return CacheDownloadStreamResponse._(
      range,
      responseHeaders,
      BufferedDataStream(
        range: StreamRange(range, responseHeaders.sourceLength),
        dataStream: dataStream,
        dataStreamPosition: dataStreamPosition,
        streamConfig: streamConfig,
      ),
    );
  }

  @override
  void cancel() => _stream.cancel(const StreamResponseCancelledException());

  @override
  ResponseSource get source => ResponseSource.cacheDownload;

  @override
  Stream<List<int>> get stream => _stream;
}
