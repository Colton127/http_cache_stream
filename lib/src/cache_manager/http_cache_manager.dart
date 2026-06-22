import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_cache_stream/src/cache_server/local_cache_server.dart';
import 'package:http_cache_stream/src/etc/extensions/uri_extensions.dart';

import '../../http_cache_stream.dart';
import '../etc/extensions/future_extensions.dart';
import '../etc/helpers.dart';

/// Manages the local HTTP server and `HttpCacheStream` instances.
///
/// Use [init] to initialize the manager before creating streams.
class HttpCacheManager {
  final LocalCacheServer _server;

  /// The global configuration used for all streams managed by this manager.
  final GlobalCacheConfig config;

  final Map<RequestKey, HttpCacheStream> _streams = {};
  final Map<RequestKey, File> _customCacheFiles = {};
  HttpCacheManager._(this._server, this.config) {
    _server.start(createStream);
  }

  /// Gets the cache URL for the given source URL.
  /// If a custom cache file is provided, it will be saved and used for the cache stream.
  Uri getCacheUrl(final Uri sourceUrl, {final File? file}) {
    _checkDisposed();
    if (file != null) {
      _customCacheFiles[sourceUrl.requestKey] = file;
    }
    return _server.encodeSourceUrl(sourceUrl);
  }

  /// Create a [HttpCacheStream] instance for the given URL. If an instance already exists, the existing instance will be returned.
  /// Use [file] to specify the output file to save the downloaded content to. If not provided, a file will be created in the cache directory.
  /// Prefer [getCacheUrl] unless if you need access to the `HttpCacheStream` instance.
  HttpCacheStream createStream(
    final Uri sourceUrl, {
    final File? file,
    final StreamCacheConfig? config,
  }) {
    _checkDisposed();
    final requestKey = sourceUrl.requestKey;

    final existingStream = _streams[requestKey];
    if (existingStream != null && !existingStream.isDisposed) {
      existingStream
          .retain(); //Retain the stream to prevent it from being disposed while in use
      return existingStream;
    }

    CacheFiles cacheFiles;
    if (file != null) {
      _customCacheFiles[requestKey] = file;
      cacheFiles = CacheFiles.fromFile(file);
    } else {
      cacheFiles = _resolveCacheFiles(sourceUrl);
    }

    final cacheStream = HttpCacheStream(
      sourceUrl: sourceUrl,
      cacheUrl: _server.encodeSourceUrl(sourceUrl),
      files: cacheFiles,
      config: config ?? createStreamConfig(),
    );

    ///Add to the stream map
    _streams[requestKey] = cacheStream;

    ///Remove when stream is disposed
    cacheStream.future.onComplete(() {
      _streams.remove(requestKey);
    });

    if (_onStreamCreated case final streamCreatedCallback?) {
      fireUserCallback(() => streamCreatedCallback(cacheStream));
    }

    return cacheStream;
  }

  /// Downloads the content of the given URL and saves it to a cache file. Returns the downloaded file.
  Future<File> preCacheUrl(final Uri sourceUrl, {final File? cacheFile}) async {
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

  ///Get the [CacheMetadata] for the given URL or input [cacheFile]. Returns null if the metadata does not exist.
  CacheMetadata? getCacheMetadata(Uri url, [File? cacheFile]) {
    return getExistingStream(url)?.metadata ??
        CacheMetadata.fromCacheFiles(_resolveCacheFiles(url, cacheFile));
  }

  ///Gets [CacheFiles] for the given URL or input [cacheFile]. Does not check if any cache files exists.
  CacheFiles getCacheFiles(Uri url, [File? cacheFile]) {
    return getExistingStream(url)?.files ?? _resolveCacheFiles(url, cacheFile);
  }

  /// Returns the existing [HttpCacheStream] for the given URL, or null if it doesn't exist.
  /// The input [url] can either be [sourceUrl] or [cacheUrl].
  HttpCacheStream? getExistingStream(Uri url) {
    _checkDisposed();
    url = _server.decodeSourceUrl(url) ?? url;
    return _streams[url.requestKey];
  }

  CacheFiles _resolveCacheFiles(Uri sourceUrl, [File? cacheFile]) {
    if (cacheFile == null) {
      sourceUrl = _server.decodeSourceUrl(sourceUrl) ?? sourceUrl;
      cacheFile = _customCacheFiles[sourceUrl.requestKey] ??
          config.cacheFileResolver(config.cacheDirectory, sourceUrl);
    }
    return CacheFiles.fromFile(cacheFile);
  }

  ///Create a [StreamCacheConfig] that inherits the current [GlobalCacheConfig]. This config is used to create [HttpCacheStream] instances.
  StreamCacheConfig createStreamConfig() => StreamCacheConfig.construct(this);

  ///Disposes the current [HttpCacheManager] and all resources.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    HttpCacheManager._instance = null;
    _onStreamCreated = null;

    try {
      await _server.close(force: true);
    } finally {
      _customCacheFiles.clear();
      for (final stream in _streams.values.toList()) {
        stream.dispose().ignore();
      }
      _streams.clear();
      if (config.customHttpClient == null) {
        config.httpClient.close(); // Close the default http client only
      }
    }
  }

  /// Set a callback to be fired when a new [HttpCacheStream] is created.
  set onStreamCreated(HttpCacheStreamCreatedCallback? callback) {
    _checkDisposed();
    _onStreamCreated = callback;
  }

  void _checkDisposed() {
    if (isDisposed) {
      throw CacheManagerDisposedException();
    }
  }

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
              cacheDirectory:
                  cacheDir ?? await GlobalCacheConfig.defaultCacheDirectory(),
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
