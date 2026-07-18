import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../../etc/extensions/stream_extensions.dart';
import '../../models/cache_files/cache_files.dart';
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
///Like [File.openRead], this stream is inert and reusable: each call to
///[listen] lazily creates an independent reader over the full range, and a
///reader releases its file handle when its subscription completes or is
///cancelled. Events are delivered synchronously, so consumer pauses take
///effect immediately.
///
///Reads are clamped to [PartialCacheFeed.flushedPosition]. When a reader
///catches up to the download it waits until [readAhead] bytes accumulate
///(clamped to the range end) rather than waking per flush, avoiding a tight
///read loop over trivial amounts of data. It survives the partial file being
///renamed to the complete file (the open file handle follows the rename) and
///transparent download retries: it only errors if the download terminates
///before the requested range is fully flushed.
class PartialCacheFileStream extends Stream<List<int>> {
  ///The maximum number of bytes read from the cache file per read operation.
  static const int defaultChunkSize = 256 * 1024;

  final StreamRange range;
  final CacheFiles cacheFiles;
  final PartialCacheFeed feed;
  final int chunkSize;

  ///The number of bytes a reader caught up to the download waits to
  ///accumulate before reading again. Clamped to the range end, and cut short
  ///when the download terminates.
  final int readAhead;

  PartialCacheFileStream({
    required this.range,
    required this.cacheFiles,
    required this.feed,
    this.chunkSize = defaultChunkSize,
    int? readAhead,
  }) : readAhead = readAhead ?? chunkSize * 2;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _PartialCacheFileReader(this).subscribe(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

///A single subscription's read pass over the stream's range.
class _PartialCacheFileReader {
  final PartialCacheFileStream _stream;
  final _controller = StreamController<List<int>>(sync: true);
  Completer<void>? _wakeCompleter;
  bool _cancelled = false;

  _PartialCacheFileReader(this._stream) {
    _controller.onListen = _pump;
    _controller.onResume = _wake;
    _controller.onCancel = () {
      _cancelled = true;
      _wake();
    };
  }

  StreamSubscription<List<int>> subscribe(
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

  void _pump() async {
    final feed = _stream.feed;
    RandomAccessFile? raf;
    int position = _stream.range.start;
    final int? end = _stream.range.absoluteEnd;
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
          //Caught up to the download: wait for a comfortable amount of data
          //to accumulate instead of waking per flush, clamped so a nearby
          //range end still wakes as soon as it is reachable. The feed also
          //wakes the wait when the download terminates.
          int target = position + _stream.readAhead - 1;
          if (end != null) target = min(target, end - 1);
          await _wait(feedPosition: target);
          continue;
        }

        raf ??= await _openCacheFile(position);
        final chunk = await raf.read(min(available, _stream.chunkSize));
        if (_cancelled) break;
        if (chunk.isEmpty) {
          //Reads never exceed the flushed position, so an EOF here means the
          //cache file was truncated or replaced externally.
          throw FileSystemException(
            'Cache file ended unexpectedly at position $position ($available flushed bytes unread)',
            _stream.cacheFiles.partial.path,
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
      if (!_controller.isClosed) {
        _controller.clearCallbacks();
        _controller.close().ignore();
      }
    }
  }

  ///Waits until the consumer resumes, the subscription is cancelled, or -
  ///when [feedPosition] is provided - the feed flushes data beyond that
  ///position or finishes.
  Future<void> _wait({final int? feedPosition}) {
    final completer = _wakeCompleter = Completer<void>();
    if (feedPosition != null) {
      _stream.feed.waitForData(feedPosition).whenComplete(() {
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
    final cacheFiles = _stream.cacheFiles;
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
}
