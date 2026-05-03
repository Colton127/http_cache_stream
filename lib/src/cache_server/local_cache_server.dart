import 'dart:io';

import 'package:flutter/foundation.dart';

import '../etc/extensions/uri_extensions.dart';
import '../etc/keep_alive_server.dart';
import '../request_handler/request_handler.dart';

class LocalCacheServer {
  final KeepAliveServer _httpServer;
  final Uri serverUri;
  LocalCacheServer._(this._httpServer)
      : serverUri = Uri(
          scheme: 'http',
          host: _httpServer.address.host,
          port: _httpServer.port,
        );

  static Future<LocalCacheServer> init({int? port}) async {
    final httpServer = await KeepAliveServer.bind(InternetAddress.loopbackIPv4, port ?? 0);
    return LocalCacheServer._(httpServer);
  }

  void start(final Future<void> Function(RequestHandler handler) processRequest) {
    _httpServer.listen(
      (request) async {
        if (kDebugMode) {
          final sourceUrl = decodeSourceUrl(request.uri);
          print(
              'LocalCacheServer received request: ${request.uri} (requestedUri: ${request.requestedUri}) (sourceUrl: $sourceUrl, requestKey: ${request.uri.requestKey})');
        }

        final requestHandler = RequestHandler(request);
        try {
          await processRequest(requestHandler);
          assert(requestHandler.isClosed, 'RequestHandler should be closed after processing the request');
        } catch (e) {
          requestHandler.closeWithError(e);
        }
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  Uri? decodeSourceUrl(Uri requestUri) {
    final segments = requestUri.pathSegments;
    if (segments.length < 2) return null;
    final scheme = segments[0];
    final defaultPort = switch (scheme) {
      'https' => 443,
      'http' => 80,
      _ => null,
    };
    if (defaultPort == null) return null;

    final hostSegment = segments[1];
    String host = hostSegment;
    int port = defaultPort;

    final colonIdx = hostSegment.lastIndexOf(':');
    if (colonIdx > 0) {
      host = hostSegment.substring(0, colonIdx);
      port = int.tryParse(hostSegment.substring(colonIdx + 1)) ?? defaultPort;
    }

    return requestUri.replace(
      scheme: scheme,
      host: host,
      port: port,
      pathSegments: segments.skip(2),
    );
  }

  Uri encodeSourceUrl(Uri sourceUrl) {
    final defaultPort = switch (sourceUrl.scheme) {
      'https' => 443,
      'http' => 80,
      _ => throw ArgumentError('Unsupported URI scheme: ${sourceUrl.scheme}. Only http and https are supported.'),
    };

    String hostSegment = sourceUrl.host;

    if (sourceUrl.hasPort && sourceUrl.port != defaultPort) {
      hostSegment += ':${sourceUrl.port}';
    }

    return sourceUrl.replace(
      scheme: serverUri.scheme,
      host: serverUri.host,
      port: serverUri.port,
      pathSegments: [sourceUrl.scheme, hostSegment, ...sourceUrl.pathSegments],
    );
  }

  Future<void> ensureActive() => _httpServer.ensureActive();

  Uri getCacheUrl(Uri sourceUrl) {
    return sourceUrl.replaceOrigin(serverUri);
  }

  Future<void> close({bool force = true}) {
    return _httpServer.close(force: force);
  }
}
