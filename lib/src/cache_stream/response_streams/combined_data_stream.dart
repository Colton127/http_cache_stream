import 'dart:async';

import '../../../http_cache_stream.dart';
import '../../etc/extensions/stream_extensions.dart';
import '../../models/stream_response/stream_response_range.dart';
import 'buffered_data_stream.dart';
import 'cache_file_stream.dart';

///A stream that combines data from cache file and data stream
class CombinedDataStream extends Stream<List<int>> {
  final CacheFileStream _fileStream;
  final BufferedDataStream _dataStream;
  final _controller = StreamController<List<int>>(sync: true);
  CombinedDataStream._(this._fileStream, this._dataStream) {
    _controller.onCancel = _close;
    _controller.onPause = () => _currentSubscription?.pause();
    _controller.onResume = () => _currentSubscription?.resume();
    _controller.onListen = _start;
  }

  factory CombinedDataStream(
    final IntRange range,
    final CacheFiles cacheFiles,
    final Stream<List<int>> dataStream,
    final int dataStreamPosition,
    final int? sourceLength,
    final StreamCacheConfig streamConfig,
  ) {
    assert(() {
      final cacheFileSize = cacheFiles.activeCacheFile().statSync().size;
      if (cacheFileSize < dataStreamPosition) {
        throw StateError('CombinedDataStream: cacheFileSize ($cacheFileSize) is less than dataStreamPosition ($dataStreamPosition)');
      }
      return true;
    }());

    return CombinedDataStream._(
      CacheFileStream(
        StreamRange.construct(range.start, dataStreamPosition, sourceLength), //Read upto dataStreamPosition from file
        cacheFiles,
      ),
      BufferedDataStream(
        range: StreamRange.construct(dataStreamPosition, range.end, sourceLength), //Read from dataStreamPosition to range.end from data stream
        dataStream: dataStream,
        dataStreamPosition: dataStreamPosition,
        streamConfig: streamConfig,
        cacheFiles: cacheFiles,
      ),
    );
  }

  void _start() {
    void subscribe({required final Stream<List<int>> stream, required final void Function() onDone}) {
      assert(_currentSubscription == null, 'CombinedCacheStreamResponse: subscribe: _currentSubscription should be null when subscribing to a new stream');
      _currentSubscription = stream.listen(
        _controller.add,
        onError: (e) {
          _currentSubscription = null;
          _close(e);
        },
        onDone: () {
          _currentSubscription = null;
          onDone();
        },
        cancelOnError: true,
      );
    }

    try {
      subscribe(
        stream: _fileStream, //Start with file stream
        onDone: () {
          subscribe(
            stream: _dataStream, //Then switch to data stream
            onDone: _close, //Close controller when done
          );
        },
      );
    } catch (e) {
      _close(e);
    }
  }

  void _close([Object? error]) {
    if (_controller.isClosed) return;
    _dataStream.cancel(); //Always cancel data stream to free buffered data
    _currentSubscription?.cancel().ignore();
    _currentSubscription = null;
    _controller.clearCallbacks();
    if (error != null) {
      _controller.addError(error);
    }
    _controller.close().ignore();
  }

  ///Public API to cancel the stream and discard buffered data
  void cancel([Object error = const StreamResponseCancelledException()]) {
    _close(error);
  }

  StreamSubscription<List<int>>? _currentSubscription;

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
