import 'dart:async';

import 'stream_response.dart';

/// A [StreamResponse] that contains an empty data stream.
/// Typically used to complete HEAD requests, where no body data is expected.
class HeaderStreamResponse extends StreamResponse {
  const HeaderStreamResponse(super.range, super.responseHeaders);

  @override
  Stream<List<int>> get stream => const Stream<List<int>>.empty();
  @override
  ResponseSource get source => ResponseSource.headerOnly;

  @override
  bool get isEmpty => true; //Always true, even though range may specify data.

  @override
  void cancel() {}
}
