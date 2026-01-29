import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_cache_stream/src/cache_server/local_cache_server.dart';
import 'package:http_cache_stream/src/etc/extensions/uri_extensions.dart';

import '../../http_cache_stream.dart';
import '../etc/extensions/future_extensions.dart';
import '../models/files/cache_file_type.dart';

/// Manages the local HTTP server and `HttpCacheStream` instances.
///
/// Use [init] to initialize the manager before creating streams.
class HttpCacheManager {
  final LocalCacheServer _server;

  /// The global configuration used for all streams managed by this manager.
  final GlobalCacheConfig config;

  final Map<String, HttpCacheStream> _streams = {};
  final List<HttpCacheServer> _cacheServers = [];
  HttpCacheManager._(this._server, this.config) {
    _server.start((request) {
      final cacheStream = getExistingStream(request.uri);
      if (cacheStream != null) {
        return request.stream(cacheStream);
      } else {
        request.close(HttpStatus.serviceUnavailable);
        return Future.value();
      }
    });
  }

  /// Create a [HttpCacheStream] instance for the given URL. If an instance already exists, the existing instance will be returned.
  ///
  /// Use [file] to specify the output file to save the downloaded content to. If not provided, a file will be created in the cache directory (recommended).
  HttpCacheStream createStream(
    final Uri sourceUrl, {
    final File? file,
    final StreamCacheConfig? config,
  }) {
    assert(!isDisposed, 'HttpCacheManager is disposed. Cannot create new streams.');
    final existingStream = getExistingStream(sourceUrl);
    if (existingStream != null && !existingStream.isDisposed) {
      existingStream.retain(); //Retain the stream to prevent it from being disposed
      return existingStream;
    }
    final cacheStream = HttpCacheStream(
      sourceUrl: sourceUrl,
      cacheUrl: _server.getCacheUrl(sourceUrl),
      files: _resolveCacheFiles(sourceUrl, file),
      config: config ?? createStreamConfig(),
    );
    final key = sourceUrl.requestKey;
    cacheStream.future.onComplete(
      () => _streams.remove(key),
    ); //Remove when stream is disposed
    _streams[key] = cacheStream; //Add to the stream map
    return cacheStream;
  }

  /// Creates a [HttpCacheServer] instance for a source Uri. This server will redirect requests to the given source and create [HttpCacheStream] instances for each request.
  ///
  /// [autoDisposeDelay] is the delay before a stream is disposed after all requests are done.
  /// [serverConfig] is the configuration for the local cache server. If not provided, a default configuration will be used.
  /// [StreamCacheConfig] is the configuration used to create [HttpCacheStream] instances for requests to this server. If not provided, the global stream config will be used.
  Future<HttpCacheServer> createServer(
    final Uri source, {
    final Duration autoDisposeDelay = const Duration(seconds: 15),
    final CacheServerConfig? serverConfig,
    final StreamCacheConfig? streamConfig,
  }) async {
    final cacheServer = HttpCacheServer(
      source.originUri,
      await LocalCacheServer.init(serverConfig),
      autoDisposeDelay,
      streamConfig ?? createStreamConfig(),
      createStream,
    );
    _cacheServers.add(cacheServer);
    cacheServer.future.onComplete(() => _cacheServers.remove(cacheServer));
    return cacheServer;
  }

  /// Downloads URL to file without creating a stream.
  ///
  /// Useful for pre-caching content.
  Future<File> preCacheUrl(final Uri sourceUrl, {final File? cacheFile}) async {
    final completeCacheFile = getCacheFiles(sourceUrl, cacheFile).complete;
    if (completeCacheFile.existsSync()) {
      return completeCacheFile;
    }

    final cacheStream = createStream(sourceUrl, file: cacheFile);
    try {
      return await cacheStream.download();
    } finally {
      cacheStream.dispose().ignore();
    }
  }

  /// Deletes cache. Does not modify files used by active [HttpCacheStream] instances.
  ///
  /// Set [partialOnly] to true to only delete partial downloads.
  Future<void> deleteCache({bool partialOnly = false}) async {
    if (!partialOnly && _streams.isEmpty) {
      if (cacheDir.existsSync()) {
        await cacheDir.delete(recursive: true);
      }
      return;
    }
    await for (final file in inactiveCacheFiles()) {
      if (partialOnly && !CacheFileType.isPartial(file)) {
        if (!CacheFileType.isMetadata(file)) continue;
        final completedCacheFile = File(
          file.path.replaceFirst(CacheFileType.metadata.extension, ''),
        );
        if (completedCacheFile.existsSync()) {
          continue; //Do not delete metadata if the cache file exists
        }
      }
      await file.delete();
    }
  }

  Stream<File> inactiveCacheFiles() async* {
    if (!cacheDir.existsSync()) return;
    final Set<String> activeFilePaths = {};
    for (final stream in allStreams) {
      activeFilePaths.addAll(stream.metadata.cacheFiles.paths);
    }
    await for (final entry in cacheDir.list(recursive: true, followLinks: false)) {
      if (entry is File && !activeFilePaths.contains(entry.path)) {
        yield entry;
      }
    }
  }

  ///Get a list of [CacheMetadata].
  ///
  ///Specify [active] to filter between metadata for active and inactive [HttpCacheStream] instances. If null, all [CacheMetadata] will be returned.
  Future<List<CacheMetadata>> cacheMetadataList({final bool? active}) async {
    final List<CacheMetadata> cacheMetadata = [];
    if (active != false) {
      cacheMetadata.addAll(allStreams.map((stream) => stream.metadata));
    }
    if (active != true) {
      await for (final file in inactiveCacheFiles().where(
        CacheFileType.isMetadata,
      )) {
        final savedMetadata = CacheMetadata.load(file);
        if (savedMetadata != null) {
          cacheMetadata.add(savedMetadata);
        }
      }
    }
    return cacheMetadata;
  }

  ///Get the [CacheMetadata] for the given URL or input [cacheFile]. Returns null if the metadata does not exist.
  CacheMetadata? getCacheMetadata(final Uri sourceUrl, [File? cacheFile]) {
    return getExistingStream(sourceUrl)?.metadata ?? CacheMetadata.fromCacheFiles(_resolveCacheFiles(sourceUrl, cacheFile));
  }

  ///Gets [CacheFiles] for the given URL or input [cacheFile]. Does not check if any cache files exists.
  CacheFiles getCacheFiles(final Uri sourceUrl, [File? cacheFile]) {
    return getExistingStream(sourceUrl)?.files ?? _resolveCacheFiles(sourceUrl, cacheFile);
  }

  /// Returns the existing [HttpCacheStream] for the given URL, or null if it doesn't exist.
  /// The input [url] can either be [sourceUrl] or [cacheUrl].
  HttpCacheStream? getExistingStream(final Uri url) {
    return _streams[url.requestKey];
  }

  ///Returns the existing [HttpCacheServer] for the given source URL, or null if it doesn't exist.
  HttpCacheServer? getExistingServer(final Uri source, [final CacheServerConfig? serverConfig]) {
    for (final server in _cacheServers) {
      if (UriExtensions.isSameOrigin(source, server.source)) {
        if (serverConfig != null) {
          if (serverConfig.host != null && serverConfig.host != server.uri.host) {
            continue;
          }
          if ((serverConfig.port ?? 0) != 0 && serverConfig.port != server.uri.port) {
            continue;
          }
        }
        return server;
      }
    }

    return null;
  }

  CacheFiles _resolveCacheFiles(Uri sourceUrl, [File? file]) {
    file ??= config.cacheFileResolver?.call(sourceUrl);
    return file != null ? CacheFiles.fromFile(file) : CacheFiles.fromUrl(config.cacheDirectory, sourceUrl);
  }

  ///Create a [StreamCacheConfig] that inherits the current [GlobalCacheConfig]. This config is used to create [HttpCacheStream] instances.
  StreamCacheConfig createStreamConfig() => StreamCacheConfig.construct(this);

  ///Disposes the current [HttpCacheManager] and all resources.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    HttpCacheManager._instance = null;

    try {
      await _server.close();
    } finally {
      for (final stream in _streams.values.toList()) {
        stream.dispose(force: true).ignore();
      }
      _streams.clear();

      for (final httpCacheServer in _cacheServers.toList()) {
        httpCacheServer.dispose().ignore();
      }
      _cacheServers.clear();

      if (config.customHttpClient == null) {
        config.httpClient.close(); // Close the default http client only
      }
    }
  }

  Directory get cacheDir => config.cacheDirectory;
  Iterable<HttpCacheStream> get allStreams => _streams.values;
  bool _disposed = false;
  bool get isDisposed => _disposed;

  /// Initializes [HttpCacheManager]. If already initialized, returns the existing instance.
  ///
  ///To specify a custom cache directory or HTTP client, provide [cacheDir] and [customHttpClient].
  /// [cacheDir] is the directory where the cache files will be stored. If null,
  /// the default cache directory will be used (see [GlobalCacheConfig.defaultCacheDirectory]).
  /// [customHttpClient] is the custom http client to use. If null, a default http client will be used.
  /// [GlobalCacheConfig] is used to configure the manager. If provided, [cacheDir] and [customHttpClient] must be null.
  /// You can also provide [CacheServerConfig] for the cache server address and port configuration.
  ///
  static Future<HttpCacheManager> init({
    @Deprecated('Use config parameter to set cacheDirectory') final Directory? cacheDir,
    @Deprecated('Use config parameter to set customHttpClient') final http.Client? customHttpClient,
    final GlobalCacheConfig? config,
    final CacheServerConfig? serverConfig,
  }) {
    assert(config == null || (cacheDir == null && customHttpClient == null),
        'Cannot set cacheDir or httpClient when config is provided. Set them in the config instead.');
    if (_instance != null) {
      return Future.value(instance);
    }
    return _initFuture ??= () async {
      try {
        final cacheConfig = config ??
            GlobalCacheConfig(
              cacheDirectory: cacheDir ?? await GlobalCacheConfig.defaultCacheDirectory(),
              customHttpClient: customHttpClient,
            );
        final httpCacheServer = await LocalCacheServer.init(serverConfig);
        return _instance = HttpCacheManager._(httpCacheServer, cacheConfig);
      } finally {
        _initFuture = null;
      }
    }();
  }

  /// The singleton instance of [HttpCacheManager].
  ///
  /// Throws a [StateError] if [init] hasn't been called.
  static HttpCacheManager get instance {
    if (_instance == null) {
      throw StateError(
        'HttpCacheManager not initialized. Call HttpCacheManager.init() first.',
      );
    }
    return _instance!;
  }

  static Future<HttpCacheManager>? _initFuture;
  static HttpCacheManager? _instance;

  /// Whether the [HttpCacheManager] has been initialized.
  static bool get isInitialized => _instance != null;

  /// The singleton instance of [HttpCacheManager], or null if not initialized.
  static HttpCacheManager? get instanceOrNull => _instance;
}
