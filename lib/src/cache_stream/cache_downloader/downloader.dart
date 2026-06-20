import 'dart:async';

import 'package:http_cache_stream/src/cache_stream/response_streams/download_stream.dart';
import 'package:http_cache_stream/src/models/exceptions/invalid_cache_exceptions.dart';

import '../../etc/counters/pause_counter.dart';
import '../../models/cache_config/stream_cache_config.dart';
import '../../models/exceptions/http_exceptions.dart';
import '../../models/metadata/cached_response_headers.dart';
import '../../models/stream_requests/int_range.dart';
import 'download_response_listener.dart';

class Downloader {
  final Uri sourceUrl;
  final StreamCacheConfig streamConfig;
  Downloader(
    this.sourceUrl,
    this.streamConfig,
  );
  bool _done = false;
  bool _closed = false;
  DownloadResponseListener? _responseListener;
  final _pauseCounter = PauseCounter();

  Future<void> download({
    required final IntRange Function() downloadRange,
    required final void Function(Object e) onError,
    required final void Function(CachedResponseHeaders responseHeaders) onHeaders,
    required final void Function(List<int> data) onData,
  }) async {
    try {
      void checkActive() {
        if (!isActive) {
          throw DownloadStoppedException(sourceUrl);
        }
      }

      while (isActive) {
        DownloadStream? downloadStream;
        try {
          if (_pauseCounter.isPaused) {
            await _pauseCounter.onResume;
            checkActive();
          }
          downloadStream = await DownloadStream.open(
            sourceUrl,
            downloadRange(),
            streamConfig,
          );
          if (_pauseCounter.isPaused) {
            final readTimeout = streamConfig.readTimeout;
            await _pauseCounter.onResume.timeout(readTimeout, onTimeout: () => throw ReadTimedOutException(sourceUrl, readTimeout));
          }
          checkActive();
          onHeaders(downloadStream.responseHeaders);
          final responseListener = DownloadResponseListener(sourceUrl, downloadStream, onData, streamConfig);
          _responseListener = responseListener;
          try {
            _done = await responseListener.done;
          } finally {
            _responseListener = null;
          }
        } catch (e) {
          downloadStream?.cancel();
          if (e is InvalidCacheException) {
            rethrow;
          } else if (!isActive) {
            break;
          } else {
            onError(e);
            await (_pauseCounter.isPaused ? _pauseCounter.onResume : Future.delayed(const Duration(seconds: 5)));
          }
        }
      }
    } finally {
      close();
    }
  }

  void close([Object? exception]) {
    _closed = true;
    final responseListener = _responseListener;
    if (responseListener != null) {
      _responseListener = null;
      responseListener.cancel(exception ?? DownloadStoppedException(sourceUrl), flushBuffer: exception is! InvalidCacheException);
    }
    _pauseCounter.resume(force: true); //Break any pauses
  }

  void pause({bool flushBuffer = true}) {
    if (_closed) return;
    _pauseCounter.pause();
    _responseListener?.pause(flushBuffer: flushBuffer);
  }

  void resume() {
    _pauseCounter.resume();
    _responseListener?.resume();
  }

  ///If the stream closed with a done event
  bool get isDone => _done;

  ///If the stream is currently active. This is true if the downloader is not closed and not done.
  bool get isActive => !isClosed && !isDone;

  ///If the downloader has been closed. The downloader cannot be used after it is closed.
  bool get isClosed => _closed;

  ///If the stream is paused
  bool get isPaused => _pauseCounter.isPaused;
}
