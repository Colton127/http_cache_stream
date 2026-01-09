import 'dart:async';
import 'dart:io';

import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:http_cache_stream/src/cache_stream/response_streams/download_stream.dart';
import 'package:http_cache_stream/src/models/exceptions.dart';

import '../../etc/chunked_bytes_buffer.dart';

class Downloader {
  final Uri sourceUrl;
  final IntRange downloadRange;
  final StreamCacheConfig streamConfig;
  final Duration timeout;
  Downloader(
    this.sourceUrl,
    this.downloadRange,
    this.streamConfig, {
    this.timeout = const Duration(seconds: 15),
  });

  Future<void> download({
    ///If [onError] is provided, handles IO errors (e.g. connection errors) and calls [onError] with the error. Otherwise, closes the stream with the error.
    required final void Function(Object e) onError,
    required final void Function(CachedResponseHeaders responseHeaders) onHeaders,
    required final void Function(List<int> data) onData,
  }) async {
    assert(_buffer == null, 'Downloader is already downloading');

    final buffer = _buffer = ChunkedBytesBuffer(
      (data) {
        _receivedBytes += data.length;
        onData(data);
      },
      onBufferFilled: (isFull) {
        if (isFull) {
          _responseListener?.pause();
        } else {
          _responseListener?.resume();
        }
      },
      minChunkSize: streamConfig.minChunkSize,
      maxBufferSize: streamConfig.maxBufferSize,
    );
    if (_pauseCount > 0) {
      buffer.pause();
    }

    void checkActive() {
      if (!isActive) {
        throw DownloadStoppedException(sourceUrl);
      }
    }

    try {
      while (isActive) {
        DownloadStream? downloadStream;
        try {
          if (buffer.isPaused) {
            await buffer.onResume;
            checkActive(); //Check if still active after resuming
          }
          downloadStream = await DownloadStream.open(
            sourceUrl,
            IntRange.validate(position, downloadRange.end),
            streamConfig.httpClient,
            streamConfig.combinedRequestHeaders(),
          );
          checkActive(); //Async gap, check if still active
          onHeaders(downloadStream.responseHeaders);
          _done = await _listenResponse(downloadStream, buffer);
        } catch (e) {
          downloadStream?.cancel();
          if (e is InvalidCacheException) {
            buffer.clear(); //Clear the buffer to prevent further data addition
            rethrow; //Invalid cache exceptions are rethrown to be handled by the caller
          } else if (!isActive) {
            break;
          } else {
            onError(e);
            if (!buffer.isPaused) {
              buffer.flush();
            }
            await Future.delayed(streamConfig.retryDelay); //Wait before retrying
          }
        }
      }
    } finally {
      if (!buffer.isEmpty) {
        if (buffer.isPaused) {
          await buffer.onResume; //Wait until resumed before flushing
        }
        buffer.flush();
      }
      close();
    }
  }

  Future<bool> _listenResponse(
    final Stream<List<int>> response,
    final ChunkedBytesBuffer buffer,
  ) {
    final responseListener = _ResponseListener(response, buffer.add);
    _responseListener = responseListener;

    int lastReceivedBytes = receivedBytes;
    final timeoutTimer = Timer.periodic(timeout, (t) {
      if (lastReceivedBytes != receivedBytes) {
        lastReceivedBytes = receivedBytes;
      } else if (!responseListener.isPaused && buffer.isEmpty) {
        t.cancel();
        responseListener.cancel(DownloadTimedOutException(sourceUrl, timeout));
      }
    });

    return responseListener.future.whenComplete(() {
      _responseListener = null;
      timeoutTimer.cancel();
    });
  }

  void close([Object? error]) {
    _closed = true;
    final responseListener = _responseListener;

    if (responseListener != null) {
      _responseListener = null;
      if (!responseListener.isCompleted) {
        responseListener.cancel(error ?? DownloadStoppedException(sourceUrl));
      }
    }
  }

  //Pauses the emission of data from the downloader. If [flush] is true, any buffered data will be flushed immediately.
  //This does not pause the download. Rather, it pauses the emission of data to the consumer. New data will still be downloaded and buffered, but not emitted until resumed.
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

  ///The number of bytes received from the current stream. This is not always the same as the position.
  int get receivedBytes => _receivedBytes;

  ///If the stream closed with a done event
  bool get isDone => _done;

  ///If the stream is currently active. This is true if the downloader is not closed and not done.
  bool get isActive => !isClosed && !isDone;

  ///The current position of the stream, this is the sum of the start position and the received bytes.
  int get position => downloadRange.start + _receivedBytes;

  ///If the downloader has been closed. The downloader cannot be used after it is closed.
  bool get isClosed => _closed;

  ///If the stream is paused
  bool get isPaused {
    return _buffer?.isPaused == true || (_responseListener?.isPaused ?? _pauseCount > 0);
  }

  _ResponseListener? _responseListener;
  int _receivedBytes = 0;
  bool _done = false;
  ChunkedBytesBuffer? _buffer;
  int _pauseCount = 0;
  bool _closed = false;
}

class DownloadException extends HttpException {
  DownloadException(Uri uri, String message) : super('Download Exception: $message', uri: uri);
}

class DownloadStoppedException extends DownloadException {
  DownloadStoppedException(Uri uri) : super(uri, 'Download stopped');
}

class DownloadTimedOutException extends DownloadException {
  DownloadTimedOutException(Uri uri, Duration duration) : super(uri, 'Timed out after $duration');
}

class _ResponseListener {
  late final StreamSubscription<List<int>> _subscription;
  _ResponseListener(
    final Stream<List<int>> response,
    final void Function(List<int> data) onData,
  ) {
    _subscription = response.listen(
      onData,
      onDone: () {
        _completer.complete(true);
      },
      onError: (e) {
        _completer.completeError(e);
      },
      cancelOnError: true,
    );
  }

  void cancel(final Object error) {
    if (isCompleted) return;
    _subscription.cancel().ignore();
    _completer.completeError(error);
  }

  void pause() => _subscription.pause();
  void resume() => _subscription.resume();

  final _completer = Completer<bool>();
  bool get isCompleted => _completer.isCompleted;
  bool get isPaused => _subscription.isPaused;
  Future<bool> get future => _completer.future;
}
