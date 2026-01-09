import 'dart:async';
import 'dart:typed_data';

/// A buffer that collects bytes and emits them in chunks of at least [minChunkSize] when flushed.
class ChunkedBytesBuffer {
  final void Function(List<int> data) _onData;
  final int minChunkSize;
  final int maxBufferSize;
  ChunkedBytesBuffer(
    this._onData, {
    required void Function(bool isFull) onBufferFilled,
    required this.minChunkSize,
    required this.maxBufferSize,
    final bool copy = false,
  })  : _buffer = BytesBuilder(copy: copy),
        _onBufferFilled = onBufferFilled;

  final BytesBuilder _buffer;
  final void Function(bool isFull) _onBufferFilled;
  bool _paused = false;
  Completer<void>? _resumeCompleter;

  void add(List<int> bytes) {
    _buffer.add(bytes);

    if (isPaused) {
      assert(!_isFullNotified, 'Data added while paused after full notification');
      if (_buffer.length >= maxBufferSize && !_isFullNotified) {
        _isFullNotified = true;
        _onBufferFilled(true);
      }
    } else if (_buffer.length >= minChunkSize) {
      flush();
    }
  }

  void flush() {
    if (_buffer.isNotEmpty) {
      _onData(_buffer.takeBytes());

      if (_isFullNotified) {
        _isFullNotified = false;
        _onBufferFilled(false);
      }
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

  bool get isEmpty => _buffer.isEmpty;
  bool get isPaused => _paused;
  int get length => _buffer.length;
  bool _isFullNotified = false;
}
