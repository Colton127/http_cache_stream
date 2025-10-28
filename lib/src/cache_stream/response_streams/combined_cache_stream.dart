import 'dart:async';
import 'dart:io';

import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:http_cache_stream/src/cache_stream/response_streams/file_stream.dart';
import 'package:http_cache_stream/src/etc/byte_limit_transformer.dart';

/// A stream that combines data from the partial cache file and the cache download stream.
/// It first streams data from the partial cache file, and once the file is done, it switches to the download stream.
/// Upon initalization, immediately starts buffering data from the download stream.
class CombinedCacheStreamResponse extends StreamResponse {
  final Stream<List<int>> fileStream;
  final Stream<List<int>> dataStream;
  @override
  final int? sourceLength;
  final _controller = StreamController<List<int>>(sync: true);
  late final StreamSubscription<List<int>> _dataSubscription;
  StreamSubscription<List<int>>? _fileSubscription;
  CombinedCacheStreamResponse._(super.range, this.sourceLength,
      {required this.fileStream, required this.dataStream}) {
    _bufferLiveData();
    _init();
  }

  factory CombinedCacheStreamResponse.construct(
    final IntRange range,
    final File partialCacheFile,
    Stream<List<int>> dataStream,
    final int dataStreamPosition,
    final int? sourceLength,
  ) {
    final requestEnd = range.end;
    if (requestEnd != null &&
        requestEnd > dataStreamPosition &&
        (sourceLength == null || requestEnd < sourceLength)) {
      final streamEnd = requestEnd - dataStreamPosition;
      dataStream = dataStream.transform(ByteLimitTransformer(streamEnd));
    }
    return CombinedCacheStreamResponse._(
      range,
      sourceLength,
      fileStream: FileStream(
          partialCacheFile, IntRange(range.start, dataStreamPosition)),
      dataStream: dataStream,
    );
  }

  void _bufferLiveData() {
    _dataSubscription = dataStream.listen(
      _controller.add,
      onDone: close,
      onError: _controller.addError,
      cancelOnError: false, //Allow subscriber to cancel stream on error
    );
    _dataSubscription.pause(); //Pause data stream, buffering data
  }

  void _init() {
    _controller.onListen = () {
      _controller.onListen = null;
      _start();
    };
    _controller.onCancel = () {
      _controller.onCancel = null;
      close();
    };
    _controller.onPause = () => _currentSubscription.pause();
    _controller.onResume = () => _currentSubscription.resume();
  }

  void _start() {
    try {
      _fileSubscription = fileStream.listen(
        _controller.add,
        onDone:
            _streamLiveData, //Start streaming live data once file stream is done
        onError: _controller.addError,
      );
    } catch (e) {
      close(e); //File stream can throw error upon listen, handle it
    }
  }

  void _streamLiveData() {
    _fileSubscription = null;
    _dataSubscription.resume(); //Resume data stream, emitting buffered data
  }

  @override
  void close([Object? error]) {
    if (!_controller.isClosed) {
      _controller.onListen = null;
      _controller.onCancel = null;
      final fileSubscription = _fileSubscription;
      if (fileSubscription != null) {
        _fileSubscription = null;
        fileSubscription.cancel().ignore();
      }
      _dataSubscription.cancel().ignore();
      if (error != null && _controller.hasListener) {
        _controller.addError(error);
      }
      _controller.close().ignore();
    }
  }

  StreamSubscription<List<int>> get _currentSubscription =>
      _fileSubscription ?? _dataSubscription;

  @override
  ResponseSource get source => ResponseSource.cacheStream;

  @override
  Stream<List<int>> get stream => _controller.stream;
}
