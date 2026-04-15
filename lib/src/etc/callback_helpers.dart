import 'dart:async';

/// Helper function to execute user-provided callbacks safely, ensuring that any exceptions thrown are caught and handled by the current Zone's error handler.
void fireUserCallback(void Function() callback) {
  try {
    callback();
  } catch (e, st) {
    Zone.current.handleUncaughtError(e, st);
  }
}
