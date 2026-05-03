class CacheStreamDisposedException extends StateError {
  final Uri sourceUrl;
  CacheStreamDisposedException(this.sourceUrl) : super('Attempted to use a disposed HttpCacheStream | $sourceUrl');
}

class CacheManagerDisposedException extends StateError {
  CacheManagerDisposedException() : super('Attempted to use a disposed HttpCacheManager');
}

class CacheServerClosedException extends StateError {
  final Uri origin;
  CacheServerClosedException(this.origin) : super('Attempted to use a closed HttpCacheServer | $origin');
}
