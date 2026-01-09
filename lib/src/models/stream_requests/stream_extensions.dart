import 'dart:async';

extension StreamControllerExtensions<T> on StreamController<T> {
  /// Returns true if the stream controller has an active listener and is not paused.
  ///
  /// Note that this can be true even if the controller is closed

  /// Clears all callbacks by setting them to null.
  ///
  /// Because these callbacks can still be called after a controller is closed, this can help prevent accidental calls.
  void clearCallbacks() {
    onCancel = null;
    onListen = null;
    onPause = null;
    onResume = null;
  }
}
