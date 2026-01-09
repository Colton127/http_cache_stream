import 'dart:async';
import 'dart:io';

import '../../models/cache_files/cache_files.dart';

class CacheFileSink {
  final CacheFiles cacheFiles;
  CacheFileSink(this.cacheFiles, final int start)
      : _sink = cacheFiles.partial.openWrite(
          mode: start > 0 ? FileMode.append : FileMode.write,
        );

  final IOSink _sink;

  void add(List<int> data) {
    _sink.add(data);
  }

  Future<void> flush() {
    return _sink.flush();
  }

  Future<void> close() {
    _isClosed = true;
    return _sink.close();
  }

  File get partialCacheFile => cacheFiles.partial;
  bool _isClosed = false;
  bool get isClosed => _isClosed;
}
