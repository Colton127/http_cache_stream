import 'dart:io';

import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:http_cache_stream/src/cache_manager/http_request_handler.dart';

class LocalCacheServer {
  final HttpServer _httpServer;
  final Uri serverUri;
  LocalCacheServer._(this._httpServer)
      : serverUri = Uri(
          scheme: 'http',
          host: _httpServer.address.host,
          port: _httpServer.port,
        );

  static Future<LocalCacheServer> init() async {
    final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return LocalCacheServer._(httpServer);
  }

  void start(final HttpCacheStream? Function(HttpRequest request) getCacheStream) {
    _httpServer.listen(
      (request) async {
        final requestHandler = RequestHandler(request);
        try {
          if (request.method != 'GET' && request.method != 'HEAD') {
            requestHandler.close(HttpStatus.methodNotAllowed);
            return;
          }
          final httpCacheStream = getCacheStream(request);
          if (httpCacheStream == null) {
            requestHandler.close(HttpStatus.serviceUnavailable);
            return;
          }
          await requestHandler.stream(httpCacheStream);
          requestHandler.close();
        } catch (_) {
          requestHandler.close(HttpStatus.internalServerError);
        }
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  Uri getCacheUrl(Uri sourceUrl) {
    return sourceUrl.replace(scheme: serverUri.scheme, host: serverUri.host, port: serverUri.port);
  }

  HttpConnectionsInfo connectionsInfo() => _httpServer.connectionsInfo();

  Future<void> close() {
    return _httpServer.close(force: true);
  }
}
