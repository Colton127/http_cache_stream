import 'dart:io';

import '../../http_cache_stream.dart';

class LazyCacheStream {
  final Uri sourceUrl;
  final Uri cacheUrl;
  final File? file;
  final StreamCacheConfig config;

  ///Unique key for this lazy cache stream, used in headers and query parameters.
  final String key;

  const LazyCacheStream({
    required this.key,
    required this.sourceUrl,
    required this.cacheUrl,
    required this.file,
    required this.config,
  });

  static const String headerName = 'x-lazy-cache-stream';

  ///Request header that can be used in making cache requests. This enables support for redirects and dynamic URLs (e.g., m3u8 playlists).
  ///Note that when using this header, the [file] parameter must be null, as the same file cannot be reused for different requests.
  Map<String, String> get requestHeader {
    assert(file == null,
        'Cache file must be null when using cacheRequestHeader, because the same file cannot be reused for different requests.');
    return Map.unmodifiable({headerName: key});
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LazyCacheStream &&
        other.key == key &&
        other.sourceUrl == sourceUrl &&
        other.cacheUrl == cacheUrl &&
        other.file?.path == file?.path &&
        other.config == config;
  }

  @override
  int get hashCode =>
      sourceUrl.hashCode ^
      cacheUrl.hashCode ^
      file.hashCode ^
      config.hashCode ^
      key.hashCode;
}
