import 'dart:async';
import 'dart:typed_data';

import 'package:http_cache_stream/http_cache_stream.dart';

import '../../models/exceptions.dart';
import '../../models/stream_requests/stream_extensions.dart';

class BufferedDataStream extends Stream<List<int>> {
  final _controller = StreamController<List<int>>(sync: true);
  StreamSubscription<List<int>>? _dataSubscription;
  final _buffer = BytesBuilder(copy: false);

  BufferedDataStream({
    required final IntRange range,
    required final Stream<List<int>> dataStream,
    required final int dataStreamPosition,
    required final int? sourceLength,
    required final StreamCacheConfig streamConfig,
  }) {
    final maxBufferSize = streamConfig.maxBufferSize;

    _dataSubscription = dataStream.listen(
      _rangeDataHandler(
        start: range.start,
        end: range.end,
        initPosition: dataStreamPosition,
        sourceLength: sourceLength,
        onCompletion: () => _close(done: true),
        onData: (data) {
          if (!_controller.isPaused) {
            assert(_buffer.isEmpty, 'BufferedDataStream: Buffer should be empty when stream has listener and is not paused');
            _controller.add(data);
          } else {
            _buffer.add(data);
            if (_buffer.length > maxBufferSize) {
              _controller.addError(StateError('BufferedDataStream: Buffer exceeded maximum maxBufferSize of $maxBufferSize bytes'));
              _close(done: false);
            }
          }
        },
      ),
      onDone: () {
        _dataSubscription = null;
        _close(done: true);
      },
      onError: (e) {
        if (!_controller.isPaused) {
          _flush(); //Flush data before reporting error for event synchronization
          _controller.addError(e); //Allow listener to decide how to handle the error
        } else {
          _controller.addError(e);
          _close(done: false);
        }
      },
      cancelOnError: false,
    );

    _controller.onCancel = cancel; //Listener cancelled, discard buffered data
    _controller.onListen = _flush;
    _controller.onResume = _flush;
  }

  void _flush() {
    assert(_controller.hasListener, 'BufferedDataStream: Flush should only be called when there is a listener');
    if (_buffer.isNotEmpty) {
      _controller.add(_buffer.takeBytes());
    }
  }

//A non-listened streamController may indefinitely retain buffered data even after source is done.
//[cancel] needs ability to clear buffered data if no listener was ever attached. In this instance, we'll have to propagate an error to indicate that the stream was cancelled before being listened to.
  void _close({required final bool done}) {
    if (_controller.isClosed) return;
    _dataSubscription?.cancel().ignore();
    _dataSubscription = null;

    if (done) {
      if (_controller.hasListener) {
        _flush(); //Flush any remaining buffered data to listener
      } else {
        _controller.onListen = () => _close(done: true); //Postpone close until listened to
        return;
      }
    } else {
      _buffer.clear();
      _controller.addError(StreamResponseClosedException());
    }

    _controller.clearCallbacks();
    _controller.close().ignore();
  }

  ///Public API to cancel the stream and discard buffered data
  void cancel() {
    _close(done: false);
  }

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

void Function(List<int>) _rangeDataHandler({
  required final int start,
  required final int? end,
  required final int initPosition,
  required final int? sourceLength,
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
