import 'dart:async';

import 'package:http_cache_stream/http_cache_stream.dart';

import '../../cache_stream/response_streams/buffered_data_stream.dart';

/// A stream response that buffers data from the cache download stream and serves it according to the specified range.
class CacheDownloadStreamResponse extends StreamResponse {
  final BufferedDataStream _stream;
  CacheDownloadStreamResponse._(super.range, super.responseHeaders, this._stream);

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
        range: range,
        dataStream: dataStream,
        dataStreamPosition: dataStreamPosition,
        sourceLength: responseHeaders.sourceLength,
        streamConfig: streamConfig,
      ),
    );
  }

  @override
  void cancel() {
    _stream.cancel();
  }

  @override
  ResponseSource get source => ResponseSource.cacheDownload;

  @override
  Stream<List<int>> get stream => _stream;
}
