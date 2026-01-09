import 'dart:async';
import 'dart:io';

import '../../http_cache_stream.dart';
import '../etc/mime_types.dart';
import '../models/exceptions.dart';
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
      httpRequest.response.bufferOutput = false; //Stream responses are already buffered
      await httpRequest.response.done;
    } catch (_) {
      //response.done can throw if the client disconnects before the response is complete, we can safely ignore this.
    } finally {
      _closed = true;
    }
  }

  Future<void> stream(final HttpCacheStream cacheStream) async {
    if (isClosed) return;
    StreamResponse? streamResponse;
    try {
      final rangeRequest = HttpRangeRequest.parse(httpRequest);
      streamResponse = await (httpRequest.method == 'HEAD'
          ? cacheStream.headRequest(
              start: rangeRequest?.start,
              end: rangeRequest?.endEx,
            )
          : cacheStream.request(
              start: rangeRequest?.start,
              end: rangeRequest?.endEx,
            ));

      if (isClosed) {
        return; //Request closed before we could start streaming
      }
      _setHeaders(
        rangeRequest,
        cacheStream.config,
        streamResponse,
      ); //Set the headers for the response before starting the stream
      _wroteResponse = true;
      //Note: [addStream] will automatically handle pausing/resuming the source stream to avoid buffering the entire response in memory.
      await httpRequest.response.addStream(streamResponse.stream);
    } catch (e) {
      if (!isClosed && !_wroteResponse) {
        if (e is RangeError || e is InvalidCacheRangeException) {
          httpRequest.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          httpRequest.response.contentLength = 0;
          final sourceLength = streamResponse?.sourceLength ?? cacheStream.metadata.headers?.sourceLength;
          if (sourceLength != null) {
            httpRequest.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$sourceLength');
          }
        } else {
          httpRequest.response.statusCode = HttpStatus.internalServerError;
        }
        _wroteResponse = true;
      }
    } finally {
      streamResponse?.cancel(); //Close the response; may be done automatically by the [addStream] method, but we do it here to be sure.
    }
  }

  void _setHeaders(
    final HttpRangeRequest? rangeRequest,
    final StreamCacheConfig cacheConfig,
    final StreamResponse streamResponse,
  ) {
    final httpResponse = httpRequest.response;
    httpResponse.headers.clear();
    final cacheHeaders = streamResponse.sourceHeaders;

    if (cacheHeaders.acceptsRangeRequests) {
      httpResponse.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    }
    if (cacheConfig.copyCachedResponseHeaders) {
      cacheHeaders.forEach(httpResponse.headers.set);
    }
    cacheConfig.combinedResponseHeaders().forEach(httpResponse.headers.set);

    String? contentType = httpResponse.headers.value(HttpHeaders.contentTypeHeader) ?? cacheHeaders.get(HttpHeaders.contentTypeHeader);
    if (contentType == null || contentType.isEmpty || contentType == MimeTypes.octetStream) {
      contentType = MimeTypes.fromPath(httpRequest.uri.path) ?? MimeTypes.octetStream;
    }
    httpResponse.headers.set(HttpHeaders.contentTypeHeader, contentType);

    if (rangeRequest == null) {
      httpResponse.contentLength = streamResponse.sourceLength ?? -1;
      httpResponse.statusCode = HttpStatus.ok;
    } else {
      final rangeResponse = HttpRangeResponse.inclusive(
        streamResponse.effectiveStart,
        streamResponse.effectiveEnd,
        streamResponse.sourceLength,
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
    }
  }

  void close([int? statusCode]) {
    if (_closed) return;
    _closed = true;
    if (!_wroteResponse && httpRequest.response.statusCode == HttpStatus.ok) {
      httpRequest.response.statusCode = statusCode ?? HttpStatus.serviceUnavailable;
    }
    httpRequest.response.close().ignore(); //Tell the client that the response is complete.
  }

  ///Indicates if the [HttpResponse] is closed. If true, no more data can be sent to the client.
  bool _closed = false;

  bool _wroteResponse = false;

  ///Indicates if any data has been written to the response. When true, headers and status code can no longer be modified.
  bool get wroteResponse => _wroteResponse;

  ///Indicates if the [HttpResponse] is closed. If true, no more data can be sent to the client.
  bool get isClosed => _closed;
}
