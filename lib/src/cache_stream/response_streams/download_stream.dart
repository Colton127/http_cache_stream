import 'dart:async';
import 'dart:io';

import 'package:http/http.dart';
import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:http_cache_stream/src/models/exceptions.dart';
import 'package:http_cache_stream/src/models/http_range/http_range_response.dart';

class DownloadStream extends Stream<List<int>> {
  final StreamedResponse _streamedResponse;
  DownloadStream(this._streamedResponse);

  static Future<DownloadStream> open(
    final Uri url,
    final IntRange range,
    final Client client,
    final Map<String, String> requestHeaders,
  ) async {
    assert(requestHeaders.containsKey(HttpHeaders.acceptEncodingHeader), 'Accept-Encoding header should be set');
    final request = Request('GET', url);
    request.headers.addAll(requestHeaders);
    final rangeRequest = range.isFull ? null : range.rangeRequest;
    if (rangeRequest != null) {
      request.headers[HttpHeaders.rangeHeader] = rangeRequest.header;
    }
    final DownloadStream downloadStream = DownloadStream(await client.send(request));
    try {
      if (rangeRequest == null) {
        HttpStatusCodeException.validateCompleteResponse(url, downloadStream.baseResponse);
      } else {
        InvalidCacheRangeException.validate(url, rangeRequest, downloadStream.responseRange);
      }
      return downloadStream;
    } catch (e) {
      downloadStream.cancel();
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

  HttpRangeResponse? get responseRange => HttpRangeResponse.parse(baseResponse);

  int? get sourceLength {
    if (baseResponse.headers.containsKey(HttpHeaders.contentRangeHeader)) {
      return responseRange?.sourceLength;
    }
    return baseResponse.contentLength;
  }

  CachedResponseHeaders get responseHeaders {
    return CachedResponseHeaders.fromBaseResponse(baseResponse);
  }

  int get statusCode => baseResponse.statusCode;
}
