class FutureRunner<T> {
  Future<T>? _future;

  /// Whether a future is currently in flight.
  bool get isRunning => _future != null;

  /// The currently running future, or null if no future is running.
  Future<T>? get future => _future;

  Future<T>? call() => _future;

  /// Runs [factory] if idle, or returns the already-running future.
  ///
  /// The stored future is automatically cleared when it completes,
  /// whether successfully or with an error.
  Future<T> run(Future<T> Function() factory) {
    return _future ??= factory().whenComplete(() => _future = null);
  }
}
