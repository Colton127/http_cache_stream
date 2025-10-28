import 'dart:async';
import 'dart:io';

import 'package:http_cache_stream/src/cache_server/local_cache_server.dart';
import 'package:http_cache_stream/src/etc/extensions.dart';
import 'package:http_cache_stream/src/models/cache_files/cache_files.dart';

import '../../http_cache_stream.dart';
import '../lazy_cache_stream/lazy_cache_stream_manager.dart';
import '../models/cache_files/cache_file_type.dart';

class HttpCacheManager {
  final LocalCacheServer _server;
  final GlobalCacheConfig config;
  final Map<String, HttpCacheStream> _streams = {};
  final LazyCacheStreamManager _lazyStreamManager;
  final List<HttpCacheServer> _cacheServers = [];
  HttpCacheManager._(this._server, this.config)
      : _lazyStreamManager = LazyCacheStreamManager(_server.serverUri) {
    _server.start((request) {
      final lazyStream = _lazyStreamManager.getLazyStream(request);
      if (lazyStream != null) {
        final cacheStream = createStream(
          lazyStream.sourceUrl,
          file: lazyStream.file,
          config: lazyStream.config,
        );
        request.response.done.onComplete(() {
          Timer(
              cacheStream.config.autoDisposeDelay,
              () => cacheStream
                  .dispose()
                  .ignore()); // Decrease the stream's retainCount for autoDispose
        });
        return cacheStream;
      }

      return getExistingStream(request.uri);
    });
  }

  ///Create a [HttpCacheStream] instance for the given URL. If an instance already exists, the existing instance will be returned.
  ///Use [file] to specify the output file to save the downloaded content to. If not provided, a file will be created in the cache directory (recommended).
  HttpCacheStream createStream(
    final Uri sourceUrl, {
    final File? file,
    final StreamCacheConfig? config,
  }) {
    assert(!isDisposed,
        'HttpCacheManager is disposed. Cannot create new streams.');
    final existingStream = getExistingStream(sourceUrl);
    if (existingStream != null) {
      existingStream
          .retain(); //Retain the stream to prevent it from being disposed
      return existingStream;
    }
    final cacheStream = HttpCacheStream(
      sourceUrl: sourceUrl,
      cacheUrl: _server.getCacheUrl(sourceUrl),
      files: file != null
          ? CacheFiles.fromFile(file)
          : _defaultCacheFiles(sourceUrl),
      config: config ?? createStreamConfig(),
    );
    final key = sourceUrl.requestKey;
    cacheStream.future.onComplete(
      () => _streams.remove(key),
    ); //Remove when stream is disposed
    _streams[key] = cacheStream; //Add to the stream map
    return cacheStream;
  }

  /// Returns a [LazyCacheStream] that automatically manages [HttpCacheStream] lifecycle.
  ///
  /// A [HttpCacheStream] is created on-demand when the first request is made to the cache URL.
  /// After all active requests complete, the stream is automatically disposed after [StreamCacheConfig.autoDisposeDelay].
  /// Subsequent requests will create a new stream instance.
  ///
  /// Use this when you need a cacheable URL that doesn't keep resources alive when idle.
  ///
  /// - [sourceUrl]: The remote URL to cache
  /// - [file]: Optional custom file path for the cache
  /// - [config]: Optional stream configuration, including autoDispose settings
  LazyCacheStream createLazyStream(
    final Uri sourceUrl, {
    final File? file,
    final StreamCacheConfig? config,
  }) {
    return _lazyStreamManager.createLazyStream(
      sourceUrl: sourceUrl,
      file: file,
      config: config,
    );
  }

  ///Creates a [HttpCacheServer] instance for an origin Uri. This server will redirect requests to the given origin and create [HttpCacheStream] instances for each request.
  ///Generally, only one server per origin is needed.
  ///After all active requests on a created [HttpCacheStream] complete, the stream is automatically disposed after [StreamCacheConfig.autoDisposeDelay].
  ///Optionally, you can provide a [StreamCacheConfig] to be used for the streams created by this server, and a [port] for the local server.
  Future<HttpCacheServer> createServer(
    final Uri origin, {
    final StreamCacheConfig? config,
    final int? port,
  }) async {
    final cacheServer = HttpCacheServer(
      origin.originUri,
      await LocalCacheServer.init(port),
      config ?? createStreamConfig(),
      createStream,
    );
    _cacheServers.add(cacheServer);
    cacheServer.future.onComplete(() => _cacheServers.remove(cacheServer));
    return cacheServer;
  }

  /// Pre-caches the URL and returns the cache file. If the cache file already exists, it will be returned immediately.
  /// If the download completes before the stream is used, the stream will automatically be disposed.
  FutureOr<File> preCacheUrl(final Uri sourceUrl, {final File? file}) {
    final completeCacheFile = file ?? _defaultCacheFiles(sourceUrl).complete;
    if (completeCacheFile.existsSync()) {
      return completeCacheFile;
    }
    final cacheStream = createStream(sourceUrl, file: file);
    return cacheStream.download().whenComplete(() => cacheStream.dispose());
  }

  ///Deletes cache. Does not modify files used by active [HttpCacheStream] instances.
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
    await for (final entry
        in cacheDir.list(recursive: true, followLinks: false)) {
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

  ///Get the [CacheMetadata] for the given URL. Returns null if the metadata does not exist.
  CacheMetadata? getCacheMetadata(final Uri sourceUrl) {
    return getExistingStream(sourceUrl)?.metadata ??
        CacheMetadata.fromCacheFiles(_defaultCacheFiles(sourceUrl));
  }

  ///Gets [CacheFiles] for the given URL. Does not check if any cache files exists.
  CacheFiles getCacheFiles(final Uri sourceUrl) {
    return getExistingStream(sourceUrl)?.metadata.cacheFiles ??
        _defaultCacheFiles(sourceUrl);
  }

  /// Returns the existing [HttpCacheStream] for the given URL, or null if it doesn't exist.
  /// The input [url] can either be [sourceUrl] or [cacheUrl].
  HttpCacheStream? getExistingStream(final Uri url) {
    final String key = url.requestKey;
    final HttpCacheStream? stream = _streams[key];

    if (stream != null && stream.isDisposed) {
      _streams.remove(key);
      return null;
    }

    return stream;
  }

  ///Returns the existing [HttpCacheServer] for the given source URL, or null if it doesn't exist.
  HttpCacheServer? getExistingServer(final Uri source) {
    for (final cacheServer in _cacheServers) {
      final cacheServerOrigin = cacheServer.origin;
      if (cacheServerOrigin.host == source.host &&
          cacheServerOrigin.port == source.port &&
          cacheServerOrigin.scheme == source.scheme &&
          !cacheServer.isDisposed) {
        return cacheServer;
      }
    }
    return null;
  }

  CacheFiles _defaultCacheFiles(final Uri sourceUrl) {
    final resolvedCacheFile = config.cacheFileResolver?.call(sourceUrl);
    if (resolvedCacheFile != null) {
      return CacheFiles.fromFile(resolvedCacheFile);
    } else {
      return CacheFiles.fromUrl(config.cacheDirectory, sourceUrl);
    }
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
      for (final server in _cacheServers.toList()) {
        server.dispose().ignore();
      }
      for (final stream in _streams.values.toList()) {
        stream.dispose(force: true).ignore();
      }
      _streams.clear();
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

  ///Initializes [HttpCacheManager]. If already initialized, returns the existing instance. If initialization is already in progress, returns the pending instance future.
  ///Use [GlobalCacheConfig] to specify the cache directory, http client, and initial cache configuration.
  ///Use [port] to specify the port for the local cache server, if null, a random available port will be used.
  static FutureOr<HttpCacheManager> init({
    final GlobalCacheConfig? config,
    final int? port,
  }) {
    if (_instance != null) {
      return instance;
    }
    return _initFuture ??= (() async {
      try {
        return _instance = HttpCacheManager._(
          await LocalCacheServer.init(port),
          config ?? await GlobalCacheConfig.init(),
        );
      } finally {
        _initFuture = null;
      }
    })();
  }

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
  static bool get isInitialized => _instance != null;
  static HttpCacheManager? get instanceOrNull => _instance;
}
