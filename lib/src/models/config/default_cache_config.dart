import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract class DefaultCacheConfig {
  static const bool copyCachedResponseHeaders = false;

  static const int maxBufferSize = 1024 * 1024 * 25; // 25 MB

  static const int minChunkSize = 1024 * 128; // 128 KB

  static const int rangeRequestSplitThreshold = 1024 * 1024 * 5; // 5 MB

  static const bool saveMetadata = true;

  static const bool savePartialCache = true;

  static const bool validateOutdatedCache = false;

  static Future<Directory> defaultCacheDirectory() async {
    final temporaryDirectory = await getTemporaryDirectory();
    return Directory(p.join(temporaryDirectory.path, 'http_cache_stream'));
  }
}
