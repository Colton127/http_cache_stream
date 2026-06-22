import 'dart:async';

class PauseCounter {
  PauseCounter({bool isPaused = false}) : _pauseCount = isPaused ? 1 : 0;
  Completer<void>? _resumeCompleter;
  int _pauseCount;

  void pause() {
    _pauseCount++;
  }

  void resume({bool force = false}) {
    if (!isPaused) {
      return;
    } else if (_pauseCount == 1 || force) {
      _pauseCount = 0;
      _resumeCompleter?.complete();
      _resumeCompleter = null;
    } else {
      _pauseCount--;
    }
  }

  bool get isPaused => _pauseCount != 0;

  Future<void> get onResume {
    if (!isPaused) return Future.value();
    return (_resumeCompleter ??= Completer<void>()).future;
  }
}
