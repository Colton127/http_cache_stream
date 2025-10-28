import 'dart:io';

import 'package:http/http.dart';
import 'package:http_cache_stream/http_cache_stream.dart';

import 'default_cache_config.dart';

/// A singleton configuration class for [HttpCacheManager].
/// This class is used to configure the behavior for all [HttpCacheStream]'s, including the cache directory, HTTP client, request and response headers, and other settings.
/// Hint: You may obtain the default cache directory using the static method `GlobalCacheConfig.defaultCacheDirectory()`.
class GlobalCacheConfig implements CacheConfiguration {
  GlobalCacheConfig({
    required this.cacheDirectory,
    int maxBufferSize = DefaultCacheConfig.maxBufferSize,
    int minChunkSize = DefaultCacheConfig.minChunkSize,
    int? rangeRequestSplitThreshold =
        DefaultCacheConfig.rangeRequestSplitThreshold,
    Map<String, String>? requestHeaders,
    Map<String, String>? responseHeaders,
    this.customHttpClient,
    this.copyCachedResponseHeaders =
        DefaultCacheConfig.copyCachedResponseHeaders,
    this.validateOutdatedCache = DefaultCacheConfig.validateOutdatedCache,
    this.savePartialCache = DefaultCacheConfig.savePartialCache,
    this.saveMetadata = DefaultCacheConfig.saveMetadata,
    this.onCacheDone,
  })  : httpClient = customHttpClient ?? Client(),
        requestHeaders = requestHeaders ?? {},
        responseHeaders = responseHeaders ?? {},
        _maxBufferSize =
            CacheConfiguration.validateMaxBufferSize(maxBufferSize),
        _minChunkSize = CacheConfiguration.validateMinChunkSize(minChunkSize),
        _rangeRequestSplitThreshold =
            CacheConfiguration.validateRangeRequestSplitThreshold(
                rangeRequestSplitThreshold);

  final Directory cacheDirectory;

  @override
  final Client httpClient;

  /// The custom HTTP client to use for downloading cache. If null, a default HTTP client will be used.
  final Client? customHttpClient;

  @override
  Map<String, String> requestHeaders;
  @override
  Map<String, String> responseHeaders;

  @override
  bool copyCachedResponseHeaders;

  @override
  bool validateOutdatedCache;

  @override
  bool savePartialCache;

  @override
  bool saveMetadata;

  int? _rangeRequestSplitThreshold;
  @override
  int? get rangeRequestSplitThreshold => _rangeRequestSplitThreshold;
  @override
  set rangeRequestSplitThreshold(int? value) {
    _rangeRequestSplitThreshold =
        CacheConfiguration.validateRangeRequestSplitThreshold(value);
  }

  int _minChunkSize;
  @override
  int get minChunkSize => _minChunkSize;
  @override
  set minChunkSize(int value) {
    _minChunkSize = CacheConfiguration.validateMinChunkSize(value);
  }

  int _maxBufferSize;
  @override
  int get maxBufferSize => _maxBufferSize;
  @override
  set maxBufferSize(int value) {
    _maxBufferSize = CacheConfiguration.validateMaxBufferSize(value);
  }

  /// Register a callback function to be called when a cache stream download is completed.
  void Function(HttpCacheStream cacheStream, File cacheFile)? onCacheDone;

  /// Returns the default cache directory for the application. Useful when constructing a [GlobalCacheConfig] instance.
  static Future<Directory> defaultCacheDirectory() =>
      DefaultCacheConfig.defaultCacheDirectory();

  /// Initializes a [GlobalCacheConfig] instance with optional parameters.
  /// If [cacheDir] is not provided, the default cache directory will be used.
  /// If [customHttpClient] is not provided, a default HTTP client will be used.
  static Future<GlobalCacheConfig> init({
    final Directory? cacheDir,
    final Client? customHttpClient,
  }) async {
    return GlobalCacheConfig(
      cacheDirectory: cacheDir ?? await defaultCacheDirectory(),
      customHttpClient: customHttpClient,
    );
  }
}
