import 'dart:async';

import 'package:http_cache_stream/http_cache_stream.dart';

class StreamRequest implements Comparable<StreamRequest> {
  final IntRange range;
  final _responseCompleter = Completer<StreamResponse>();
  StreamRequest(this.range);

  factory StreamRequest.construct(final IntRange range) {
    return StreamRequest(range);
  }

  ///Use a function to complete the response to catch errors during response creation.
  void complete(final FutureOr<StreamResponse> Function() func) {
    assert(!_responseCompleter.isCompleted, 'Response already completed');
    if (_responseCompleter.isCompleted) return;
    try {
      //Catch synchronous errors during response creation (e.g. invalid range).
      _responseCompleter.complete(func());
    } catch (e, stackTrace) {
      _responseCompleter.completeError(e, stackTrace);
    }
  }

  void completeError(final Object error, [StackTrace? stackTrace]) {
    assert(!_responseCompleter.isCompleted, 'Response already completed');
    if (_responseCompleter.isCompleted) return;
    _responseCompleter.completeError(error, stackTrace);
  }

  @override
  String toString() => 'StreamRequest($range)';

  Future<StreamResponse> get response => _responseCompleter.future;
  int get start => range.start;
  int? get end => range.end;
  bool get isComplete => _responseCompleter.isCompleted;
  bool get isRangeRequest => range.isFull == false;

  @override
  int compareTo(StreamRequest other) {
    return start.compareTo(other.start);
  }
}
