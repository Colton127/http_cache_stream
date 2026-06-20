import 'dart:io';

import '../../http_cache_stream.dart';
import '../etc/extensions/uri_extensions.dart';
import '../request_handler/request_handler.dart';
import 'keep_alive_server.dart';

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
    final httpServer =
        await KeepAliveServer.bind(InternetAddress.loopbackIPv4, port ?? 0);
    return LocalCacheServer._(httpServer);
  }

  void start(final HttpCacheStream Function(Uri sourceUrl) getCacheStream) {
    _httpServer.listen(
      (request) async {
        HttpCacheStream? cacheStream;
        final requestHandler = RequestHandler(request);

        try {
          final sourceUrl = decodeSourceUrl(request.uri);
          if (sourceUrl == null) {
            requestHandler.close(HttpStatus.badRequest);
            return;
          }
          cacheStream = getCacheStream(sourceUrl);
          await requestHandler.stream(cacheStream);
        } catch (e) {
          requestHandler.closeWithError(e);
        } finally {
          assert(requestHandler.isClosed,
              'RequestHandler should be closed after processing the request');
          cacheStream
              ?.release(); //Release the stream after handling the request
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
    if (sourceUrl.host == serverUri.host) {
      if (!validateCacheUrl(sourceUrl)) {
        throw ArgumentError(
            'Invalid source URL: $sourceUrl. The host matches the cache server host but the URL is not a valid cache URL.');
      }
      return sourceUrl; //Already encoded
    }

    final defaultPort = switch (sourceUrl.scheme) {
      'https' => 443,
      'http' => 80,
      _ => throw ArgumentError(
          'Unsupported URI scheme: ${sourceUrl.scheme}. Only http and https are supported.'),
    };

    String hostSegment = sourceUrl.host;

    if (sourceUrl.hasPort && sourceUrl.port != defaultPort) {
      hostSegment += ':${sourceUrl.port}';
    }

    final encodedUrl = sourceUrl.replace(
      scheme: serverUri.scheme,
      host: serverUri.host,
      port: serverUri.port,
      pathSegments: [sourceUrl.scheme, hostSegment, ...sourceUrl.pathSegments],
    );
    assert(
        validateCacheUrl(encodedUrl), 'Encoded URL is not valid: $encodedUrl');
    return encodedUrl;
  }

  bool validateCacheUrl(Uri url) {
    if (!url.originEquals(serverUri)) return false;
    return decodeSourceUrl(url) != null;
  }

  Future<void> ensureActive() => _httpServer.ensureActive();

  Future<void> close({bool force = true}) {
    return _httpServer.close(force: force);
  }
}
