import 'dart:async';

import '../../models/files/cache_files.dart';
import '../../models/stream_response/stream_response_range.dart';

class CacheFileStream extends Stream<List<int>> {
  final StreamRange range;
  final CacheFiles cacheFiles;
  const CacheFileStream(this.range, this.cacheFiles);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return cacheFiles
        .activeCacheFile()
        .openRead(
          range.start,
          range.end,
        )
        .listen(
          onData,
          onError: onError,
          onDone: onDone,
          cancelOnError: cancelOnError,
        );
  }
}
