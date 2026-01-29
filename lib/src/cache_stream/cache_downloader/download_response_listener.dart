import 'dart:async';

import '../../etc/chunked_bytes_buffer.dart';
import '../../etc/timeout_timer.dart';
import '../../models/config/cache/stream_cache_config.dart';
import '../../models/exceptions/http_exceptions.dart';

class DownloadResponseListener {
  late final StreamSubscription<List<int>> _subscription;
  final ChunkedBytesBuffer _buffer;
  final TimeoutTimer _timeoutTimer;
  DownloadResponseListener(
    final Uri sourceUrl,
    final Stream<List<int>> stream,
    final void Function(List<int> data) onData,
    final StreamCacheConfig streamConfig,
  )   : _buffer = ChunkedBytesBuffer(onData, streamConfig.minChunkSize),
        _timeoutTimer = TimeoutTimer(streamConfig.readTimeout) {
    _subscription = stream.listen(
      (data) {
        _timeoutTimer.reset();
        _buffer.add(data);
      },
      onDone: () {
        _buffer.flush();
        _timeoutTimer.cancel();
        _completer.complete(true);
      },
      onError: (e) {
        _buffer.flush();
        _timeoutTimer.cancel();
        _completer.completeError(DownloadResponseException(sourceUrl, e));
      },
      cancelOnError: true,
    );
    _timeoutTimer.start(() {
      cancel(ReadTimedOutException(sourceUrl, _timeoutTimer.duration), flushBuffer: true);
    });
  }

  void cancel(final Object error, {final bool flushBuffer = true}) {
    if (isCompleted) return;
    _subscription.cancel().ignore();
    if (flushBuffer) {
      _buffer.flush();
    } else {
      _buffer.clear();
    }
    _timeoutTimer.cancel();
    _completer.completeError(error);
  }

  void pause() {
    _timeoutTimer.reset();
    _subscription.pause();
  }

  void resume() {
    _timeoutTimer.reset();
    _subscription.resume();
  }

  final _completer = Completer<bool>();
  bool get isCompleted => _completer.isCompleted;
  bool get isPaused => _subscription.isPaused;
  Future<bool> get done => _completer.future;
}
