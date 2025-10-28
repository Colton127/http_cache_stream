import 'dart:async';
import 'dart:io';

import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:http_cache_stream/src/models/cache_files/cache_file_type.dart';

class FileStreamResponse extends StreamResponse {
  final File file;
  @override
  final int? sourceLength;
  const FileStreamResponse(this.file, super.range, this.sourceLength);

  @override
  Stream<List<int>> get stream => FileStream(file, range);

  @override
  ResponseSource get source => ResponseSource.cacheFile;

  @override
  void close() {
    // No need to close the file stream, as it will be closed automatically when the stream is done.
  }
}

class FileStream extends Stream<List<int>> {
  final File file;
  final IntRange range;
  const FileStream(this.file, this.range);

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
