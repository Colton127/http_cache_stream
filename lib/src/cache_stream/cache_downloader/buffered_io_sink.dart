import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// An IO sink that supports adding data while flushing to disk asynchronously.
class BufferedIOSink {
  final File file;
  BufferedIOSink(this.file, int initialPosition) : _flushedBytes = initialPosition;
  int _flushedBytes;
  final _buffer = BytesBuilder(copy: false);
  RandomAccessFile? _openedRAF;
  bool _isClosed = false;
  Future<void>? _flushFuture;
  final List<({int position, Completer<void> completer})> _positionWaiters = [];

  void add(List<int> data) {
    if (_isClosed) {
      throw StateError('Cannot add data to a closed sink.');
    }
    _buffer.add(data);
  }

  /// Flushes all buffered data to disk. If new data is added during flushing, it will continue flushing until the buffer is empty.
  /// If an error occurs during flushing, it will be propagated to the caller, and all future flush attempts will rethrow the same error.
  Future<void> flush() {
    if (_flushFuture != null) return _flushFuture!;
    if (_buffer.isEmpty) return Future.value();

    return _flushFuture = () async {
      try {
        RandomAccessFile? raf = _openedRAF;

        if (raf == null) {
          FileMode fileMode = FileMode.append;

          if (flushedBytes == 0) {
            await file.parent.create(recursive: true); //Ensure directory exists
            fileMode = FileMode.write; //Overwrite existing
          }

          raf = _openedRAF = await file.open(mode: fileMode);
        }

        while (_buffer.isNotEmpty) {
          final bytes = _buffer.takeBytes();
          await raf.writeFrom(bytes, 0, bytes.length);
          _flushedBytes += bytes.length;
          _notifyPositionWaiters();
        }
        _flushFuture = null;
      } catch (e) {
        _failPositionWaiters(e);
        rethrow;
      }
    }();
  }

  /// Returns a [Future] that completes once [flushedBytes] reaches or exceeds [minFlushedBytes].
  /// Completes immediately if the position is already reached.
  /// Fails if the sink is closed or a flush error occurs before the position is reached.
  Future<void> waitForPosition(int minFlushedBytes, [Duration timeout = const Duration(seconds: 30)]) {
    if (_flushedBytes >= minFlushedBytes) return Future.value();
    if (_isClosed) {
      return Future.error(StateError('BufferedIOSink closed before reaching position $minFlushedBytes'));
    }
    final completer = Completer<void>();
    _positionWaiters.add((position: minFlushedBytes, completer: completer));
    return completer.future.timeout(timeout, onTimeout: () {
      _positionWaiters.removeWhere((w) => w.completer == completer);
      throw TimeoutException('Timeout while waiting for flushedBytes to reach $minFlushedBytes', timeout);
    });
  }

  void _notifyPositionWaiters() {
    if (_positionWaiters.isEmpty) return;
    for (int i = _positionWaiters.length - 1; i >= 0; i--) {
      if (_flushedBytes >= _positionWaiters[i].position) {
        _positionWaiters.removeAt(i).completer.complete();
      }
    }
  }

  void _failPositionWaiters(Object error) {
    if (_positionWaiters.isEmpty) return;
    for (final w in _positionWaiters) {
      w.completer.completeError(error);
    }
    _positionWaiters.clear();
  }

  Future<void> close({final bool flushBuffer = true}) async {
    if (_isClosed) return;
    _isClosed = true;

    try {
      if (!flushBuffer) {
        _buffer.clear();
      }
      await flush(); //Even if !flushBuffer, ongoing flush must complete before RAF can be closed
    } finally {
      _failPositionWaiters(StateError('BufferedIOSink closed'));
      _buffer.clear();
      if (_openedRAF case final RandomAccessFile raf) {
        _openedRAF = null;
        await raf.close();
      }
    }
  }

  int get bufferSize => _buffer.length;
  int get flushedBytes => _flushedBytes;
  bool get flushed => _buffer.isEmpty && !isFlushing;
  bool get isFlushing => _flushFuture != null;
  bool get isClosed => _isClosed;
}
