import 'dart:io';

import 'package:http/http.dart';
import 'package:http_cache_stream/http_cache_stream.dart';

///Cache configuration for a single [HttpCacheStream]. Values set here override the global values set in [GlobalCacheConfig].
///
///When [useGlobalHeaders] is true, headers will be combined with the global headers, overriding any duplicates.
class StreamCacheConfig implements CacheConfiguration {
  StreamCacheConfig(this._global);
  final GlobalCacheConfig _global;

  ///Constructs a [StreamCacheConfig] using the global configuration from [HttpCacheManager].
  factory StreamCacheConfig.construct(final HttpCacheManager cacheManager) {
    return StreamCacheConfig(cacheManager.config);
  }

  ///When true, custom request and response headers set in [HttpCacheManager] are used.
  ///If headers are set for this [HttpCacheStream], they are combined with the global headers, overriding any duplicates.
  bool useGlobalHeaders = true;

  @override
  Map<String, String> get requestHeaders => _requestHeaders ??= {};
  @override
  Map<String, String> get responseHeaders => _responseHeaders ??= {};

  @override
  set responseHeaders(Map<String, String> value) {
    _responseHeaders = value;
  }

  @override
  set requestHeaders(Map<String, String> value) {
    _requestHeaders = value;
  }

  @override
  bool get saveAllHeaders {
    return _saveAllHeaders ?? _global.saveAllHeaders;
  }

  @override
  bool get copyCachedResponseHeaders {
    return _copyCachedResponseHeaders ?? _global.copyCachedResponseHeaders;
  }

  @override
  bool get validateOutdatedCache {
    return _validateOutdatedCache ?? _global.validateOutdatedCache;
  }

  @override
  bool get savePartialCache {
    return _savePartialCache ?? _global.savePartialCache;
  }

  @override
  bool get saveMetadata {
    return _saveMetadata ?? _global.saveMetadata;
  }

  @override
  int? get rangeRequestSplitThreshold {
    return switch (_useGlobalRangeRequestSplitThreshold) {
      true => _global.rangeRequestSplitThreshold,
      false => _rangeRequestSplitThreshold,
    };
  }

  @override
  int get maxBufferSize {
    return _maxBufferSize ?? _global.maxBufferSize;
  }

  @override
  int get minChunkSize {
    return _minChunkSize ?? _global.minChunkSize;
  }

  @override
  Duration get retryDelay {
    return _retryDelay ?? _global.retryDelay;
  }

  @override
  Duration get cacheRequestTimeout {
    return _requestTimeout ?? _global.cacheRequestTimeout;
  }

  @override
  set saveAllHeaders(bool value) {
    _saveAllHeaders = value;
  }

  @override
  set copyCachedResponseHeaders(bool value) {
    _copyCachedResponseHeaders = value;
  }

  @override
  set savePartialCache(bool value) {
    _savePartialCache = value;
  }

  @override
  set saveMetadata(bool value) {
    _saveMetadata = value;
  }

  @override
  set validateOutdatedCache(bool value) {
    _validateOutdatedCache = value;
  }

  @override
  set rangeRequestSplitThreshold(int? value) {
    _useGlobalRangeRequestSplitThreshold = false;
    _rangeRequestSplitThreshold = CacheConfiguration.validateRangeRequestSplitThreshold(value);
  }

  @override
  set maxBufferSize(int value) {
    _maxBufferSize = CacheConfiguration.validateMaxBufferSize(value);
  }

  @override
  set minChunkSize(int value) {
    _minChunkSize = CacheConfiguration.validateMinChunkSize(value);
  }

  @override
  set retryDelay(Duration value) {
    _retryDelay = value;
  }

  @override
  set cacheRequestTimeout(Duration value) {
    _requestTimeout = value;
  }

  ///Register a callback to be called when this stream's cache is completely downloaded and written to disk.
  void Function(File cacheFile)? onCacheDone;

  ///Returns an immutable map of all custom request headers.
  Map<String, String> combinedRequestHeaders() {
    return _combineHeaders(
      _global.requestHeaders,
      _requestHeaders,
      defaultHeaders: const {HttpHeaders.acceptEncodingHeader: 'identity'}, // Avoid compressed responses
    );
  }

  ///Returns an immutable map of all custom response headers.
  Map<String, String> combinedResponseHeaders() {
    return _combineHeaders(_global.responseHeaders, _responseHeaders);
  }

  ///Internal callback to be called when the cache is completely downloaded and written to disk.
  ///To register a callback, use [onCacheDone].
  void onCacheComplete(HttpCacheStream stream, File cacheFile) {
    onCacheDone?.call(cacheFile);
    _global.onCacheDone?.call(stream, cacheFile);
  }

  Map<String, String> _combineHeaders(
    final Map<String, String> global,
    final Map<String, String>? local, {
    final Map<String, String> defaultHeaders = const {},
  }) {
    final useGlobal = global.isNotEmpty && useGlobalHeaders;
    final useLocal = local != null && local.isNotEmpty;
    if (!useGlobal && !useLocal) return defaultHeaders;
    return Map.unmodifiable({
      ...defaultHeaders,
      if (useGlobal) ...global,
      if (useLocal) ...local,
    });
  }

  @override
  Client get httpClient => _global.httpClient;

  /// Stream-specific configuration
  bool _useGlobalRangeRequestSplitThreshold = true;
  bool? _copyCachedResponseHeaders;
  bool? _validateOutdatedCache;
  bool? _savePartialCache;
  bool? _saveMetadata;
  bool? _saveAllHeaders;
  int? _maxBufferSize;
  int? _minChunkSize;
  int? _rangeRequestSplitThreshold;
  Duration? _requestTimeout;
  Duration? _retryDelay;
  Map<String, String>? _requestHeaders;
  Map<String, String>? _responseHeaders;
}
