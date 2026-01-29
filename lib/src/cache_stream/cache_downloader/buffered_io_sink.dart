import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// An IO sink that supports adding data while flushing to disk asynchronously.
class BufferedIOSink {
  final File file;
  BufferedIOSink(this.file, final int start)
      : _rafFuture = start > 0 ? file.open(mode: FileMode.append) : file.parent.create(recursive: true).then((_) => file.open(mode: FileMode.write));

  final Future<RandomAccessFile> _rafFuture;
  RandomAccessFile? _raf;
  final _buffer = BytesBuilder(copy: false);
  int _flushedBytes = 0;
  bool _isClosed = false;
  Future<void>? _flushFuture;

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
    if (_buffer.isEmpty) Future.value();

    return _flushFuture = () async {
      final raf = (_raf ??= await _rafFuture);

      while (_buffer.isNotEmpty) {
        final bytes = _buffer.takeBytes();
        await raf.writeFrom(bytes, 0, bytes.length);
        _flushedBytes += bytes.length;
      }

      _flushFuture = null;
    }();
  }

  Future<void> close({final bool flushBuffer = true}) async {
    if (_isClosed) return;
    _isClosed = true;

    try {
      if (!flushBuffer) {
        _buffer.clear(); //Discard buffered data
      }
      await flush(); //Ensure flush completes before closing (even if !flushBuffer, we cannot close while a flush is ongoing)
    } finally {
      _buffer.clear();
      await (_raf ?? await _rafFuture).close();
    }
  }

  int get bufferSize => _buffer.length;
  int get flushedBytes => _flushedBytes;
  bool get flushed => _buffer.isEmpty && !isFlushing;
  bool get isFlushing => _flushFuture != null;
  bool get isClosed => _isClosed;
}
