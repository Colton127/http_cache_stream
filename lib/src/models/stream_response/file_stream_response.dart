import 'dart:async';
import 'dart:io';

import 'package:http_cache_stream/http_cache_stream.dart';

import '../../cache_stream/response_streams/cache_file_stream.dart';

class FileStreamResponse extends StreamResponse {
  final File file;
  const FileStreamResponse(this.file, super.range, super.responseHeaders);

  @override
  Stream<List<int>> get stream => CacheFileStream(file, range);

  @override
  ResponseSource get source => ResponseSource.cacheFile;

  @override
  void cancel() {
    // No need to close the file stream, as it will be closed automatically when the stream is done.
  }
}
