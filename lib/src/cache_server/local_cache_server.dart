import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:http_cache_stream/src/cache_manager/http_request_handler.dart';
import 'package:http_cache_stream/src/etc/extensions.dart';

class LocalCacheServer {
  final HttpServer _httpServer;
  final Uri serverUri;
  LocalCacheServer._(this._httpServer)
      : serverUri = Uri(
          scheme: 'http',
          host: _httpServer.address.host,
          port: _httpServer.port,
        );

  static Future<LocalCacheServer> init([int? port]) async {
    final httpServer =
        await HttpServer.bind(InternetAddress.loopbackIPv4, port ?? 0);
    return LocalCacheServer._(httpServer);
  }

  void start(
      final HttpCacheStream? Function(HttpRequest request) getCacheStream) {
    _httpServer.listen(
      (request) {
        final httpCacheStream =
            request.method == 'GET' ? getCacheStream(request) : null;
        if (httpCacheStream != null) {
          RequestHandler(request).stream(httpCacheStream);
        } else {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.close().ignore();
        }
      },
      onError: (Object e) {
        if (kDebugMode) print('HttpCacheStream Proxy server onError: $e');
      },
      cancelOnError: false,
    );
  }

  Uri getCacheUrl(Uri sourceUrl) {
    return sourceUrl.replaceOrigin(serverUri);
  }

  Future<void> close() {
    return _httpServer.close(force: true);
  }
}
