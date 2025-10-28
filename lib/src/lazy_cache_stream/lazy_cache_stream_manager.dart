import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http_cache_stream/src/etc/extensions.dart';

import '../models/config/stream_cache_config.dart';
import 'lazy_cache_stream.dart';

class LazyCacheStreamManager {
  final Uri serverUri;
  LazyCacheStreamManager(this.serverUri);
  final Map<String, LazyCacheStream> _streams = {};

  LazyCacheStream createLazyStream(
    final Uri sourceUrl, {
    required final Duration autoDisposeDelay,
    final File? file,
    final StreamCacheConfig? config,
  }) {
    final String key =
        md5.convert(utf8.encode(sourceUrl.requestKey)).toString();

    return _streams.putIfAbsent(key, () {
      final Uri lazyCacheUrl = sourceUrl.replaceOrigin(
        serverUri,
        queryParameters: {
          ...sourceUrl.queryParameters,
          _lazyStreamQueryKey: key,
        },
      );

      return LazyCacheStream(
        sourceUrl: sourceUrl,
        cacheUrl: lazyCacheUrl,
        autoDisposeDelay: autoDisposeDelay,
        file: file,
        config: config,
      );
    });
  }

  LazyCacheStream? getLazyStream(final Uri requestUri) {
    if (_streams.isEmpty) return null;
    return _streams[requestUri.queryParameters[_lazyStreamQueryKey]];
  }

  static const String _lazyStreamQueryKey = 'lstream';
}
