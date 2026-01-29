import 'dart:async';

import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:http_cache_stream/src/cache_stream/response_streams/download_stream.dart';

import '../../etc/pause_counter.dart';
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
      while (isActive) {
        DownloadStream? downloadStream;
        try {
          if (_pauseCounter.isPaused) {
            await _pauseCounter.onResume;
            _checkActive();
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
          _checkActive();
          onHeaders(downloadStream.responseHeaders);
          _done = await (_responseListener = DownloadResponseListener(sourceUrl, downloadStream, onData, streamConfig)).done;
          _responseListener = null;
        } catch (e) {
          _responseListener = null;
          downloadStream?.cancel();
          if (e is InvalidCacheException) {
            rethrow;
          } else if (!isActive) {
            break;
          } else {
            onError(e);
            await (_pauseCounter.isPaused ? _pauseCounter.onResume : Future.delayed(streamConfig.retryDelay));
          }
        }
      }
    } finally {
      close();
    }
  }

  void _checkActive() {
    if (!isActive) {
      throw CacheDownloadStoppedException(sourceUrl);
    }
  }

  void close([Object? error]) {
    _closed = true;
    final responseListener = _responseListener;
    if (responseListener != null) {
      _responseListener = null;
      responseListener.cancel(error ?? CacheDownloadStoppedException(sourceUrl));
    }
    _pauseCounter.resume(force: true); //Break any pauses
  }

  void pause() {
    if (_closed) return;
    _pauseCounter.pause();
    _responseListener?.pause();
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
