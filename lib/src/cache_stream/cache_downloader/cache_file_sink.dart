import 'dart:io';

class CacheFileSink {
  final File partialCacheFile;
  CacheFileSink(this.partialCacheFile, final int start)
      : _sink = partialCacheFile.openWrite(
          mode: start > 0 ? FileMode.append : FileMode.write,
        );

  final IOSink _sink;

  void add(List<int> data) {
    return _sink.add(data);
  }

  Future<void> flush() {
    return _sink.flush();
  }

  Future<void> close() {
    _isClosed = true;
    return _sink.close();
  }

  bool _isClosed = false;
  bool get isClosed => _isClosed;
}
