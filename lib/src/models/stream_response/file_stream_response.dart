import 'dart:async';

import '../../cache_stream/response_streams/cache_file_stream.dart';
import '../cache_files/cache_files.dart';
import '../metadata/cached_response_headers.dart';
import '../stream_requests/int_range.dart';
import 'stream_response.dart';
import 'stream_response_range.dart';

class FileStreamResponse extends StreamResponse {
  final CacheFileStream _stream;
  const FileStreamResponse._(this._stream, super.range, super.responseHeaders);

  factory FileStreamResponse(
    final IntRange range,
    final CacheFiles cacheFiles,
    final CachedResponseHeaders responseHeaders,
  ) {
    final streamRange =
        StreamRange(range, responseHeaders.sourceLength); //Validate range
    return FileStreamResponse._(
      CacheFileStream(streamRange, cacheFiles),
      range,
      responseHeaders,
    );
  }

  @override
  Stream<List<int>> get stream => _stream;
  @override
  ResponseSource get source => ResponseSource.cacheFile;

  @override
  void cancel() {
    // No need to close the file stream, it's created on-demand and closed after use.
  }
}
