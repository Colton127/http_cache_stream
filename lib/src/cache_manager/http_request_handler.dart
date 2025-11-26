import 'dart:async';
import 'dart:io';

import 'package:mime/mime.dart';

import '../../http_cache_stream.dart';
import '../etc/extensions.dart';
import '../models/http_range/http_range.dart';
import '../models/http_range/http_range_request.dart';
import '../models/http_range/http_range_response.dart';

class RequestHandler {
  final HttpRequest httpRequest;

  RequestHandler(this.httpRequest) {
    _awaitDone();
  }

  void _awaitDone() async {
    try {
      httpRequest.response.bufferOutput = false;
      httpRequest.response.statusCode = HttpStatus
          .internalServerError; //Set default status code to 500, in case of error
      await httpRequest.response.done;
    } catch (_) {
    } finally {
      _closed = true;
    }
  }

  void stream(final HttpCacheStream cacheStream) async {
    if (isClosed) return; //Request closed before we could start streaming
    Object? error;
    StreamResponse? streamResponse;
    try {
      final rangeRequest = HttpRangeRequest.parse(httpRequest.rangeHeader);
      streamResponse = await cacheStream.request(
        start: rangeRequest?.start,
        end: rangeRequest?.endEx,
      );
      if (isClosed) {
        return; //Request closed before we could start streaming
      }
      _setHeaders(
        rangeRequest,
        cacheStream.config,
        cacheStream.metadata.headers,
        streamResponse,
      ); //Set the headers for the response before starting the stream
      _streaming = true;
      //Note: [addStream] will automatically handle pausing/resuming the source stream to avoid buffering the entire response in memory.
      await httpRequest.response.addStream(streamResponse.stream);
    } catch (e) {
      error = e;
    } finally {
      _streaming = false;
      close(error);
      streamResponse
          ?.close(); //Close the response; may be done automatically by the [addStream] method, but we do it here to be sure.
    }
  }

  void _setHeaders(
    final HttpRangeRequest? rangeRequest,
    final StreamCacheConfig cacheConfig,
    final CachedResponseHeaders? cacheHeaders,
    final StreamResponse streamResponse,
  ) {
    final httpResponse = httpRequest.response;
    httpResponse.headers.clear();

    String? cachedContentType;
    int? sourceLength = streamResponse.sourceLength;
    if (cacheHeaders != null) {
      sourceLength ??= cacheHeaders.sourceLength;
      if (cacheHeaders.acceptsRangeRequests) {
        httpResponse.headers.set(
          HttpHeaders.acceptRangesHeader,
          'bytes',
        );
      }
      cachedContentType = cacheHeaders.get(HttpHeaders.contentTypeHeader);
      if (cacheConfig.copyCachedResponseHeaders) {
        cacheHeaders.forEach(httpResponse.headers.set);
      }
    }
    cacheConfig.combinedResponseHeaders().forEach(httpResponse.headers.set);

    if (httpResponse.headers.value(HttpHeaders.contentTypeHeader) == null) {
      final contentType = cachedContentType ??
          lookupMimeType(httpRequest.uri.path) ??
          'application/octet-stream';
      httpResponse.headers.set(HttpHeaders.contentTypeHeader, contentType);
    }

    if (rangeRequest != null) {
      final rangeResponse = HttpRangeResponse.inclusive(
        streamResponse.effectiveStart,
        streamResponse.effectiveEnd,
        sourceLength: sourceLength,
      );
      httpResponse.headers.set(
        HttpHeaders.contentRangeHeader,
        rangeResponse.header,
      );
      httpResponse.contentLength = rangeResponse.contentLength ?? -1;
      httpResponse.statusCode = HttpStatus.partialContent;
      assert(
        HttpRange.isEqual(rangeRequest, rangeResponse),
        'Invalid HttpRange: request: $rangeRequest | response: $rangeResponse | StreamResponse.Range: ${streamResponse.range}',
      );
    } else {
      httpResponse.contentLength = sourceLength ?? -1;
      httpResponse.statusCode = HttpStatus.ok;
    }
  }

  void close([final Object? error]) {
    if (_closed) return;
    _closed = true;
    if (error != null && !_streaming) {
      httpRequest.response.addError(error);
    }
    httpRequest.response
        .close()
        .ignore(); //Tell the client that the response is complete.
  }

  ///Indicates if the [HttpResponse] is closed. If true, no more data can be sent to the client.
  bool _closed = false;

  ///Indicate that [addStream] is currently streaming data to the client. When true, the [HttpResponse] cannot be manually written to.
  bool _streaming = false;
  bool get isClosed => _closed;
}
