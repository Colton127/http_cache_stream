/// A configuration class that defines the lifecycle behavior of a `HttpCacheStream` instance.
class StreamLifecycleConfig {
  ///The duration after which an inactive stream will pause the ongoing download, if any.
  ///A paused connection will remain open for the duration of `readTimeout` to allow for resuming without needing to re-establish the connection.
  final Duration pauseDelay;

  ///The duration after which an inactive stream will be disposed, if any. Once disposed, the stream cannot be resumed and must be recreated for new requests.
  final Duration disposeDelay;
  const StreamLifecycleConfig({
    this.pauseDelay = const Duration(seconds: 10),
    this.disposeDelay = const Duration(minutes: 5),
  });
}
