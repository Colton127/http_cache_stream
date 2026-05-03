import 'dart:async';

import 'package:http_cache_stream/src/cache_server/local_cache_server.dart';

import '../../http_cache_stream.dart';
import '../etc/extensions/uri_extensions.dart';

/// A local proxy server that creates and manages [HttpCacheStream] instances
/// for a given origin, automatically routing requests and handling lifecycle.
///
/// `HttpCacheServer` is the recommended approach when working with content that
/// spans multiple URLs sharing the same origin — for example, HLS/DASH manifests
/// that reference many segment files, or a media player managing a playlist of
/// tracks from the same CDN.
///
/// Create an instance via [HttpCacheManager.createServer]. By default, the manager
/// returns an existing server when one already exists for the same [origin], so a
/// single `HttpCacheServer` can be shared across your application for a given host.
///
/// Convert any URL on the same origin to a local cache URL using [getCacheUrl]:
/// ```dart
/// final server = await cacheManager.createServer(
///   Uri.parse('https://cdn.example.com'),
/// );
/// // Both URLs below share the same origin and use the same server.
/// final track1 = server.getCacheUrl(Uri.parse('https://cdn.example.com/1.mp3'));
/// final track2 = server.getCacheUrl(Uri.parse('https://cdn.example.com/2.mp3'));
/// ```
class HttpCacheServer {
  /// The origin URI used to fulfill requests to this server.
  /// Example: "https://cdn.example.com".
  final Uri origin;

  final LocalCacheServer _localCacheServer;

  /// The configuration for each generated stream.
  final StreamCacheConfig config;
  final HttpCacheStream Function(Uri sourceUrl, {StreamCacheConfig? config}) _createCacheStream;
  HttpCacheServer(this.origin, this._localCacheServer, this.config, this._createCacheStream) {
    _localCacheServer.start((request) {
      final sourceUrl = request.uri.replaceOrigin(origin);
      final cacheStream = _createCacheStream(sourceUrl, config: config);
      return request.stream(cacheStream).whenComplete(cacheStream.release);
    });
  }

  /// Returns the local cache URL for the given [sourceUrl].
  ///
  /// The [sourceUrl] must share the same [origin] as this server.
  Uri getCacheUrl(Uri sourceUrl) {
    _checkClosed();

    if (sourceUrl.originEquals(origin)) {
      return _localCacheServer.getCacheUrl(sourceUrl);
    } else if (sourceUrl.originEquals(_localCacheServer.serverUri)) {
      return sourceUrl; // Already a cache URL, return as is
    } else {
      throw ArgumentError('Invalid source URL: $sourceUrl does not match server origin: $origin');
    }
  }

  /// Closes this [HttpCacheServer] and its underlying local server.
  /// If [force] is true, active connections will be closed immediately.
  Future<void> close({bool force = false}) {
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
    return _localCacheServer.close(force: force);
  }

  void _checkClosed() {
    if (isClosed) {
      throw CacheServerClosedException(origin);
    }
  }

  final _doneCompleter = Completer<void>();

  /// The URI of the local cache server.
  /// Requests to this URI will be redirected to the `origin` and fulfilled by this server.
  Uri get uri => _localCacheServer.serverUri;

  int get port => _localCacheServer.serverUri.port;

  /// Whether the server has been closed.
  bool get isClosed => _doneCompleter.isCompleted;

  /// A future that completes when the server is closed.
  Future<void> get future => _doneCompleter.future;
}
