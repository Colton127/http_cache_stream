abstract class StreamResponseException implements Exception {
  final String message;
  const StreamResponseException(this.message);

  @override
  String toString() => 'StreamResponseException: $message';
}

class StreamResponseCancelledException extends StreamResponseException {
  const StreamResponseCancelledException() : super('StreamResponse was cancelled');
}

class StreamResponseExceededMaxBufferSizeException extends StreamResponseException {
  const StreamResponseExceededMaxBufferSizeException(int maxBufferSize) : super('Buffered response data exceeded maxBufferSize of $maxBufferSize bytes.');
}

abstract class CacheStreamException implements Exception {
  final Uri url;
  final String message;
  const CacheStreamException(this.url, this.message);

  @override
  String toString() => 'CacheStreamException: $message';
}

class CacheStreamDisposedException extends CacheStreamException {
  CacheStreamDisposedException(Uri uri) : super(uri, 'HttpCacheStream disposed | $uri');
}

class CacheDownloadStoppedException extends CacheStreamException {
  CacheDownloadStoppedException(Uri uri) : super(uri, 'HttpCacheStream download stopped | $uri');
}
