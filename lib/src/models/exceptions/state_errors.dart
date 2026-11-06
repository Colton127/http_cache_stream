class CacheStreamDisposedException extends StateError {
  final Uri sourceUrl;
  CacheStreamDisposedException(this.sourceUrl)
      : super('Attempted to use a disposed HttpCacheStream | $sourceUrl');
}

class CacheManagerDisposedException extends StateError {
  CacheManagerDisposedException()
      : super('Attempted to use a disposed HttpCacheManager');
}

/// Thrown when a cache URL is requested from an `HttpCacheManager` that was
/// initialized with `startServer: false`. Without the local cache server there
/// is no URL to serve the cache from: read the content through
/// `HttpCacheStream.request` (or `download`) instead.
class CacheServerUnavailableException extends StateError {
  final Uri sourceUrl;
  CacheServerUnavailableException(this.sourceUrl)
      : super(
          'HttpCacheManager was initialized without a local cache server (startServer: false), '
          'so there is no cache URL for $sourceUrl. Read it through HttpCacheStream.request instead.',
        );
}
