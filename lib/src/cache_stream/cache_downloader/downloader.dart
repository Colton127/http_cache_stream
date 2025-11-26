import 'dart:async';
import 'dart:io';

import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:http_cache_stream/src/cache_stream/response_streams/download_stream.dart';
import 'package:http_cache_stream/src/etc/exceptions.dart';

import 'chunked_bytes_buffer.dart';

class Downloader {
  final Uri sourceUrl;
  final IntRange downloadRange;
  final StreamCacheConfig streamConfig;
  final Duration timeout;
  Downloader(
    this.sourceUrl,
    this.downloadRange,
    this.streamConfig, {
    this.timeout = const Duration(seconds: 30),
  });

  Future<void> download({
    ///If [onError] is provided, handles IO errors (e.g. connection errors) and calls [onError] with the error. Otherwise, closes the stream with the error.
    required final void Function(Object e) onError,
    required final void Function(CachedResponseHeaders responseHeaders)
        onHeaders,
    required final void Function(List<int> data) onData,
  }) async {
    assert(_buffer == null, 'Downloader is already downloading');

    final buffer = _buffer = ChunkedBytesBuffer(
      (List<int> data) {
        _receivedBytes += data.length;
        onData(data);
      },
      minChunkSize: streamConfig.minChunkSize,
    );
    if (_pauseCount > 0) {
      buffer.pause();
    }

    bool invalidCacheOccurred = false;

    try {
      while (isActive) {
        DownloadStream? downloadStream;
        try {
          downloadStream = await DownloadStream.open(
            sourceUrl,
            IntRange(position, downloadRange.end),
            streamConfig.httpClient,
            streamConfig.combinedRequestHeaders(),
          );
          if (!isActive) {
            throw DownloadStoppedException(
                sourceUrl); //Downloader was closed while waiting for the stream
          }
          onHeaders(downloadStream.cachedResponseHeaders);
          await _listenResponse(downloadStream, buffer);
        } on InvalidCacheException {
          invalidCacheOccurred =
              true; //Clear buffer on invalid cache to avoid sending invalid data
          rethrow;
        } catch (e) {
          downloadStream?.cancel();
          if (!isActive) {
            break;
          } else {
            onError(e);
            if (!buffer.isPaused) {
              buffer.flush();
            }
            await Future.delayed(Duration(seconds: 5)); //Wait before retrying
          }
        }
      }
    } finally {
      if (invalidCacheOccurred) {
        buffer.clear(); //Clear buffer if an InvalidCacheException occurred
      } else {
        if (buffer.isPaused) {
          await buffer
              .onResume; //Wait until resumed before flushing and closing
        }
        buffer.flush();
      }
      close();
    }
  }

  Future<void> _listenResponse(
    final Stream<List<int>> response,
    final ChunkedBytesBuffer buffer,
  ) {
    final subscriptionCompleter = _subscriptionCompleter = Completer<void>();
    bool receivedData = false;

    void completeError(DownloadException error) {
      if (subscriptionCompleter.isCompleted) return;
      subscriptionCompleter.completeError(error);
    }

    final subscription = response.listen(
      (data) {
        receivedData = true;
        buffer.add(data);
      },
      onDone: () {
        _done = true;
        if (!subscriptionCompleter.isCompleted) {
          subscriptionCompleter.complete();
        }
      },
      onError: (e) {
        completeError(DownloadException(sourceUrl, e.toString()));
      },
      cancelOnError: true,
    );

    final timeoutTimer = Timer.periodic(timeout, (t) {
      if (receivedData) {
        receivedData = false;
      } else if (!subscription.isPaused) {
        t.cancel();
        completeError(DownloadTimedOutException(sourceUrl, timeout));
      }
    });

    return subscriptionCompleter.future.whenComplete(() {
      _subscriptionCompleter = null;
      timeoutTimer.cancel();
      subscription.cancel();
    });
  }

  void close([Object? error]) {
    _closed = true;

    final subscriptionCompleter = _subscriptionCompleter;
    if (subscriptionCompleter != null && !subscriptionCompleter.isCompleted) {
      subscriptionCompleter
          .completeError(error ?? DownloadStoppedException(sourceUrl));
    }
  }

  ///Pauses the emission of data from the downloader. If [flush] is true, any buffered data will be flushed immediately.
  ///This does not pause the download. Rather, it pauses the emission of data to the consumer. New data will still be downloaded and buffered, but not emitted until resumed.
  void pauseEmission({bool flush = false}) {
    flush = flush && !isPaused;
    _pauseCount = _pauseCount <= 0 ? 1 : _pauseCount + 1;

    final buffer = _buffer;
    if (buffer != null) {
      buffer.pause();
      if (flush) buffer.flush();
    }
  }

  void resumeEmission() {
    if (_pauseCount > 1) {
      _pauseCount--;
    } else {
      _pauseCount = 0;
      _buffer?.resume();
    }
  }

  int _receivedBytes = 0;
  bool _done = false;
  Completer<void>? _subscriptionCompleter;
  ChunkedBytesBuffer? _buffer;
  int _pauseCount = 0;
  bool _closed = false;

  ///The number of bytes emitted by the downloader. This is not always the same as the position.
  int get receivedBytes => _receivedBytes;

  ///If the stream closed with a done event
  bool get isDone => _done;

  ///If the stream is currently active. This is true if the downloader is not closed and not done.
  bool get isActive => !isClosed && !isDone;

  ///The current position of the download, this is the sum of the start position and the received bytes.
  int get position => downloadRange.start + _receivedBytes;

  ///If the downloader has been closed. The downloader cannot be used after it is closed.
  bool get isClosed => _closed;

  ///If the stream is paused
  bool get isPaused {
    return _buffer?.isPaused ?? _pauseCount > 0;
  }
}

class DownloadException extends HttpException {
  DownloadException(Uri uri, String message)
      : super('Download Exception: $message', uri: uri);
}

class DownloadStoppedException extends DownloadException {
  DownloadStoppedException(Uri uri) : super(uri, 'Download stopped');
}

class DownloadTimedOutException extends DownloadException {
  DownloadTimedOutException(Uri uri, Duration duration)
      : super(uri, 'Timed out after $duration');
}
