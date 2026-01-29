import 'dart:io';

import 'package:http/http.dart';
import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef CacheFileResolver = File? Function(Uri sourceUrl);

/// A configuration class for [HttpCacheManager].
///
/// This class is used to configure the behavior for all [HttpCacheStream] instances,
/// including the cache directory, HTTP client, and header settings.
///
/// To create a default configuration with the standard cache directory, use [GlobalCacheConfig.defaultConfig].
class GlobalCacheConfig implements CacheConfiguration {
  GlobalCacheConfig({
    required this.cacheDirectory,
    int maxBufferSize = 1024 * 1024 * 25, // 25 MB
    int minChunkSize = 1024 * 64, // 64 KB
    int? rangeRequestSplitThreshold,
    Map<String, String>? requestHeaders,
    Map<String, String>? responseHeaders,
    this.retryDelay = const Duration(seconds: 5),
    this.customHttpClient,
    this.copyCachedResponseHeaders = false,
    this.validateOutdatedCache = false,
    this.savePartialCache = true,
    this.saveMetadata = true,
    this.saveAllHeaders = true,
    this.onCacheDone,
    this.cacheFileResolver,
    this.readTimeout = const Duration(seconds: 30),
  })  : httpClient = customHttpClient ?? Client(),
        requestHeaders = requestHeaders ?? {},
        responseHeaders = responseHeaders ?? {},
        _maxBufferSize = CacheConfiguration.validateMaxBufferSize(maxBufferSize),
        _minChunkSize = CacheConfiguration.validateMinChunkSize(minChunkSize),
        _rangeRequestSplitThreshold = CacheConfiguration.validateRangeRequestSplitThreshold(rangeRequestSplitThreshold);

  /// The directory where the cache files will be stored.
  final Directory cacheDirectory;

  @override
  final Client httpClient;

  /// The custom HTTP client to use for downloading cache.
  ///
  /// If null, a default HTTP client will be used.
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
    _rangeRequestSplitThreshold = CacheConfiguration.validateRangeRequestSplitThreshold(value);
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

  @override
  Duration readTimeout;

  @override
  Duration retryDelay;

  @override
  bool saveAllHeaders;

  /// Callback function fired when a cache stream download is completed.
  void Function(HttpCacheStream cacheStream, File cacheFile)? onCacheDone;

  /// Callback function to resolve a custom cache file for a given source URL.
  ///
  /// Called when cache streams are created to determine the file to use for caching.
  final CacheFileResolver? cacheFileResolver;

  /// Returns the default cache directory for the application.
  ///
  /// Useful when constructing a [GlobalCacheConfig] instance.
  static Future<Directory> defaultCacheDirectory() async {
    final temporaryDirectory = await getTemporaryDirectory();
    return Directory(p.join(temporaryDirectory.path, 'http_cache_stream'));
  }

  /// Initializes a [GlobalCacheConfig] with the default cache directory.
  ///
  /// To specify a custom cache directory, use the regular constructor.
  static Future<GlobalCacheConfig> defaultConfig({final Client? customHttpClient}) async {
    return GlobalCacheConfig(
      cacheDirectory: await defaultCacheDirectory(),
      customHttpClient: customHttpClient,
    );
  }
}
