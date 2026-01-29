import 'dart:async';
import 'dart:typed_data';

import 'package:http_cache_stream/http_cache_stream.dart';

import '../../etc/extensions/stream_extensions.dart';
import '../../models/stream_response/stream_response_range.dart';
import 'cache_file_stream.dart';

///A stream that buffers data while waiting for a listener.
///Immediately begins buffering data from the source stream upon creation.
///Data from the source stream is clamped to the specified range. The specified range may be beyond the current position of the source stream, but never before it.
///If the buffered data exceeds the maximum buffer size, the stream is cancelled with an exception.
class BufferedDataStream extends Stream<List<int>> {
  final StreamRange range;
  final CacheFiles cacheFiles;
  final _controller = StreamController<List<int>>(sync: true);
  final _buffer = BytesBuilder(copy: false);
  StreamSubscription<List<int>>? _dataSubscription;
  bool _switchedToFileStream = false;

  BufferedDataStream({
    required this.range,
    required final Stream<List<int>> dataStream,
    required final int dataStreamPosition,
    required final StreamCacheConfig streamConfig,
    required this.cacheFiles, //Used as backup when buffer exceeds max size
  }) {
    if (dataStreamPosition > range.start) {
      throw RangeError('BufferedDataStream: dataStreamPosition ($dataStreamPosition) cannot be greater than range.start (${range.start})');
    }
    final maxBufferSize = streamConfig.maxBufferSize;
    bool done = false; //If source stream is done, or range end is reached
    bool ready = false; //If listener is present and not paused
    int addedBytes = 0; //Total bytes added to controller

    void flush() {
      if (_buffer.isNotEmpty) {
        addedBytes += _buffer.length;
        _controller.add(_buffer.takeBytes());
      }
      ready = !_controller.isPaused;
      if (done) _close();
    }

    void onDone() {
      done = true; //Mark stream as done
      _dataSubscription?.cancel().ignore();
      _dataSubscription = null;
      if (_buffer.isEmpty) _close();
    }

    void switchToFileStream() async {
      if (_switchedToFileStream) return;
      _switchedToFileStream = true;

      if (!_controller.hasListener || _controller.isClosed) {
        _close();
        return; //Upon listen, file stream will be started instead
      }
      _stopDataStream(); //Stop data stream and clear buffer
      _controller.clearCallbacks(); //[addStream] manages pausing/resuming /cancelling internally

      try {
        final fileRange = StreamRange.construct(range.start + addedBytes, range.end, range.sourceLength);
        await _controller.addStream(CacheFileStream(fileRange, cacheFiles));
      } catch (e) {
        if (!_controller.isClosed) _controller.addError(e);
      } finally {
        _controller.close().ignore();
      }
    }

    _dataSubscription = dataStream.listen(
      _rangeDataHandler(
        start: range.start,
        end: range.end,
        sourceLength: range.sourceLength,
        initPosition: dataStreamPosition,
        onCompletion: onDone,
        onData: (data) {
          assert(!_switchedToFileStream, 'BufferedDataStream: Data received after switching to file stream');

          if (ready) {
            assert(_buffer.isEmpty, 'BufferedDataStream: Buffer should be empty when stream has listener and is not paused');
            assert(!_controller.isPaused, 'BufferedDataStream: Stream should not be paused when ready is true');
            addedBytes += data.length;
            _controller.add(data);
          } else if (_buffer.length + data.length > maxBufferSize) {
            switchToFileStream();
          } else {
            _buffer.add(data);
          }
        },
      ),
      onDone: () {
        _dataSubscription = null;
        onDone();
      },
      onError: (e) {
        if (ready) {
          flush(); //Flush data before reporting error for event synchronization
          _controller.addError(e); //Allow listener to decide how to handle the error
        } else {
          _close(e);
        }
      },
      cancelOnError: false,
    );

    _controller.onCancel = _close; //Listener cancelled, discard buffered data
    _controller.onResume = flush; //Flush buffered data when listener resumes
    _controller.onPause = () {
      ready = false; //Buffer data while paused
    };
    _controller.onListen = () {
      scheduleMicrotask(flush); //Avoid synchronously writing to listener upon listen (listener may not be ready yet)
    };
  }

  void _stopDataStream() {
    _dataSubscription?.cancel().ignore();
    _dataSubscription = null;
    _buffer.clear();
  }

  void _close([Object? error]) {
    if (_controller.isClosed) return;
    _stopDataStream();
    _controller.clearCallbacks();
    if (error != null) {
      _controller.addError(error);
    }
    _controller.close().ignore();
  }

  ///Public API to cancel the stream and discard buffered data
  void cancel([Object error = const StreamResponseCancelledException()]) {
    if (_switchedToFileStream) return; //Already switched to file stream, cannot cancel
    _close(error);
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final stream = _switchedToFileStream ? CacheFileStream(range, cacheFiles) : _controller.stream; //If switched to file stream, bypass controller
    return stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

void Function(List<int>) _rangeDataHandler({
  required final int start,
  required final int? end,
  required final int? sourceLength,
  required final int initPosition,
  required final void Function(List<int>) onData,
  required final void Function() onCompletion,
}) {
  if (end != null && (sourceLength == null || sourceLength > end)) {
    int currentPosition = initPosition;
    return (List<int> data) {
      final int nextPosition = currentPosition + data.length;

      if (nextPosition >= end) {
        final int startOffset = start > currentPosition ? start - currentPosition : 0;
        final int endOffset = end - currentPosition;
        if (data.length >= endOffset && endOffset > startOffset) {
          if (data.length != endOffset || startOffset > 0) {
            data = data.sublist(startOffset, endOffset); //Clamp start and end
          }
          onData(data);
        }

        onCompletion(); //Close stream when end is reached
      } else if (start > currentPosition) {
        final int startOffset = start - currentPosition;
        if (data.length > startOffset) {
          onData(data.sublist(startOffset));
        }
      } else {
        onData(data);
      }

      currentPosition = nextPosition;
    };
  } else if (start > initPosition) {
    int currentPosition = initPosition;
    return (List<int> data) {
      final int nextPosition = currentPosition + data.length;

      if (start > currentPosition) {
        final int startOffset = start - currentPosition;
        if (startOffset >= data.length) {
          currentPosition = nextPosition;
          return; //Skip entire chunk
        }
        data = data.sublist(startOffset); //Clamp start
      }

      onData(data);
      currentPosition = nextPosition;
    };
  } else {
    return onData;
  }
}
