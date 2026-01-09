import 'dart:async';

import 'package:http_cache_stream/http_cache_stream.dart';

import '../../cache_stream/response_streams/download_stream.dart';

class DownloadStreamResponse extends StreamResponse {
  final DownloadStream _downloadStream;
  const DownloadStreamResponse._(super.range, super.responseHeaders, this._downloadStream);

  static Future<DownloadStreamResponse> construct(final Uri url, final IntRange range, final StreamCacheConfig config) async {
    final downloadStream = await DownloadStream.open(
      url,
      range,
      config.httpClient,
      config.combinedRequestHeaders(),
    );
    return DownloadStreamResponse._(
      range,
      downloadStream.responseHeaders,
      downloadStream,
    );
  }

  @override
  Stream<List<int>> get stream => _downloadStream;

  @override
  ResponseSource get source => ResponseSource.download;

  @override
  void cancel() => _downloadStream.cancel();
}
