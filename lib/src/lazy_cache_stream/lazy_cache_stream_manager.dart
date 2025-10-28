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

  LazyCacheStream createLazyStream({
    required final Uri sourceUrl,
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
        key: key,
        sourceUrl: sourceUrl,
        cacheUrl: lazyCacheUrl,
        file: file,
        config: config ?? StreamCacheConfig.init(),
      );
    });
  }

  LazyCacheStream? getLazyStream(final HttpRequest request) {
    if (_streams.isEmpty) return null;

    final Uri requestedUri = request.requestedUri;
    final Map<String, String> requestQueryParms = requestedUri.queryParameters;

    final LazyCacheStream? lazyCacheStream =
        _streams[requestQueryParms[_lazyStreamQueryKey]] ??
            _streams[request.headers.value(LazyCacheStream.headerName)];
    if (lazyCacheStream == null) return null;

    if (requestedUri.requestKey == lazyCacheStream.cacheUrl.requestKey) {
      return lazyCacheStream; //Direct match based on request key
    } else {
      ///The request differs from the original source URL, we must rewrite the sourceUrl to match the requested URI

      Map<String, String>? updatedQueryParameters;
      if (requestQueryParms.containsKey(_lazyStreamQueryKey)) {
        updatedQueryParameters = {...requestQueryParms}..remove(
            _lazyStreamQueryKey); //Remove lazy stream key from query parameters
      }

      return LazyCacheStream(
        sourceUrl: requestedUri.replaceOrigin(
          lazyCacheStream.sourceUrl,
          queryParameters: updatedQueryParameters,
        ),
        cacheUrl: requestedUri,
        file:
            null, //When rewriting the sourceUrl, the same file cannot be reused
        key: lazyCacheStream.key, //Preserve the key
        config: lazyCacheStream.config, //Reuse the config for consistency
      );
    }
  }

  static const String _lazyStreamQueryKey = 'lstream';
}
