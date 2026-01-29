import 'dart:async';

import 'package:http_cache_stream/http_cache_stream.dart';

/// A [StreamResponse] that contains an empty data stream.
/// Typically used to complete HEAD requests, where no body data is expected.
class HeaderStreamResponse extends StreamResponse {
  const HeaderStreamResponse(super.range, super.responseHeaders);

  @override
  Stream<List<int>> get stream => const Stream<List<int>>.empty();
  @override
  ResponseSource get source => ResponseSource.headersOnly;

  @override
  bool get isEmpty => true; //Always true, even though range may specify data.

  @override
  void cancel() {}
}
