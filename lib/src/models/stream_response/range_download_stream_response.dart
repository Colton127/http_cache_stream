import 'dart:async';

import '../../cache_stream/response_streams/download_stream.dart';
import '../../etc/chunked_bytes_buffer.dart';
import '../cache_config/stream_cache_config.dart';
import '../stream_requests/int_range.dart';
import 'stream_response.dart';

class RangeDownloadStreamResponse extends StreamResponse {
  final DownloadStream _downloadStream;
  final int _minChunkSize;
  const RangeDownloadStreamResponse._(super.range, super.responseHeaders,
      this._downloadStream, this._minChunkSize);

  static Future<RangeDownloadStreamResponse> construct(
    final Uri url,
    final IntRange range,
    final StreamCacheConfig config,
  ) async {
    final downloadStream = await DownloadStream.open(url, range, config);
    return RangeDownloadStreamResponse._(
      range,
      downloadStream.responseHeaders,
      downloadStream,
      config.minChunkSize,
    );
  }

  @override
  Stream<List<int>> get stream {
    // Wrap the download stream with a chunked bytes transformer to ensure minimum chunk size.
    return _downloadStream.transform(ChunkedBytesTransformer(_minChunkSize));
  }

  @override
  void cancel() => _downloadStream.cancel();

  @override
  ResponseSource get source => ResponseSource.rangeDownload;
}
