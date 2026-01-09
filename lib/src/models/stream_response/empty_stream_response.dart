import '../../../http_cache_stream.dart';

///A stream response that contains no data.
///This is an acceptable response for range requests for which there is no data to serve. For example, requests at the end of a file, or HEAD requests.
class EmptyCacheStreamResponse extends StreamResponse {
  const EmptyCacheStreamResponse(super.range, super.responseHeaders);

  @override
  Stream<List<int>> get stream => const Stream<List<int>>.empty();

  @override
  ResponseSource get source => ResponseSource.empty;

  @override
  bool get isEmpty => true;

  @override
  void cancel() {}
}
