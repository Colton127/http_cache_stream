import 'dart:io';

import 'package:http/http.dart';
import 'package:http_cache_stream/src/models/cache_config/cache_config.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../cache_stream/http_cache_stream.dart';
import '../cache_files/cache_file_resolver.dart';
import 'stream_lifecycle_config.dart';

/// A configuration class for [HttpCacheManager].
///
/// This class is used to configure the behavior for all [HttpCacheStream] instances,
/// including the cache directory, HTTP client, and header settings.
class GlobalCacheConfig implements CacheConfiguration {
  GlobalCacheConfig({
    required this.cacheDirectory,
    int maxBufferSize = 1024 * 1024 * 25,
    int minChunkSize = 1024 * 64, // 64 KB
    int? rangeRequestSplitThreshold,
    Map<String, String>? requestHeaders,
    Map<String, String>? responseHeaders,
    this.lifecycleConfig = const StreamLifecycleConfig(),
    this.customHttpClient,
    this.copyCachedResponseHeaders = false,
    this.validateOutdatedCache = false,
    this.savePartialCache = true,
    this.saveMetadata = true,
    this.saveAllHeaders = true,
    this.onCacheDone,
    this.requestTimeout = const Duration(seconds: 60),
    this.readTimeout = const Duration(seconds: 30),
    this.cacheFileResolver = defaultCacheFileResolver,
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
  Duration requestTimeout;

  @override
  bool saveAllHeaders;

  @override
  StreamLifecycleConfig lifecycleConfig;

  /// A function that takes the cache directory and source URL, and returns a [File] where the cache should be stored.
  /// This allows for custom file naming and organization strategies. By default, it generates a file path based on the URL structure.
  /// This function is called for every cache stream, unless if a custom file is provided when creating the cache stream.
  final CacheFileResolver cacheFileResolver;

  @override
  CacheCompleteCallback? onCacheDone;

  /// Returns the default cache directory for the application.
  ///
  /// Useful when constructing a [GlobalCacheConfig] instance.
  static Future<Directory> defaultCacheDirectory() async {
    final temporaryDirectory = await getTemporaryDirectory();
    return Directory(p.join(temporaryDirectory.path, 'http_cache_stream'));
  }
}
