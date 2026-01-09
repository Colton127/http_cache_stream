import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_cache_stream/src/cache_server/local_cache_server.dart';
import 'package:http_cache_stream/src/etc/extensions/uri_extensions.dart';
import 'package:http_cache_stream/src/models/cache_files/cache_files.dart';

import '../../http_cache_stream.dart';
import '../etc/extensions/future_extensions.dart';
import '../models/cache_files/cache_file_types.dart';

class HttpCacheManager {
  final LocalCacheServer _server;
  final GlobalCacheConfig config;
  final Map<String, HttpCacheStream> _streams = {};
  final List<HttpCacheServer> _cacheServers = [];
  HttpCacheManager._(this._server, this.config) {
    _server.start((request) {
      return getExistingStream(request.uri);
    });
  }

  ///Create a [HttpCacheStream] instance for the given URL. If an instance already exists, the existing instance will be returned.
  ///Use [file] to specify the output file to save the downloaded content to. If not provided, a file will be created in the cache directory (recommended).
  ///Use [retain] to specify whether to increase the retain count of the stream if it already exists. Default is true.
  HttpCacheStream createStream(
    final Uri sourceUrl, {
    final File? file,
    final StreamCacheConfig? config,
    final bool retain = true,
  }) {
    final existingStream = getExistingStream(sourceUrl);
    if (existingStream != null && !existingStream.isDisposed) {
      if (retain || !existingStream.isRetained) {
        existingStream.retain(); //Retain the stream to prevent it from being disposed
      }
      return existingStream;
    }
    final cacheStream = HttpCacheStream(
      sourceUrl: sourceUrl,
      cacheUrl: _server.getCacheUrl(sourceUrl),
      files: file != null ? CacheFiles.fromFile(file) : _defaultCacheFiles(sourceUrl),
      config: config ?? createStreamConfig(),
    );
    final key = sourceUrl.requestKey;
    cacheStream.future.onComplete(
      () => _streams.remove(key),
    ); //Remove when stream is disposed
    _streams[key] = cacheStream; //Add to the stream map
    return cacheStream;
  }

  ///Creates a [HttpCacheServer] instance for a source Uri. This server will redirect requests to the given source and create [HttpCacheStream] instances for each request.
  ///[autoDisposeDelay] is the delay before a stream is disposed after all requests are done.
  ///Optionally, you can provide a [StreamCacheConfig] to be used for the streams created by this server.
  Future<HttpCacheServer> createServer(
    final Uri source, {
    final Duration autoDisposeDelay = const Duration(seconds: 15),
    final StreamCacheConfig? config,
  }) async {
    final cacheServer = HttpCacheServer(
      Uri(
        scheme: source.scheme,
        host: source.host,
        port: source.port,
      ),
      await LocalCacheServer.init(),
      autoDisposeDelay,
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
    await for (final entry in cacheDir.list(recursive: true, followLinks: false)) {
      if (entry is File && !activeFilePaths.contains(entry.path)) {
        yield entry;
      }
    }
  }

  ///Get a list of [CacheMetadata].
  ///
  ///Specify [active] to filter between metadata for active and inactive [HttpCacheStream] instances. If null, all [CacheMetadata] will be returned.
  ///
  ///Prefer using [cacheMetadataStream] for large number of cache files to avoid loading all metadata into memory at once.
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

  ///Gets a stream of [CacheMetadata].
  ///
  ///Specify [active] to filter between metadata for active and inactive [HttpCacheStream] instances. If null, all [CacheMetadata] will be returned.
  Stream<CacheMetadata> cacheMetadataStream({final bool? active}) async* {
    if (active != false) {
      yield* Stream.fromIterable(allStreams.map((stream) => stream.metadata));
    }
    if (active != true) {
      await for (final file in inactiveCacheFiles().where(CacheFileType.isMetadata)) {
        final savedMetadata = CacheMetadata.load(file);
        if (savedMetadata != null) {
          yield savedMetadata;
        }
      }
    }
  }

  ///Get the [CacheMetadata] for the given URL. Returns null if the metadata does not exist.
  CacheMetadata? getCacheMetadata(final Uri sourceUrl) {
    return getExistingStream(sourceUrl)?.metadata ?? CacheMetadata.fromCacheFiles(_defaultCacheFiles(sourceUrl));
  }

  ///Gets [CacheFiles] for the given URL. Does not check if any cache files exists.
  CacheFiles getCacheFiles(final Uri sourceUrl) {
    return getExistingStream(sourceUrl)?.metadata.cacheFiles ?? _defaultCacheFiles(sourceUrl);
  }

  /// Returns the existing [HttpCacheStream] for the given URL, or null if it doesn't exist.
  /// The input [url] can either be [sourceUrl] or [cacheUrl].
  HttpCacheStream? getExistingStream(final Uri url) {
    return _streams[url.requestKey];
  }

  ///Returns the existing [HttpCacheServer] for the given source URL, or null if it doesn't exist.
  HttpCacheServer? getExistingServer(final Uri source) {
    for (final cacheServer in _cacheServers) {
      final serverSource = cacheServer.source;
      if (serverSource.host == source.host && serverSource.port == source.port && serverSource.scheme == source.scheme) {
        return cacheServer;
      }
    }
    return null;
  }

  CacheFiles _defaultCacheFiles(Uri sourceUrl) {
    return CacheFiles.fromUrl(config.cacheDirectory, sourceUrl);
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

  /// Summary statistics about the current HTTP connections to all local cache servers.
  HttpConnectionsInfo connectionsInfo() {
    final result = _server.connectionsInfo();

    for (final cacheServer in _cacheServers) {
      final serverInfo = cacheServer.connectionsInfo();
      result.total += serverInfo.total;
      result.active += serverInfo.active;
      result.idle += serverInfo.idle;
      result.closing += serverInfo.closing;
    }

    return result;
  }

  Directory get cacheDir => config.cacheDirectory;
  Iterable<HttpCacheStream> get allStreams => _streams.values;
  bool _disposed = false;
  bool get isDisposed => _disposed;

  ///Initializes [HttpCacheManager]. If already initialized, returns the existing instance.
  ///[cacheDir] is the directory where the cache files will be stored. If null, the default cache directory will be used (see [GlobalCacheConfig.defaultCacheDirectory]).
  ///[customHttpClient] is the custom http client to use. If null, a default http client will be used.
  ///You can also provide [GlobalCacheConfig] for the initial configuration.
  static Future<HttpCacheManager> init({
    final Directory? cacheDir,
    final http.Client? customHttpClient,
    final GlobalCacheConfig? config,
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
        final httpCacheServer = await LocalCacheServer.init();
        return _instance = HttpCacheManager._(httpCacheServer, cacheConfig);
      } finally {
        _initFuture = null;
      }
    }();
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
