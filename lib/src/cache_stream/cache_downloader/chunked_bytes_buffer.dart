import 'dart:async';
import 'dart:typed_data';

class ChunkedBytesBuffer {
  final void Function(List<int> data) _onData;
  final int minChunkSize;
  ChunkedBytesBuffer(
    this._onData, {
    required this.minChunkSize,
  });
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  bool _paused = false;
  Completer<void>? _resumeCompleter;

  void add(List<int> bytes) {
    if (isPaused) {
      _buffer.add(bytes);
      return;
    } else if (_buffer.isEmpty && bytes.length >= minChunkSize) {
      _onData(bytes);
      return;
    } else {
      _buffer.add(bytes);
      if (_buffer.length >= minChunkSize) {
        flush();
      }
    }
  }

  void flush() {
    if (_buffer.isNotEmpty) {
      _onData(_buffer.takeBytes());
    }
  }

  void clear() {
    _buffer.clear();
  }

  void pause() {
    _paused = true;
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    flush();
    _resumeCompleter?.complete();
    _resumeCompleter = null;
  }

  Future<void> get onResume {
    if (!isPaused) return Future.value();
    return (_resumeCompleter ??= Completer<void>()).future;
  }

  bool get isPaused => _paused;
  int get length => _buffer.length;
}
