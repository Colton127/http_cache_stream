class CacheStreamDisposedException extends StateError {
  final Uri sourceUrl;
  CacheStreamDisposedException(this.sourceUrl)
      : super('Attempted to use a disposed HttpCacheStream | $sourceUrl');
}
