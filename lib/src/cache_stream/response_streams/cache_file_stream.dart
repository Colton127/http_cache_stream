import 'dart:async';
import 'dart:io';

import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:http_cache_stream/src/models/cache_files/cache_file_types.dart';

class CacheFileStream extends Stream<List<int>> {
  final File file;
  final IntRange range;
  const CacheFileStream(this.file, this.range);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final stream = _activeCacheFile().openRead(range.start, range.end);
    return stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  ///In case the cache download was completed before listening, we need to return the complete cache file
  File _activeCacheFile() {
    if (CacheFileType.isPartial(file) && !file.existsSync()) {
      return CacheFileType.completeFile(file);
    }
    return file;
  }
}
