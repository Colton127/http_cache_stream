import 'dart:async';
import 'dart:io';

import '../../http_cache_stream.dart';
import '../etc/mime_types.dart';
import '../models/exceptions/invalid_cache_exceptions.dart';
import '../models/http_range/http_range.dart';
import '../models/http_range/http_range_request.dart';
import '../models/http_range/http_range_response.dart';

/// Internal handler for HTTP responses.
class ResponseHandler {
  final HttpRequest _request;

  /// Creates a [ResponseHandler] for the given [_request].
  ResponseHandler(this._request);

  /// Processes the request and returns a [StreamResponse].
  Future<StreamResponse> getResponse(final HttpCacheStream cacheStream) async {
    final timeoutTimer = Timer(cacheStream.config.requestTimeout, () {
      close(HttpStatus.gatewayTimeout);
    });

    StreamResponse? streamResponse;
    try {
      final rangeRequest = HttpRangeRequest.parse(_request);
      streamResponse = await cacheStream.request(
        start: rangeRequest?.start,
        end: rangeRequest?.endEx,
      );

      if (isClosed) {
        throw StateError('Request closed before we could start streaming');
      }
      _setHeaders(
        rangeRequest,
        cacheStream.config,
        streamResponse,
      ); //Set the headers for the response before starting the stream

      _wroteHeaders = true;
      return streamResponse;
    } catch (e) {
      streamResponse?.cancel();
      if (!isClosed) {
        if (e is RangeError || e is HttpRangeException) {
          _request.response.contentLength = 0;
          final sourceLength = streamResponse?.sourceLength ??
              cacheStream.metadata.headers?.sourceLength;
          if (sourceLength != null) {
            _request.response.headers
                .set(HttpHeaders.contentRangeHeader, 'bytes */$sourceLength');
          }
          close(HttpStatus.requestedRangeNotSatisfiable);
        } else {
          close(HttpStatus.internalServerError);
        }
      }
      rethrow;
    } finally {
      timeoutTimer.cancel();
    }
  }

  /// Detaches the underlying socket from the response.
  Future<Socket> detachSocket() {
    assert(_wroteHeaders, 'Cannot detach socket before writing headers');
    _closed =
        true; //After detaching the socket, we can no longer use the HttpResponse object.
    return _request.response.detachSocket(writeHeaders: true);
  }

  void _setHeaders(
    final HttpRangeRequest? rangeRequest,
    final StreamCacheConfig cacheConfig,
    final StreamResponse streamResponse,
  ) {
    final httpResponse = _request.response;
    httpResponse.headers.clear();
    final cacheHeaders = streamResponse.sourceHeaders;

    if (cacheHeaders.acceptsRangeRequests) {
      httpResponse.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    }
    if (cacheConfig.copyCachedResponseHeaders) {
      cacheHeaders.forEach(httpResponse.headers.set);
    }
    cacheConfig.combinedResponseHeaders().forEach(httpResponse.headers.set);

    String? contentType =
        httpResponse.headers.value(HttpHeaders.contentTypeHeader) ??
            cacheHeaders.get(HttpHeaders.contentTypeHeader);
    if (contentType == null ||
        contentType.isEmpty ||
        contentType == MimeTypes.octetStream) {
      contentType =
          MimeTypes.fromPath(_request.uri.path) ?? MimeTypes.octetStream;
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

  /// Closes the response with an optional [statusCode].
  void close([int? statusCode]) {
    if (_closed) return;
    _closed = true;
    if (!_wroteHeaders && statusCode != null) {
      _request.response.statusCode = statusCode;
    }
    _request.response.close().ignore();
  }

  bool _closed = false;
  bool _wroteHeaders = false;

  /// Whether the response has been closed.
  bool get isClosed => _closed;
}
