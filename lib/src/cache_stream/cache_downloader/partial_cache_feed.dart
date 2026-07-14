import 'dart:async';

/// Publishes how many bytes of an active download have been safely flushed to
/// the partial cache file, and whether the download has terminated.
///
/// Any number of readers can follow the file as it grows by awaiting
/// [waitForData], without a single byte of response data being buffered in
/// memory. Waiters are never completed with an error; readers inspect
/// [finishError] after draining the flushed data, so a reader always serves
/// everything that reached disk before surfacing a failure.
class PartialCacheFeed {
  PartialCacheFeed(final int initialPosition)
      : _flushedPosition = initialPosition;

  int _flushedPosition;
  bool _finished = false;
  Object? _finishError;
  final List<({int position, Completer<void> completer})> _waiters = [];

  ///Bytes of the partial cache file that are flushed and safe to read from disk.
  int get flushedPosition => _flushedPosition;

  ///Whether the download has terminated. Once finished, [flushedPosition] is final.
  bool get isFinished => _finished;

  ///The terminal error, if the download stopped before completing. Null when the download completed normally, or is still active.
  Object? get finishError => _finishError;

  ///Advances [flushedPosition] and wakes readers waiting below the new position.
  void update(final int flushedPosition) {
    assert(flushedPosition >= _flushedPosition,
        'PartialCacheFeed: flushedPosition cannot move backwards ($flushedPosition < $_flushedPosition)');
    if (flushedPosition <= _flushedPosition) return;
    _flushedPosition = flushedPosition;
    if (_waiters.isEmpty) return;
    for (int i = _waiters.length - 1; i >= 0; i--) {
      if (_flushedPosition > _waiters[i].position) {
        _waiters.removeAt(i).completer.complete();
      }
    }
  }

  ///Marks the download as terminated and wakes all waiting readers.
  ///Provide [error] when the download stopped before flushing all data; leave null when it completed normally.
  void finish([final Object? error]) {
    if (_finished) return;
    _finished = true;
    _finishError = error;
    for (final waiter in _waiters) {
      waiter.completer.complete();
    }
    _waiters.clear();
  }

  ///Completes when [flushedPosition] exceeds [position], or the feed finishes.
  ///Never completes with an error; check [finishError] after completion.
  Future<void> waitForData(final int position) {
    if (_finished || _flushedPosition > position) return Future.value();
    final completer = Completer<void>();
    _waiters.add((position: position, completer: completer));
    return completer.future;
  }
}
