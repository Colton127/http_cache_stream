import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http_cache_stream/src/cache_stream/cache_downloader/cache_downloader.dart';
import 'package:http_cache_stream/src/cache_stream/cache_downloader/downloader.dart';
import 'package:http_cache_stream/src/etc/extensions/future_extensions.dart';
import 'package:http_cache_stream/src/models/cache_config/stream_cache_config.dart';
import 'package:http_cache_stream/src/models/cache_files/cache_files.dart';
import 'package:http_cache_stream/src/models/metadata/cached_response_headers.dart';
import 'package:http_cache_stream/src/models/stream_requests/int_range.dart';

import '../etc/extensions/list_extensions.dart';
import '../models/exceptions.dart';
import '../models/metadata/cache_metadata.dart';
import '../models/stream_requests/stream_request.dart';
import '../models/stream_response/stream_response.dart';

class HttpCacheStream {
  ///The source Url of the file to be downloaded (e.g., https://example.com/file.mp3)
  final Uri sourceUrl;

  ///The Url of the cached stream (e.g., http://127.0.0.1:8080/file.mp3)
  final Uri cacheUrl;

  /// The complete, partial, and metadata files used for the cache.
  final CacheFiles files;

  /// The cache config used for this stream. By default, values from [GlobalCacheConfig] are used.
  final StreamCacheConfig config;

  final List<StreamRequest> _queuedRequests = [];

  final _progressController = StreamController<double?>.broadcast();
  CacheDownloader? _cacheDownloader; //The active cache downloader, if any. This can be used to cancel the download.
  int _retainCount = 1; //The number of times the stream has been retained
  Future<File>? _downloadFuture; //The future for the current download, if any.
  Future<bool?>? _validateCacheFuture;
  bool _setProgress = false; //Whether the cache progress has been updated at least once. Used to ensure progress is set upon first access.
  double? _lastProgress; //The last progress value emitted by the stream
  Object? _lastError; //The last error emitted by the stream
  final _disposeCompleter = Completer<void>(); //Completer for the dispose future
  CacheMetadata _cacheMetadata; //The metadata for the cache

  HttpCacheStream({
    required this.sourceUrl,
    required this.cacheUrl,
    required this.files,
    required this.config,
  }) : _cacheMetadata = CacheMetadata.construct(files, sourceUrl) {
    _progressController.onListen = () {
      if (!_setProgress) _calculateCacheProgress();
      _progressController.onListen = null;
    };
    if (config.validateOutdatedCache) {
      validateCache(force: false, resetInvalid: true).ignore();
    }
  }

  ///Requests a [StreamResponse] for the specified byte range. If the requested range is not cached, starts a download if not already in progress
  Future<StreamResponse> request({final int? start, final int? end}) async {
    if (_validateCacheFuture != null) {
      await _validateCacheFuture!;
    }
    _checkDisposed();
    final range = IntRange.validate(start, end, metadata.sourceLength);

    if (!isDownloading) {
      if (metadata.headers != null && await cacheFile.exists()) {
        _updateProgressStream(1.0);
        return StreamResponse.fromFile(range, cacheFile, metadata.headers!);
      }

      download().ignore(); //Start download
    }

    final streamRequest = StreamRequest.construct(range);
    final downloader = _cacheDownloader;
    if (downloader == null || !downloader.processRequest(streamRequest)) {
      _queuedRequests.add(streamRequest); //Add request to queue

      final timeoutTimer = Timer(config.cacheRequestTimeout, () {
        streamRequest.completeError(CacheRequestTimeoutException(sourceUrl, config.cacheRequestTimeout));
        _queuedRequests.remove(streamRequest);
      });
      streamRequest.response.onComplete(timeoutTimer.cancel);
    }

    return streamRequest.response;
  }

  Future<StreamResponse> headRequest({final int? start, final int? end, final bool fetchLatest = false}) async {
    if (_validateCacheFuture != null) {
      await _validateCacheFuture!;
    }
    _checkDisposed();
    final headers = await cachedResponseHeaders(fetchLatest: fetchLatest);
    final range = IntRange.validate(start, end, headers.sourceLength);
    return StreamResponse.empty(range, headers);
  }

  ///Validates the cache. Returns true if the cache is valid, false if it is not, and null if cache does not exist or is downloading.
  ///Cache is only revalidated if [CachedResponseHeaders.shouldRevalidate()] or [force] is true.
  ///Partial cache is automatically revalidated when the download is resumed, and cannot be validated manually.
  Future<bool?> validateCache({
    final bool force = false,
    final bool resetInvalid = false,
  }) async {
    if (_validateCacheFuture != null) {
      return _validateCacheFuture;
    }
    if (isDownloading || !isCached) {
      return null; //Cache does not exist or is downloading
    }
    final currentHeaders = metadata.headers ?? CachedResponseHeaders.fromFile(cacheFile);
    if (currentHeaders == null) return null;
    if (!force && currentHeaders.shouldRevalidate() == false) return true;
    return _validateCacheFuture = () async {
      try {
        final latestHeaders = await cachedResponseHeaders(fetchLatest: true);
        if (CachedResponseHeaders.validateCacheResponse(currentHeaders, latestHeaders)) {
          _setCachedResponseHeaders(latestHeaders);
          return true;
        } else {
          if (resetInvalid) {
            await resetCache(CacheSourceChangedException(sourceUrl));
          }
          return false;
        }
      } catch (e) {
        _addError(e, closeRequests: false);
        return null;
      } finally {
        _validateCacheFuture = null;
        _calculateCacheProgress();
      }
    }();
  }

  ///Downloads and returns [cacheFile]. If the file already exists, returns immediately. If a download is already in progress, returns the same future.
  ///This method will return [DownloadStoppedException] if the cache stream is disposed before the download is complete. Other errors will be emitted to the [progressStream].
  Future<File> download() async {
    if (_downloadFuture != null) {
      return _downloadFuture!;
    }
    _checkDisposed();
    final downloadCompleter = Completer<File>();
    _downloadFuture = downloadCompleter.future;

    bool isComplete() {
      if (downloadCompleter.isCompleted) return true;
      final completed = _calculateCacheProgress() == 1.0;
      if (completed) {
        downloadCompleter.complete(cacheFile);
      }
      return completed;
    }

    while (isRetained && !isComplete()) {
      try {
        final downloader = _cacheDownloader = CacheDownloader.construct(metadata, config);
        await downloader.download(
          onPosition: (position) {
            final int? sourceLength = downloader.sourceLength;

            if (sourceLength == null || sourceLength <= 0) {
              _updateProgressStream(null);
            } else {
              final progress = ((position / sourceLength * 100).round() / 100);
              if (progress >= 0.99) {
                _updateProgressStream(0.99); //Avoid setting progress to 1.0 before completion
                return; //If near completion, avoid processing requests using partial data.
              }
              _updateProgressStream(progress);
            }

            if (_queuedRequests.isEmpty) return;
            final rangeThreshold = config.rangeRequestSplitThreshold;
            _queuedRequests.removeWhere((request) {
              if (request.isComplete) {
                return true;
              } else if (sourceLength != null && request.range.rangeMax > sourceLength) {
                request.completeError(RangeError.range(request.range.rangeMax, 0, sourceLength));
                return true;
              } else if (downloader.processRequest(request)) {
                return true;
              } else if (rangeThreshold != null && (request.start - position) > rangeThreshold && metadata.headers?.acceptsRangeRequests == true) {
                request.complete(() => StreamResponse.fromDownload(sourceUrl, request.range, config));
                return true;
              } else {
                return false;
              }
            });
          },
          onComplete: () async {
            await files.partial.rename(files.complete.path);
            final cachedHeaders = metadata.headers!;
            if (cachedHeaders.sourceLength != downloader.dataStreamPosition || !cachedHeaders.acceptsRangeRequests) {
              _setCachedResponseHeaders(cachedHeaders.setSourceLength(downloader.dataStreamPosition));
            }
            config.onCacheComplete(this, files.complete);
          },
          onHeaders: (cacheHttpHeaders) {
            _setCachedResponseHeaders(cacheHttpHeaders);
          },
          onError: (error) {
            assert(error is! InvalidCacheException, 'InvalidCacheException must be rethrown to reset the cache');
            _addError(error, closeRequests: true);
          },
        );
      } catch (e) {
        assert(_cacheDownloader?.isActive == false, 'Downloader should not be active on error');
        _cacheDownloader = null;
        if (e is InvalidCacheException) {
          await resetCache(e);
        } else if (isRetained) {
          _addError(e, closeRequests: true);
          await Future.delayed(config.retryDelay);
        }
      }
    }
    _cacheDownloader = null;
    _downloadFuture = null;
    if (!isComplete()) {
      final error = isRetained ? DownloadStoppedException(sourceUrl) : CacheStreamDisposedException(sourceUrl);
      downloadCompleter.future.ignore(); // Prevent unhandled error during completion
      downloadCompleter.completeError(error);
      _addError(error, closeRequests: true);
    }
    return downloadCompleter.future;
  }

  ///Disposes this [HttpCacheStream]. This method should be called when you are done with the stream.
  ///If [force] is true, the stream will be disposed immediately, regardless of the [retain] count. [retain] is incremented when the stream is obtained using [HttpCacheManager.createStream].
  ///Returns a future that completes when the stream is disposed.
  Future<void> dispose({final bool force = false}) {
    if (_retainCount > 0 && !isDisposed) {
      _retainCount = force ? 0 : _retainCount - 1;
      if (!isRetained) {
        () async {
          late final error = CacheStreamDisposedException(sourceUrl);
          try {
            final downloader = _cacheDownloader;
            if (downloader != null) {
              await downloader.cancel(error); //Allow downloader to complete cleanly. Note that the stream can be retained again during this await.
            }
          } catch (e) {
            _addError(e, closeRequests: !isRetained);
          } finally {
            if (!_disposeCompleter.isCompleted && !isRetained) {
              _disposeCompleter.complete();
              if (_queuedRequests.isNotEmpty) {
                _addError(error, closeRequests: true);
              }
              _progressController.close().ignore();
              if (!config.savePartialCache && progress != 1.0) {
                files.delete(partialOnly: true).ignore();
              } else if (!config.saveMetadata && progress == 1.0 && files.metadata.existsSync()) {
                files.metadata.delete().ignore();
              }
            }
          }
        }();
      }
    }

    return _disposeCompleter.future;
  }

  ///Resets the cache files used by this [HttpCacheStream], interrupting any ongoing download.
  Future<void> resetCache([InvalidCacheException? exception]) async {
    final error = exception ?? CacheDeletedException(sourceUrl);
    final downloader = _cacheDownloader;
    if (downloader != null && downloader.isActive) {
      return downloader.cancel(error); //Close the ongoing download, which will rethrow the exception and reset the cache
    } else {
      _cacheMetadata = _cacheMetadata.setHeaders(null);
      _updateProgressStream(null);
      _addError(error, closeRequests: false);
      await files.delete().catchError((_) => false);
      if (_queuedRequests.isNotEmpty && !isDownloading && isRetained) {
        download().ignore(); //Restart download to fulfill pending requests
      }
    }
  }

  ///Retrieves the cached response headers, fetching from source if not already cached.
  /// If [fetchLatest] is true, fetches the latest headers from the source URL.
  FutureOr<CachedResponseHeaders> cachedResponseHeaders({final bool fetchLatest = false}) {
    if (!fetchLatest) {
      final headers = metadata.headers;
      if (headers != null) return headers;
    }
    return CachedResponseHeaders.fromUrl(
      sourceUrl,
      httpClient: config.httpClient,
      requestHeaders: config.combinedRequestHeaders(),
    );
  }

  void _setCachedResponseHeaders(CachedResponseHeaders? headers) async {
    try {
      if (!config.saveAllHeaders && headers != null) {
        headers = headers.essentialHeaders();
      }
      _cacheMetadata = _cacheMetadata.setHeaders(headers);
      if (config.saveMetadata || (config.savePartialCache && progress != 1.0)) {
        await files.metadata.writeAsString(jsonEncode(_cacheMetadata.toJson()));
      }
    } catch (e) {
      _addError(e, closeRequests: false);
    }
  }

  double? _calculateCacheProgress() {
    double? cacheProgress;
    try {
      cacheProgress = metadata.cacheProgress();
    } catch (e) {
      _addError(e, closeRequests: false);
    }
    _updateProgressStream(cacheProgress);
    return cacheProgress;
  }

  void _updateProgressStream(final double? progress) {
    if (_lastProgress != progress || !_setProgress) {
      _lastProgress = progress;
      _setProgress = true;
      if (!_progressController.isClosed) {
        _progressController.add(progress);
      }
    }

    if (progress == 1.0 && _queuedRequests.isNotEmpty && metadata.headers != null) {
      _queuedRequests.processAndRemove((request) {
        request.complete(() => StreamResponse.fromFile(request.range, cacheFile, metadata.headers!));
      });
    }
  }

  void _addError(final Object error, {required final bool closeRequests}) {
    _lastError = error;
    if (!_progressController.isClosed) {
      _progressController.addError(error);
    }

    if (closeRequests) {
      _queuedRequests.processAndRemove((request) {
        request.completeError(error);
      });
    }
  }

  void _checkDisposed() {
    if (isDisposed) {
      throw CacheStreamDisposedException(sourceUrl);
    }
  }

  ///Returns a stream of download progress 0-1, rounded to 2 decimal places, and any errors that occur.
  ///Returns null if the source length is unknown. Returns 1.0 only if the cache file exists.
  Stream<double?> get progressStream => _progressController.stream;

  ///Returns true if the cache file exists.
  bool get isCached => cacheFile.existsSync();

  ///If this [HttpCacheStream] has been disposed. A disposed stream cannot be used.
  bool get isDisposed => _disposeCompleter.isCompleted;

  ///If this [HttpCacheStream] is actively downloading data to cache file
  bool get isDownloading => _cacheDownloader?.isActive ?? false;

  ///If this [HttpCacheStream] is retained. A retained stream will not be disposed until the [dispose] method is called the same number of times as [retain] was called.
  bool get isRetained => _retainCount > 0;

  /// The number of times this [HttpCacheStream] has been retained. This is incremented when the stream is obtained using [HttpCacheManager.createStream], and decremented when [dispose] is called.
  int get retainCount => _retainCount;

  ///The latest download progress 0-1, rounded to 2 decimal places. Returns null if the source length is unknown. Returns 1.0 only if the cache file exists.
  double? get progress => _setProgress ? _lastProgress : _calculateCacheProgress();

  ///Returns the last emitted error, or null if error events haven't yet been emitted.
  Object? get lastErrorOrNull => _lastError;

  ///The current [CacheMetadata] for this [HttpCacheStream].
  CacheMetadata get metadata => _cacheMetadata;

  ///The response headers saved in the cache metadata for this [HttpCacheStream]. Returns null if no headers are saved.
  CachedResponseHeaders? get headers => metadata.headers;

  ///The output cache file for this [HttpCacheStream]. This is the file that will be used to save the downloaded content.
  File get cacheFile => files.complete;

  ///Retains this [HttpCacheStream] instance. This method is automatically called when the stream is obtained using [HttpCacheManager.createStream].
  ///The stream will not be disposed until the [dispose] method is called the same number of times as this method.
  void retain() {
    _checkDisposed();
    _retainCount = _retainCount <= 0 ? 1 : _retainCount + 1;
  }

  ///Returns a future that completes when this [HttpCacheStream] is disposed.
  Future get future => _disposeCompleter.future;

  @override
  String toString() => 'HttpCacheStream{sourceUrl: $sourceUrl, cacheUrl: $cacheUrl, cacheFile: $cacheFile}';
}
