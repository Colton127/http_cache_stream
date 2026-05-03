import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_cache_stream/src/cache_server/local_cache_server.dart';
import 'package:http_cache_stream/src/etc/extensions/uri_extensions.dart';
import 'package:synchronized/synchronized.dart';

import '../../http_cache_stream.dart';
import '../etc/callback_helpers.dart';
import '../etc/extensions/future_extensions.dart';

/// Manages the local HTTP server and `HttpCacheStream` instances.
///
/// Use [init] to initialize the manager before creating streams.
class HttpCacheManager {
  final LocalCacheServer _server;

  /// The global configuration used for all streams managed by this manager.
  final GlobalCacheConfig config;

  final Map<RequestKey, HttpCacheStream> _streams = {};
  final List<HttpCacheServer> _cacheServers = [];
  HttpCacheManager._(this._server, this.config) {
    _server.start((request) {
      final Uri? sourceUrl = _server.decodeSourceUrl(request.uri);
      if (sourceUrl != null) {
        print('Creating cache stream for decoded source URL: $sourceUrl');
        return request.stream(createStream(sourceUrl));
      }

      final cacheStream = getExistingStream(request.uri);
      if (cacheStream != null) {
        return request.stream(cacheStream);
      } else {
        request.close(HttpStatus.serviceUnavailable);
        return Future.value();
      }
    });
  }

  Uri getCacheUrl(final Uri sourceUrl) {
    _checkDisposed();
    return _server.encodeSourceUrl(sourceUrl);
  }

  /// Create a [HttpCacheStream] instance for the given URL. If an instance already exists, the existing instance will be returned.
  /// Use [file] to specify the output file to save the downloaded content to. If not provided, a file will be created in the cache directory (recommended).
  HttpCacheStream createStream(
    final Uri sourceUrl, {
    final File? file,
    final StreamCacheConfig? config,
  }) {
    _checkDisposed();
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

    ///Remove when stream is disposed
    cacheStream.future.onComplete(() {
      _streams.remove(key);
      print('Cache stream for URL $sourceUrl disposed and removed from manager');
    });

    ///Add to the stream map
    _streams[key] = cacheStream;

    if (_onStreamCreated case final streamCreatedCallback?) {
      fireUserCallback(() => streamCreatedCallback(cacheStream));
    }

    print('Created new cache stream for URL: $sourceUrl');
    return cacheStream;
  }

  /// Creates an [HttpCacheServer] for the given [origin], or returns an existing
  /// one if [returnExisting] is true (the default).
  ///
  /// [origin] is matched by scheme, host, and port only — the path is ignored.
  /// For example, `https://cdn.example.com/1.mp3` and
  /// `https://cdn.example.com/2.mp3` both resolve to the same server.
  ///
  /// Use [StreamLifecycleConfig] on [config] to control the lifecycle of
  /// [HttpCacheStream] instances created by the server.
  /// Use [port] to bind to a specific port (random if omitted).
  Future<HttpCacheServer> createServer(
    final Uri origin, {
    final StreamCacheConfig? config,
    final bool returnExisting = true,
    final int? port,
  }) {
    return _createServerLock.synchronized(() async {
      _checkDisposed();

      if (returnExisting) {
        final existing = getExistingServer(origin, port: port);
        if (existing != null) return existing;
      }

      final cacheServer = HttpCacheServer(
        origin.originUri,
        await LocalCacheServer.init(port: port),
        config ?? createStreamConfig(),
        createStream,
      );

      if (_disposed) {
        cacheServer.close(force: true).ignore();
        throw CacheManagerDisposedException();
      }

      _cacheServers.add(cacheServer);
      cacheServer.future.onComplete(() => _cacheServers.remove(cacheServer));
      return cacheServer;
    });
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
        if (await completedCacheFile.exists()) {
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
  HttpCacheServer? getExistingServer(final Uri origin, {int? port}) {
    for (final cacheServer in _cacheServers) {
      if (cacheServer.origin.originEquals(origin) && !cacheServer.isClosed) {
        if (port == null || port == 0 || cacheServer.port == port) {
          return cacheServer;
        }
      }
    }
    return null;
  }

  CacheFiles _resolveCacheFiles(Uri sourceUrl, [File? file]) {
    file ??= config.cacheFileResolver(config.cacheDirectory, sourceUrl);
    return CacheFiles.fromFile(file);
  }

  ///Create a [StreamCacheConfig] that inherits the current [GlobalCacheConfig]. This config is used to create [HttpCacheStream] instances.
  StreamCacheConfig createStreamConfig() => StreamCacheConfig.construct(this);

  ///Disposes the current [HttpCacheManager] and all resources.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    HttpCacheManager._instance = null;

    try {
      await Future.wait([
        _server.close(force: true),
        ..._cacheServers.map((server) => server.close(force: true)),
        ..._streams.values.map((stream) => stream.dispose(force: true)),
      ]);
    } finally {
      _streams.clear();
      _cacheServers.clear();
      if (config.customHttpClient == null) {
        config.httpClient.close(); // Close the default http client only
      }
    }
  }

  /// Set a callback to be fired when a new [HttpCacheStream] is created.
  set onStreamCreated(HttpCacheStreamCreatedCallback? callback) {
    _onStreamCreated = callback;
  }

  void _checkDisposed() {
    if (isDisposed) {
      throw CacheManagerDisposedException();
    }
  }

  late final _createServerLock = Lock();
  HttpCacheStreamCreatedCallback? _onStreamCreated;
  Directory get cacheDir => config.cacheDirectory;
  Iterable<HttpCacheStream> get allStreams => _streams.values;
  bool _disposed = false;
  bool get isDisposed => _disposed;

  /// Initializes [HttpCacheManager]. If already initialized, returns the existing instance.
  ///
  /// [cacheDir] is the directory where the cache files will be stored. If null,
  /// the default cache directory will be used (see [GlobalCacheConfig.defaultCacheDirectory]).
  /// [customHttpClient] is the custom http client to use. If null, a default http client will be used.
  /// You can also provide [GlobalCacheConfig] for the initial configuration.
  /// Use `port` to specify the port for the local server. If not provided, a random available port will be used.
  static Future<HttpCacheManager> init({
    final Directory? cacheDir,
    final http.Client? customHttpClient,
    final GlobalCacheConfig? config,
    final int? port,
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
        final httpCacheServer = await LocalCacheServer.init(port: port);
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

typedef HttpCacheStreamCreatedCallback = void Function(HttpCacheStream stream);
