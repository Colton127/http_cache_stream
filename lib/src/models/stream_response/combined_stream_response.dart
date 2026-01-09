import 'dart:async';
import 'dart:io';

import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:http_cache_stream/src/cache_stream/response_streams/cache_file_stream.dart';

import '../../cache_stream/response_streams/buffered_data_stream.dart';

/// A stream that combines data from the partial cache file and the cache download stream.
/// It first streams data from the partial cache file, and once the file is done, it switches to the download stream.
/// Upon initalization, immediately starts buffering data from the download stream.
class CombinedCacheStreamResponse extends StreamResponse {
  final CacheFileStream _fileStream;
  final BufferedDataStream _dataStream;
  final _controller = StreamController<List<int>>(sync: true);
  CombinedCacheStreamResponse._(
    super.range,
    super.responseHeaders,
    this._fileStream,
    this._dataStream,
  ) {
    _controller.onListen = _start;
    _controller.onCancel = cancel;
    _controller.onPause = () {
      _currentSubscription?.pause();
    };
    _controller.onResume = () {
      _currentSubscription?.resume();
    };
  }

  factory CombinedCacheStreamResponse(
    final IntRange range,
    final CachedResponseHeaders responseHeaders,
    final File partialCacheFile,
    final Stream<List<int>> dataStream,
    final int dataStreamPosition,
    final StreamCacheConfig streamConfig,
  ) {
    final sourceLength = responseHeaders.sourceLength;
    return CombinedCacheStreamResponse._(
      range,
      responseHeaders,
      CacheFileStream(
        partialCacheFile,
        IntRange.validate(range.start, dataStreamPosition, sourceLength), //Read upto dataStreamPosition from file
      ),
      BufferedDataStream(
        range: range,
        dataStream: dataStream,
        dataStreamPosition: dataStreamPosition,
        sourceLength: sourceLength,
        streamConfig: streamConfig,
      ),
    );
  }

  void _start() {
    void subscribe(final Stream<List<int>> stream, {required void Function() onDone}) {
      _currentSubscription = stream.listen(
        _controller.add,
        onError: (e) {
          _currentSubscription = null;
          cancel(e);
        },
        onDone: onDone,
        cancelOnError: true,
      );
    }

    try {
      subscribe(_fileStream, onDone: () {
        subscribe(_dataStream, onDone: () {
          _currentSubscription = null;
          cancel();
        });
      });
    } catch (e) {
      cancel(e);
    }
  }

  @override
  void cancel([Object? error]) {
    if (_controller.isClosed) return;
    //Always cancel data stream, it's possible that it was never listened to.
    _dataStream.cancel();
    _currentSubscription?.cancel().ignore();
    _currentSubscription = null;
    if (error != null) {
      _controller.addError(error);
    }
    _controller.close().ignore();
  }

  StreamSubscription<List<int>>? _currentSubscription;

  @override
  ResponseSource get source => ResponseSource.combined;

  @override
  Stream<List<int>> get stream => _controller.stream;
}
