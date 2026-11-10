import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../models/exceptions/partial_cache_feed_exceptions.dart';
import '../response_streams/partial_cache_feed.dart';

part 'buffered_io_sink_feed.dart';

/// Thrown when the file a [BufferedIOSink] resumes does not end where the sink resumes it: it was deleted,
/// truncated or written to since the sink's earlier bytes were saved.
class SinkFileLengthException implements Exception {
  final String path;

  /// The length of the file.
  final int length;

  /// Where the sink resumes the file.
  final int expected;

  const SinkFileLengthException(this.path, this.length, this.expected);

  @override
  String toString() =>
      'SinkFileLengthException: $path is $length bytes long, but the sink resumes it at $expected';
}

/// An IO sink that supports adding data while flushing to disk asynchronously.
class BufferedIOSink {
  //Maximum number of bytes to write in a single write operation. This prevents long writes from stalling position waiters.
  static const int _maxWriteSize = 256 * 1024; // 256 KB

  final File file;
  BufferedIOSink(this.file, int initialPosition)
      : _flushedBytes = initialPosition {
    _feed = BufferedIOSinkFeed._(this);
  }

  int _flushedBytes;
  final _buffer = BytesBuilder(copy: false);
  RandomAccessFile? _openedRAF;
  bool _isClosed = false;
  Future<void>? _flushFuture;
  late final BufferedIOSinkFeed _feed;

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

          raf = await file.open(mode: fileMode);
          if (fileMode == FileMode.append) {
            //Appended at its end, the file must end where the sink resumes it.
            //Deleted since (append creates it again), truncated or written to,
            //it would take the sink's bytes at the wrong offset.
            final length = await raf.length();
            if (length != flushedBytes) {
              await raf.close();
              throw SinkFileLengthException(file.path, length, flushedBytes);
            }
          }
          _openedRAF = raf;
        }

        while (_buffer.isNotEmpty) {
          final bytes = _buffer.takeBytes();
          for (int start = 0; start < bytes.length; start += _maxWriteSize) {
            final int uncappedEnd = start + _maxWriteSize;
            final int end =
                uncappedEnd < bytes.length ? uncappedEnd : bytes.length;
            await raf.writeFrom(bytes, start, end);
            _flushedBytes += end - start;
            _feed._notifyPositionWaiters();
          }
        }
        _flushFuture = null;
      } catch (e) {
        _feed._failPositionWaiters(e);
        rethrow;
      }
    }();
  }

  /// Returns a [PositionWaiter] that completes once [flushedBytes] reaches or exceeds [minFlushedBytes].
  /// Completes immediately if the position is already reached.
  /// Fails if the sink is closed, a flush error occurs before the position is reached, or the waiter is cancelled.
  PositionWaiter waitForPosition(int minFlushedBytes) =>
      _feed.waitForPosition(minFlushedBytes);

  /// Closes the sink, resolving any waiters that can no longer be satisfied.
  ///
  /// Set [isDone] when the producer reached the end of its content. The feed is
  /// then left unfailed, so readers treat [flushedBytes] as the true end of the
  /// content. When [isDone] is false the download was aborted, and the feed
  /// fails with [PartialCacheAbortedException] so readers do not mistake the
  /// truncated content for an end of stream.
  Future<void> close({
    final bool flushBuffer = true,
    final bool isDone = false,
  }) async {
    if (_isClosed) return;
    _isClosed = true;

    try {
      if (!flushBuffer) {
        _buffer.clear();
      }
      await flush(); //Even if !flushBuffer, ongoing flush must complete before RAF can be closed
    } finally {
      _buffer.clear();
      try {
        if (_openedRAF case final RandomAccessFile raf) {
          _openedRAF = null;
          await raf.close();
        }
      } finally {
        _feed._close(
          failure: isDone ? null : PartialCacheAbortedException(_flushedBytes),
        );
      }
    }
  }

  int get bufferSize => _buffer.length;
  int get flushedBytes => _flushedBytes;
  PartialCacheFeed get feed => _feed;
  bool get flushed => _buffer.isEmpty && !isFlushing;
  bool get isFlushing => _flushFuture != null;
  bool get isClosed => _isClosed;
}
