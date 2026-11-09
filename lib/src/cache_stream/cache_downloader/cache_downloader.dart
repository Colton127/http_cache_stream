import 'dart:async';

import 'package:http_cache_stream/src/etc/extensions/file_extensions.dart';

import '../../etc/extensions/future_extensions.dart';
import '../../models/cache_config/stream_cache_config.dart';
import '../../models/cache_files/cache_files.dart';
import '../../models/exceptions/invalid_cache_exceptions.dart';
import '../../models/metadata/cache_metadata.dart';
import '../../models/metadata/cached_response_headers.dart';
import '../../models/stream_requests/int_range.dart';
import '../../models/stream_requests/stream_request.dart';
import '../../models/stream_response/partial_file_stream_response.dart';
import 'buffered_io_sink.dart';
import 'downloader.dart';

class CacheDownloader {
  final CacheFiles _cacheFiles;
  final Downloader _downloader;
  final BufferedIOSink _sink;
  final _completer = Completer<void>();
  int _position;
  bool _paused = false;

  ///Used to validate cache response when resuming a previous partial download
  final CachedResponseHeaders? _resumeHeaders;

  ///Headers received and validated
  CachedResponseHeaders? _validatedHeaders;

  ///The invalid cache the download stopped for, if any: [cancel]led for it, or found by a save. The download
  ///ends on it, and serves no more requests.
  InvalidCacheException? _invalidCache;

  ///If the download may still write to the partial cache file, until its sink is closed.
  bool _writing = true;
  CacheDownloader._(
    final CacheMetadata cacheMetadata,
    final int startPosition,
    this._downloader,
  )   : _cacheFiles = cacheMetadata.cacheFiles,
        _position = startPosition,
        _sink = BufferedIOSink(cacheMetadata.partialCacheFile, startPosition),
        _resumeHeaders = startPosition > 0 ? cacheMetadata.headers : null;

  factory CacheDownloader.construct(
    final CacheMetadata cacheMetadata,
    final StreamCacheConfig cacheConfig,
  ) {
    final partialCacheFile = cacheMetadata.partialCacheFile;
    int startPosition = 0;

    if (cacheMetadata.headers?.canResumeDownload() ?? false) {
      startPosition = partialCacheFile.lengthSyncOrNull() ?? 0;
    }

    return CacheDownloader._(
      cacheMetadata,
      startPosition,
      Downloader(cacheMetadata.sourceUrl, cacheConfig),
    );
  }

  Future<void> download({
    required final void Function(Object e) onError,
    required final void Function(CachedResponseHeaders headers) onHeaders,
    required final void Function(int position) onPosition,
    required final Future<void> Function(int sourceLength) onComplete,
  }) async {
    final int maxBufferSize = _downloader.streamConfig.maxBufferSize;

    try {
      try {
        await _downloader.download(
          downloadRange: () => IntRange(downloadPosition),
          onError: (error) {
            onError(error);
          },
          onHeaders: (cacheHttpHeaders) {
            final prevHeaders = _validatedHeaders ?? _resumeHeaders;
            if (prevHeaders != null &&
                downloadPosition > 0 &&
                !CachedResponseHeaders.validateCacheResponse(
                    prevHeaders, cacheHttpHeaders)) {
              throw CacheSourceChangedException(sourceUrl);
            }

            _validatedHeaders = cacheHttpHeaders;
            onHeaders(cacheHttpHeaders);
            onPosition(
                downloadPosition); //Emit current position to update progress and process queued requests
          },
          onData: (data) {
            assert(_validatedHeaders != null,
                'Bad state: No validated headers onData');
            _position += data.length;
            _sink.add(data);
            onPosition(
                downloadPosition); //Emit current position to update progress and synchronously process queued requests

            if (_sink.bufferSize > maxBufferSize) {
              _downloader
                  .pause(); //Pause upstream if we are receiving more data than we can write
              _sink.flush().then(
                (_) {
                  _downloader.resume();
                },
                onError: _cancelOnFlushError,
              );
            } else if (!_sink.isFlushing) {
              _sink.flush().catchError(_cancelOnFlushError);
            }
          },
        );
      } on InvalidCacheException catch (e) {
        _invalidCache ??= e;
        _validatedHeaders = null;
        rethrow;
      } catch (e) {
        onError(e);
      }

      // Post-download — flush remaining data and verify cache integrity
      try {
        await _sink.close(
          flushBuffer: !isInvalidated, //An invalid cache keeps no more bytes
          isDone: _downloader
              .isDone, //If the source did not end, the feed is marked as aborted so readers do not treat it as an end of stream
        ); //Flushes all buffered data and closes the sink
      } catch (e) {
        final error = _saveError(e);
        if (error is InvalidCacheException) {
          _invalidCache ??= error;
        } else {
          onError(error);
        }
      } finally {
        _writing = false;
      }

      //Cancelled for an invalid cache between responses (waiting for one, or
      //to retry) or while saving its last bytes, or found invalid by a save that
      //failed after the response ended: the download returned as if stopped,
      //and ends on it, as when a response is cancelled for it.
      if (_invalidCache case final InvalidCacheException invalidCache) {
        _validatedHeaders = null;
        throw invalidCache;
      }

      final sourceLength = _validatedHeaders?.sourceLength ??
          (_downloader.isDone ? downloadPosition : null);
      if (sourceLength != null && downloadPosition == sourceLength) {
        await onComplete(sourceLength);
      }
    } finally {
      if (!_sink.isClosed) {
        ///The sink is not closed on invalid cache exception, so we need to close it here
        await _sink.close(flushBuffer: false).ignoreResult();
      }
      _writing = false;
      if (!_completer.isCompleted) {
        _completer.complete();
      }
    }
  }

  ///Cancels the download on a failed save.
  void _cancelOnFlushError(final Object e) {
    //A block body: a flush future's error handler must return null.
    cancel(_saveError(e));
  }

  ///A partial cache file that does not end where the download resumes it (deleted, truncated or written
  ///to since) is an invalid cache: the download starts over.
  Object _saveError(final Object e) => e is SinkFileLengthException
      ? InvalidCacheSizeException(sourceUrl, e.length, e.expected)
      : e;

  /// Cancels the download and closes the stream. An optional [error] can be provided to indicate the reason for cancellation.
  /// An [InvalidCacheException] ends [download] on it, and the download serves no more requests.
  Future<void> cancel([Object? exception]) async {
    if (exception is InvalidCacheException) {
      _invalidCache ??= exception;
    }
    _downloader.close(exception);
    _paused = false;
    return _completer.future;
  }

  void pause() {
    if (_paused || !_downloader.isActive) return;
    _paused = true;
    _downloader.pause();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    _downloader.resume();
  }

  bool processRequest(final StreamRequest request) {
    assert(!_paused);
    if (isInvalidated) return false;
    if (request.start > downloadPosition) return false;
    final headers = _validatedHeaders;
    if (headers == null) return false;

    if (_downloader.isClosed && !_downloader.isDone) {
      final effectiveEnd = request.end ?? headers.sourceLength;
      if (effectiveEnd == null || effectiveEnd > downloadPosition) {
        return false; //Downloader closed and request exceeds downloaded range, cannot fulfill request
      }
    }

    request.complete(
      () => PartialFileStreamResponse(
        request.range,
        _cacheFiles,
        headers,
        _sink.feed,
      ),
    );

    return true;
  }

  int? get sourceLength =>
      _validatedHeaders?.sourceLength ?? _resumeHeaders?.sourceLength;
  int get downloadPosition => _position;
  int get filePosition => _sink.flushedBytes;

  ///If the download may still write to the partial cache file: until its sink is closed, and the file
  ///released.
  bool get isWriting => _writing;
  Uri get sourceUrl => _downloader.sourceUrl;
  bool get isClosed => _completer.isCompleted;

  ///If the download stopped for an invalid cache: [cancel]led for it, or found by a save.
  bool get isInvalidated => _invalidCache != null;
  bool get isPaused => _paused;
}
