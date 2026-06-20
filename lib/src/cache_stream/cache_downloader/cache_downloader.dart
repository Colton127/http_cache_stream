import 'dart:async';

import 'package:http_cache_stream/src/etc/extensions/file_extensions.dart';

import '../../models/cache_config/stream_cache_config.dart';
import '../../models/cache_files/cache_files.dart';
import '../../models/exceptions/http_exceptions.dart';
import '../../models/exceptions/invalid_cache_exceptions.dart';
import '../../models/metadata/cache_metadata.dart';
import '../../models/metadata/cached_response_headers.dart';
import '../../models/stream_requests/int_range.dart';
import '../../models/stream_requests/stream_request.dart';
import '../../models/stream_response/stream_response.dart';
import 'buffered_io_sink.dart';
import 'downloader.dart';

class CacheDownloader {
  final CacheFiles _cacheFiles;
  final Downloader _downloader;
  final BufferedIOSink _sink;
  final _streamController = StreamController<List<int>>.broadcast(sync: true);
  final _completer = Completer<void>();
  int _position;
  int _pendingStreamBytes = 0; //Bytes received but not added to stream yet. These bytes will be added within the current event loop.
  CachedResponseHeaders? _cachedHeaders;
  bool _paused = false;
  CacheDownloader._(
    final CacheMetadata cacheMetadata,
    final int startPosition,
    this._downloader,
  )   : _cacheFiles = cacheMetadata.cacheFiles,
        _position = startPosition,
        _sink = BufferedIOSink(cacheMetadata.partialCacheFile, startPosition),
        _cachedHeaders = startPosition > 0 ? cacheMetadata.headers : null;

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
            _streamController.addError(error);
          },
          onHeaders: (cacheHttpHeaders) {
            final prevHeaders = _cachedHeaders;
            if (prevHeaders != null && downloadPosition > 0 && !CachedResponseHeaders.validateCacheResponse(prevHeaders, cacheHttpHeaders)) {
              throw CacheSourceChangedException(sourceUrl);
            }

            _cachedHeaders = cacheHttpHeaders;
            onHeaders(cacheHttpHeaders);
            onPosition(downloadPosition); //Emit current position to update progress and process queued requests
          },
          onData: (data) {
            _position += data.length;
            _sink.add(data);
            _pendingStreamBytes = data.length;
            onPosition(downloadPosition); //Emit current position to update progress and synchronously process queued requests
            _streamController.add(data); //Add after processing queued requests. Requests may be fulfilled from the data.
            _pendingStreamBytes = 0;

            if (_sink.bufferSize > maxBufferSize) {
              _downloader.pause(); //Pause upstream if we are receiving more data than we can write
              _sink.flush().then(
                (_) {
                  _downloader.resume();
                },
                onError: (e) {
                  cancel(e);
                },
              );
            } else if (!_sink.isFlushing) {
              _sink.flush().catchError((e) {
                cancel(e);
              });
            }
          },
        );
      } on InvalidCacheException {
        rethrow;
      } catch (e) {
        onError(e);
      }

      // Post-download — flush remaining data and verify cache integrity
      try {
        await _sink.close(flushBuffer: true); //Flushes all buffered data and closes the sink
      } catch (e) {
        onError(e);
      }
      final partialCacheLength = (await _sink.file.stat()).size;

      InvalidCacheSizeException.validate(
        sourceUrl,
        partialCacheLength,
        downloadPosition,
      );

      final sourceLength = _cachedHeaders?.sourceLength ?? (_downloader.isDone ? downloadPosition : null);
      if (sourceLength != null && partialCacheLength == sourceLength) {
        await onComplete(sourceLength);
      }
    } finally {
      if (!_completer.isCompleted) {
        _completer.complete();
      }
      if (!_sink.isClosed) {
        ///The sink is not closed on invalid cache exception, so we need to close it here
        _sink.close(flushBuffer: false).ignore();
      }
      if (!_streamController.isClosed) {
        if (!_downloader.isDone) {
          _streamController.addError(DownloadStoppedException(sourceUrl));
        }
        _streamController.close().ignore();
      }
    }
  }

  /// Cancels the download and closes the stream. An optional [error] can be provided to indicate the reason for cancellation.
  Future<void> cancel([Object? exception]) async {
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
    if (request.start > downloadPosition) return false;
    if (!_downloader.isActive) return false;
    final headers = _cachedHeaders;
    if (headers == null) return false;

    request.complete(() async {
      if (request.start >= streamPosition) {
        return StreamResponse.fromStream(
          request.range,
          headers,
          _streamController.stream,
          streamPosition,
          _downloader.streamConfig,
        );
      }

      final effectiveEnd = request.end ?? headers.sourceLength;
      if (effectiveEnd != null && downloadPosition >= effectiveEnd) {
        await _sink.waitForPosition(effectiveEnd);
        return StreamResponse.fromFile(request.range, _cacheFiles, headers);
      }

      final dataStreamPosition = streamPosition;
      final combinedCacheResponse = StreamResponse.combined(
        request.range,
        headers,
        _cacheFiles,
        _streamController.stream,
        dataStreamPosition,
        _downloader.streamConfig,
      );

      try {
        await _sink.waitForPosition(dataStreamPosition);
        return combinedCacheResponse;
      } catch (_) {
        combinedCacheResponse.cancel();
        rethrow;
      }
    });

    return true;
  }

  int? get sourceLength => _cachedHeaders?.sourceLength;
  int get downloadPosition => _position;
  int get streamPosition => downloadPosition - _pendingStreamBytes;
  int get filePosition => _sink.flushedBytes;
  Uri get sourceUrl => _downloader.sourceUrl;
  bool get isClosed => _completer.isCompleted;
  bool get isPaused => _paused;
}
