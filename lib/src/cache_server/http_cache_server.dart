import 'dart:async';

import 'package:http_cache_stream/src/cache_server/local_cache_server.dart';
import 'package:http_cache_stream/src/etc/extensions.dart';

import '../../http_cache_stream.dart';

class HttpCacheServer {
  final Uri origin;
  final LocalCacheServer _localCacheServer;

  /// The configuration for each generated stream.
  final StreamCacheConfig config;
  final HttpCacheStream Function(Uri sourceUrl, {StreamCacheConfig config})
      _createCacheStream;
  HttpCacheServer(this.origin, this._localCacheServer, this.config,
      this._createCacheStream) {
    _localCacheServer.start((request) {
      final sourceUrl = getSourceUrl(request.uri);
      final cacheStream = _createCacheStream(sourceUrl, config: config);
      request.response.done.onComplete(() {
        if (isDisposed) {
          cacheStream
              .dispose()
              .ignore(); // Decrease retainCount immediately if the server is disposed
        } else {
          Timer(
              cacheStream.config.autoDisposeDelay,
              () => cacheStream
                  .dispose()
                  .ignore()); // Decrease the stream's retainCount for autoDispose
        }
      });
      return cacheStream;
    });
  }

  Uri getCacheUrl(Uri sourceUrl) {
    if (sourceUrl.scheme != origin.scheme ||
        sourceUrl.host != origin.host ||
        sourceUrl.port != origin.port) {
      throw ArgumentError('Invalid source URL: $sourceUrl');
    }
    return _localCacheServer.getCacheUrl(sourceUrl);
  }

  Uri getSourceUrl(Uri cacheUrl) {
    return cacheUrl.replaceOrigin(origin);
  }

  /// The URI of the local cache server. Requests to this URI will be redirected to the source URL.
  Uri get serverUri => _localCacheServer.serverUri;

  Future<void> dispose() {
    if (!_completer.isCompleted) {
      _completer.complete(_localCacheServer.close());
    }
    return _completer.future;
  }

  final _completer = Completer<void>();
  bool get isDisposed => _completer.isCompleted;
  Future<void> get future => _completer.future;
}
