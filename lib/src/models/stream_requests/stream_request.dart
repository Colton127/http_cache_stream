import 'dart:async';

import 'package:http_cache_stream/http_cache_stream.dart';

class StreamRequest {
  final IntRange range;
  final Completer<StreamResponse> _responseCompleter;
  const StreamRequest._(this.range, this._responseCompleter);

  factory StreamRequest.construct(final IntRange range) {
    final responseCompleter = Completer<StreamResponse>();
    return StreamRequest._(range, responseCompleter);
  }

  ///Use a function to complete the response to catch errors during response creation.
  void complete(final FutureOr<StreamResponse> Function() func) {
    assert(!_responseCompleter.isCompleted, 'Response already completed');
    if (_responseCompleter.isCompleted) return;

    try {
      //Catch synchronous errors during response creation (e.g. invalid range).
      _responseCompleter.complete(func());
    } catch (e) {
      _responseCompleter.completeError(e);
    }
  }

  void completeError(final Object error, [StackTrace? stackTrace]) {
    assert(!_responseCompleter.isCompleted, 'Response already completed');
    if (_responseCompleter.isCompleted) return;
    _responseCompleter.completeError(error, stackTrace);
  }

  @override
  String toString() => 'StreamRequest(range: $range, isCompleted: ${_responseCompleter.isCompleted})';

  Future<StreamResponse> get response => _responseCompleter.future;
  int get start => range.start;
  int? get end => range.end;
  bool get isComplete => _responseCompleter.isCompleted;
  bool get isRangeRequest => range.isFull == false;
  bool get isEmptyRequest => range.isEmpty;
}
