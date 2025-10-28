import 'dart:async';
import 'dart:io';

import 'package:http/http.dart';
import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:http_cache_stream/src/etc/exceptions.dart';
import 'package:http_cache_stream/src/models/http_range/http_range_response.dart';

class DownloadStreamResponse extends StreamResponse {
  final DownloadStream _downloadStream;
  const DownloadStreamResponse._(super.range, this._downloadStream);

  static Future<DownloadStreamResponse> construct(final Uri url,
      final IntRange range, final StreamCacheConfig config) async {
    final downloadStream = await DownloadStream.open(
      url,
      range,
      config.httpClient,
      config.combinedRequestHeaders(),
    );
    return DownloadStreamResponse._(range, downloadStream);
  }

  @override
  Stream<List<int>> get stream => _downloadStream;

  @override
  ResponseSource get source => ResponseSource.download;

  @override
  int? get sourceLength => _downloadStream.sourceLength;

  @override
  void close() => _downloadStream.cancel();
}

class DownloadStream extends Stream<List<int>> {
  final StreamedResponse _streamedResponse;
  DownloadStream(this._streamedResponse);

  static Future<DownloadStream> open(
    final Uri url,
    final IntRange range,
    final Client client,
    final Map<String, String> requestHeaders,
  ) async {
    assert(requestHeaders.containsKey(HttpHeaders.acceptEncodingHeader),
        'Accept-Encoding header should be set');
    final request = Request('GET', url);
    request.headers.addAll(requestHeaders);
    final rangeRequest = range.isFull ? null : range.rangeRequest;
    if (rangeRequest != null) {
      request.headers[HttpHeaders.rangeHeader] = rangeRequest.header;
    }
    DownloadStream? downloadStream;
    try {
      downloadStream = DownloadStream(await client.send(request));
      if (rangeRequest == null) {
        HttpStatusCodeException.validate(
            url, HttpStatus.ok, downloadStream.statusCode);
      } else {
        HttpRangeException.validate(
            url, rangeRequest, downloadStream.responseRange);
      }
      return downloadStream;
    } catch (_) {
      downloadStream?.cancel();
      rethrow;
    }
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _listened = true;
    return _streamedResponse.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  ///To cancel the stream, we need to call cancel on the StreamedResponse.
  void cancel() async {
    if (_listened) return;
    try {
      final listener = listen(null, onError: (_) {}, cancelOnError: true);
      await listener.cancel();
    } catch (_) {}
  }

  bool _listened = false;
  bool get hasListener => _listened;
  BaseResponse get baseResponse => _streamedResponse;

  HttpRangeResponse? get responseRange {
    return HttpRangeResponse.parse(
      baseResponse.headers[HttpHeaders.contentRangeHeader],
      baseResponse.contentLength,
    );
  }

  int? get sourceLength {
    if (baseResponse.headers.containsKey(HttpHeaders.contentRangeHeader)) {
      return responseRange?.sourceLength;
    }
    return baseResponse.contentLength;
  }

  CachedResponseHeaders get cachedResponseHeaders {
    return CachedResponseHeaders.fromBaseResponse(baseResponse);
  }

  int get statusCode => baseResponse.statusCode;
}
