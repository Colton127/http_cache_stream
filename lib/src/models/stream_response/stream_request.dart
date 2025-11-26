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

  void complete(final FutureOr<StreamResponse> response) {
    assert(!_responseCompleter.isCompleted, 'Response already completed');
    if (!_responseCompleter.isCompleted) {
      _responseCompleter.complete(response);
    } else {
      switch (response) {
        case StreamResponse():
          response.close();
        case Future<StreamResponse>():
          response.then((value) => value.close()).ignore();
      }
    }
  }

  void completeError(final Object error, [StackTrace? stackTrace]) {
    assert(!_responseCompleter.isCompleted, 'Response already completed');
    if (!_responseCompleter.isCompleted) {
      _responseCompleter.completeError(error, stackTrace);
    }
  }

  Future<StreamResponse> get response => _responseCompleter.future;
  int get start => range.start;
  int? get end => range.end;
  bool get isComplete => _responseCompleter.isCompleted;
  bool get isRangeRequest => range.isFull == false;
}
