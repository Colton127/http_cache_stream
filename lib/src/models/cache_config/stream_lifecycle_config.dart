/// Controls how an inactive `HttpCacheStream` is managed over time.
///
/// `HttpCacheStream` instances are managed with a retain/release lifecycle.
/// Obtaining a stream retains it, and callers must release it when they are
/// finished. In most consumer flows, streams are used indirectly through
/// `getCacheUrl`, which automates retain/release handling.
///
/// A stream is considered inactive when it is no longer retained.
/// Inactive streams are still eligible for pause and disposal according to this
/// configuration.
///
/// Use this configuration to balance resource usage and resume behavior for
/// streams that are not actively being consumed.
///
/// - `pauseAfter` determines how long an inactive stream may remain before any
///   active download is paused. Pausing preserves the connection for the
///   remaining `readTimeout` window so the stream can still resume without a
///   full reconnect.
/// - `disposeAfter` determines how long an inactive stream may remain before it
///   is fully disposed. Once disposed, the stream cannot be resumed and a new
///   request must be created.
class StreamLifecycleConfig {
  /// The duration after which an inactive stream is paused.
  ///
  /// If a stream is no longer retained for this duration, the underlying
  /// download will be paused and the connection is kept alive only long enough
  /// to support resuming within the configured `readTimeout`.
  final Duration pauseAfter;

  /// The duration after which an inactive stream is disposed.
  ///
  /// Once the stream has been disposed, it cannot be resumed and must be
  /// recreated for subsequent requests.
  final Duration disposeAfter;

  const StreamLifecycleConfig({
    this.pauseAfter = const Duration(seconds: 10),
    this.disposeAfter = const Duration(minutes: 5),
  });
}
