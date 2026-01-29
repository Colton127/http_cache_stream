import 'dart:async';

import 'package:http_cache_stream/src/cache_server/local_cache_server.dart';

import '../../http_cache_stream.dart';
import '../etc/extensions/uri_extensions.dart';

/// A server that redirects requests to a source and automatically creates
/// [HttpCacheStream] instances.
class HttpCacheServer {
  /// The base source URI for this server.
  final Uri source;

  final LocalCacheServer _localCacheServer;

  /// The delay before a stream is disposed after all requests are completed.
  final Duration autoDisposeDelay;

  /// The configuration for each generated stream.
  final StreamCacheConfig config;
  final HttpCacheStream Function(Uri sourceUrl, {StreamCacheConfig config}) _createCacheStream;
  HttpCacheServer(this.source, this._localCacheServer, this.autoDisposeDelay, this.config, this._createCacheStream) {
    _localCacheServer.start((request) {
      final sourceUrl = getSourceUrl(request.uri);
      final cacheStream = _createCacheStream(sourceUrl, config: config);

      return request.stream(cacheStream).whenComplete(() {
        if (isDisposed) {
          cacheStream.dispose().ignore(); // Decrease retainCount immediately if the server is disposed
        } else {
          Timer(autoDisposeDelay, () => cacheStream.dispose().ignore()); // Decrease the stream's retainCount for autoDispose
        }
      });
    });
  }

  /// Returns the cache URL for a given source URL.
  Uri getCacheUrl(Uri sourceUrl) {
    if (sourceUrl.scheme != source.scheme || sourceUrl.host != source.host || sourceUrl.port != source.port) {
      throw ArgumentError('Invalid source URL: $sourceUrl. Expected scheme=${source.scheme}, host=${source.host}, port=${source.port}');
    }
    return _localCacheServer.getCacheUrl(sourceUrl);
  }

  /// Returns the source URL for a given cache URL.
  Uri getSourceUrl(Uri cacheUrl) {
    return cacheUrl.replaceOrigin(source);
  }

  /// The URI of the local cache server.
  ///
  /// Requests to this URI will be redirected to the source URL.
  Uri get uri => _localCacheServer.serverUri;

  /// Disposes this [HttpCacheServer] and closes the local server.
  Future<void> dispose() {
    if (_completer.isCompleted) {
      return _completer.future;
    } else {
      _completer.complete();
      return _localCacheServer.close();
    }
  }

  final _completer = Completer<void>();

  /// Whether the server has been disposed.
  bool get isDisposed => _completer.isCompleted;

  /// A future that completes when the server is disposed.
  Future<void> get future => _completer.future;
}
