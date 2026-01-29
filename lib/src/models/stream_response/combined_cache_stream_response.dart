import 'dart:async';

import 'package:http_cache_stream/http_cache_stream.dart';

import '../../cache_stream/response_streams/combined_data_stream.dart';

/// A stream that combines data from the partial cache file and the cache download stream.
/// It first streams data from the partial cache file, and once the file is done, it switches to the download stream.
/// Upon initalization, immediately starts buffering data from the download stream.
class CombinedCacheStreamResponse extends StreamResponse {
  final CombinedDataStream _stream;
  CombinedCacheStreamResponse._(super.range, super.responseHeaders, this._stream);

  factory CombinedCacheStreamResponse.construct(
    final IntRange range,
    final CachedResponseHeaders responseHeaders,
    final CacheFiles cacheFiles,
    final Stream<List<int>> dataStream,
    final int dataStreamPosition,
    final StreamCacheConfig streamConfig,
  ) {
    final combinedDataStream = CombinedDataStream(
      range,
      cacheFiles,
      dataStream,
      dataStreamPosition,
      responseHeaders.sourceLength,
      streamConfig,
    );
    return CombinedCacheStreamResponse._(range, responseHeaders, combinedDataStream);
  }

  @override
  void cancel() => _stream.cancel(const StreamResponseCancelledException());

  @override
  ResponseSource get source => ResponseSource.combined;

  @override
  Stream<List<int>> get stream => _stream;
}
