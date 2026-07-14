import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../../etc/extensions/stream_extensions.dart';
import '../../models/cache_files/cache_files.dart';
import '../../models/exceptions/stream_response_exceptions.dart';
import '../../models/stream_response/stream_response_range.dart';
import '../cache_downloader/partial_cache_feed.dart';

///Streams a byte range of an active download by following the partial cache
///file on disk as the downloader flushes data to it.
///
///Every downloaded byte is persisted to the partial cache file before it
///becomes visible through [PartialCacheFeed], so this stream never buffers
///response data in memory: at most one read chunk is in flight at a time.
///A slow or paused consumer simply stops reading, providing unbounded
///backpressure regardless of how far the download runs ahead.
///
///Reads are clamped to [PartialCacheFeed.flushedPosition], and the stream
///waits for the feed when it catches up to the download. It survives the
///partial file being renamed to the complete file (the open file handle
///follows the rename) and transparent download retries: it only errors if the
///download terminates before the requested range is fully flushed.
class PartialCacheFileStream extends Stream<List<int>> {
  ///The maximum number of bytes read from the cache file per read operation.
  static const int defaultChunkSize = 256 * 1024;

  final StreamRange range;
  final CacheFiles cacheFiles;
  final PartialCacheFeed feed;
  final int chunkSize;

  final _controller = StreamController<List<int>>();
  Completer<void>? _wakeCompleter;
  bool _started = false;
  bool _cancelled = false;

  PartialCacheFileStream({
    required this.range,
    required this.cacheFiles,
    required this.feed,
    this.chunkSize = defaultChunkSize,
  }) {
    _controller.onListen = () {
      _started = true;
      _pump();
    };
    _controller.onResume = _wake;
    _controller.onCancel = () {
      _cancelled = true;
      _wake();
    };
  }

  ///Public API to cancel the stream. If a listener is attached, it receives [error] before the stream closes.
  void cancel([Object error = const StreamResponseCancelledException()]) {
    if (_cancelled || _controller.isClosed) return;
    _cancelled = true;
    if (_controller.hasListener) {
      _controller.addError(error);
    }
    _wake();
    if (!_started) {
      _closeController(); //The pump loop was never started, so close the controller directly
    }
  }

  void _pump() async {
    RandomAccessFile? raf;
    int position = range.start;
    final int? end = range.absoluteEnd;
    try {
      while (!_cancelled) {
        if (_controller.isPaused) {
          await _wait(); //Stop reading entirely while the consumer is paused
          continue;
        }
        if (end != null && position >= end) break; //Range fully served

        int available = feed.flushedPosition - position;
        if (end != null) {
          available = min(available, end - position);
        }
        if (available <= 0) {
          if (feed.isFinished) {
            //No more data will ever be flushed. Surface the download failure,
            //if any, only after all flushed data has been served.
            if (feed.finishError case final Object error when !_cancelled) {
              _controller.addError(error);
            }
            break;
          }
          await _wait(feedPosition: position);
          continue;
        }

        raf ??= await _openCacheFile(position);
        final chunk = await raf.read(min(available, chunkSize));
        if (_cancelled) break;
        if (chunk.isEmpty) {
          //Reads never exceed the flushed position, so an EOF here means the
          //cache file was truncated or replaced externally.
          throw FileSystemException(
            'Cache file ended unexpectedly at position $position ($available flushed bytes unread)',
            cacheFiles.partial.path,
          );
        }
        _controller.add(chunk);
        position += chunk.length;
      }
    } catch (e, stackTrace) {
      if (!_cancelled && !_controller.isClosed) {
        _controller.addError(e, stackTrace);
      }
    } finally {
      raf?.close().ignore();
      _closeController();
    }
  }

  ///Waits until the consumer resumes, the stream is cancelled, or - when
  ///[feedPosition] is provided - the feed flushes data beyond that position.
  Future<void> _wait({final int? feedPosition}) {
    final completer = _wakeCompleter = Completer<void>();
    if (feedPosition != null) {
      feed.waitForData(feedPosition).whenComplete(() {
        if (!completer.isCompleted) completer.complete();
      });
    }
    return completer.future;
  }

  void _wake() {
    final completer = _wakeCompleter;
    _wakeCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  Future<RandomAccessFile> _openCacheFile(final int position) async {
    RandomAccessFile raf;
    try {
      raf = await cacheFiles.activeCacheFile().open(mode: FileMode.read);
    } on FileSystemException {
      //The download may have completed between resolving the active file and
      //opening it, renaming partial -> complete. Re-resolve and retry once.
      raf = await cacheFiles.activeCacheFile().open(mode: FileMode.read);
    }
    try {
      return await raf.setPosition(position);
    } catch (_) {
      raf.close().ignore();
      rethrow;
    }
  }

  void _closeController() {
    if (_controller.isClosed) return;
    _controller.clearCallbacks();
    _controller.close().ignore();
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
