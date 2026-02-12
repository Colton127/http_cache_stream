import 'dart:io';
import 'dart:typed_data';

/// An IO sink that supports adding data while flushing to disk asynchronously.
class BufferedIOSink {
  final File file;
  BufferedIOSink(this.file, final int initialPosition)
      : _initialPosition = initialPosition >= 0 ? initialPosition : 0;

  final _buffer = BytesBuilder(copy: false);
  final int _initialPosition;
  RandomAccessFile? _openedRAF;
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
    if (_buffer.isEmpty) return Future.value();

    return _flushFuture = () async {
      RandomAccessFile? raf = _openedRAF;

      if (raf == null) {
        FileMode fileMode = FileMode.append;

        if (_initialPosition == 0 && _flushedBytes == 0) {
          await file.parent.create(recursive: true); //Ensure directory exists
          fileMode = FileMode.write; //Overwrite existing
        }

        raf = _openedRAF = await file.open(mode: fileMode);
      }

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
        _buffer.clear();
      }
      await flush(); //Even if !flushBuffer, ongoing flush must complete before RAF can be closed
    } finally {
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
