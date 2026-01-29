import 'dart:io';

import '../etc/extensions/uri_extensions.dart';
import '../models/config/server/server_config.dart';
import '../request_handler/request_handler.dart';

class LocalCacheServer {
  final HttpServer _httpServer;
  final Uri serverUri;
  LocalCacheServer._(this._httpServer)
      : serverUri = Uri(
          scheme: 'http',
          host: _httpServer.address.host,
          port: _httpServer.port,
        );

  static Future<LocalCacheServer> init([CacheServerConfig? serverConfig]) async {
    serverConfig ??= const CacheServerConfig();
    return LocalCacheServer._(await serverConfig.createServer());
  }

  void start(final Future<void> Function(RequestHandler handler) processRequest) {
    _httpServer.listen(
      (request) async {
        final requestHandler = RequestHandler(request);
        try {
          if (request.method != 'GET' && request.method != 'HEAD') {
            requestHandler.close(HttpStatus.methodNotAllowed);
          } else {
            await processRequest(requestHandler);
          }
        } catch (_) {
          requestHandler.close(HttpStatus.internalServerError);
        } finally {
          assert(requestHandler.isClosed, 'RequestHandler should be closed after processing the request');
        }
      },
      onError: (_) {},
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
