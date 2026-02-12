import 'dart:async';

abstract class StreamResponseException implements Exception {
  final String message;
  const StreamResponseException(this.message);

  @override
  String toString() => 'StreamResponseException: $message';
}

class StreamResponseCancelledException extends StreamResponseException {
  const StreamResponseCancelledException()
      : super('StreamResponse was cancelled');
}

class StreamResponseExceededMaxBufferSizeException
    extends StreamResponseException {
  const StreamResponseExceededMaxBufferSizeException(int maxBufferSize)
      : super(
            'Buffered response data exceeded maxBufferSize of $maxBufferSize bytes.');
}

class StreamRequestTimedOutException extends StreamResponseException
    implements TimeoutException {
  @override
  final Duration duration;
  const StreamRequestTimedOutException(this.duration)
      : super('Stream request timed out after $duration');

  @override
  String toString() {
    return 'StreamRequestTimedOutException: $message';
  }
}
