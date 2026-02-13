import 'dart:io';

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

  static Future<LocalCacheServer> init() async {
    final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return LocalCacheServer._(httpServer);
  }

  void start(
      final Future<void> Function(RequestHandler handler) processRequest) {
    _httpServer.listen(
      (request) async {
        final requestHandler = RequestHandler(request);
        try {
          await processRequest(requestHandler);
        } catch (e) {
          requestHandler.closeWithError(e);
        } finally {
          assert(requestHandler.isClosed,
              'RequestHandler should be closed after processing the request');
        }
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  Uri getCacheUrl(Uri sourceUrl) {
    return sourceUrl.replace(
        scheme: serverUri.scheme, host: serverUri.host, port: serverUri.port);
  }

  Future<void> close() {
    return _httpServer.close(force: true);
  }
}
