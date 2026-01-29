import 'dart:async';
import 'dart:io';

import 'package:http/http.dart';
import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:http_cache_stream/src/models/http_range/http_range_response.dart';

import '../../etc/extensions/http_extensions.dart';

class DownloadStream extends Stream<List<int>> {
  final StreamedResponse _streamedResponse;
  DownloadStream(this._streamedResponse);

  static Future<DownloadStream> open(
    final Uri url,
    final IntRange range,
    final StreamCacheConfig config,
  ) async {
    final request = Request('GET', url);
    request.headers.addAll(config.combinedRequestHeaders());
    final rangeRequest = range.isFull ? null : range.rangeRequest;
    if (rangeRequest != null) {
      request.headers[HttpHeaders.rangeHeader] = rangeRequest.header;
    }

    final streamedResponse = await config.httpClient.sendWithTimeout(request, config.readTimeout);
    try {
      if (rangeRequest == null) {
        HttpStatusCodeException.validateCompleteResponse(url, streamedResponse);
      } else {
        HttpRangeException.validate(url, rangeRequest, HttpRangeResponse.parse(streamedResponse));
      }
      return DownloadStream(streamedResponse);
    } catch (e) {
      streamedResponse.close();
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

  void cancel() {
    if (_listened) return;
    _streamedResponse.close();
  }

  bool _listened = false;
  BaseResponse get baseResponse => _streamedResponse;

  HttpRangeResponse? get responseRange => HttpRangeResponse.parse(_streamedResponse);

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
