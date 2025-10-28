import 'dart:io';

import '../../http_cache_stream.dart';

class LazyCacheStream {
  final Uri sourceUrl;
  final Uri cacheUrl;
  final File? file;
  final Duration autoDisposeDelay;
  final StreamCacheConfig? config;

  const LazyCacheStream({
    required this.sourceUrl,
    required this.cacheUrl,
    required this.autoDisposeDelay,
    required this.file,
    required this.config,
  }) : assert(autoDisposeDelay >= Duration.zero,
            'autoDisposeDelay must be non-negative');

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LazyCacheStream &&
        other.sourceUrl == sourceUrl &&
        other.cacheUrl == cacheUrl &&
        other.autoDisposeDelay == autoDisposeDelay &&
        other.file?.path == file?.path &&
        other.config == config;
  }

  @override
  int get hashCode =>
      sourceUrl.hashCode ^
      cacheUrl.hashCode ^
      autoDisposeDelay.hashCode ^
      file.hashCode ^
      config.hashCode;
}
