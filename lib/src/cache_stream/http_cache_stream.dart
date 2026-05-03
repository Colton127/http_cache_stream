import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http_cache_stream/src/cache_stream/cache_downloader/cache_downloader.dart';
import 'package:http_cache_stream/src/models/cache_config/stream_cache_config.dart';
import 'package:http_cache_stream/src/models/cache_files/cache_files.dart';
import 'package:http_cache_stream/src/models/metadata/cached_response_headers.dart';
import 'package:http_cache_stream/src/models/stream_requests/int_range.dart';
import 'package:synchronized/synchronized.dart';

import '../etc/counters/retain_counter.dart';
import '../etc/extensions/list_extensions.dart';
import '../etc/future_runner.dart';
import '../models/exceptions/http_exceptions.dart';
import '../models/exceptions/invalid_cache_exceptions.dart';
import '../models/exceptions/state_errors.dart';
import '../models/exceptions/stream_response_exceptions.dart';
import '../models/metadata/cache_metadata.dart';
import '../models/stream_requests/stream_request.dart';
import '../models/stream_response/header_stream_response.dart';
import '../models/stream_response/stream_response.dart';

/// A stream that handles downloading, caching, and serving content.
///
/// Use [request] to obtain a stream of data for a specific range.
class HttpCacheStream {
  /// The source Url of the file to be downloaded (e.g., https://example.com/file.mp3)
  final Uri sourceUrl;

  /// The Url of the cached stream (e.g., http://127.0.0.1:8080/file.mp3)
  final Uri cacheUrl;

  /// The complete, partial, and metadata files used for the cache.
  final CacheFiles files;

  /// The cache config used for this stream. By default, values from [GlobalCacheConfig] are used.
  final StreamCacheConfig config;

  final List<StreamRequest> _queuedRequests = [];

  final _progressController = StreamController<double?>.broadcast();
  final _retainCounter = RetainCounter();
  CacheDownloader? _cacheDownloader; //The active cache downloader, if any. This can be used to cancel the download.
  final _downloadFuture = FutureRunner<File>();
  late final _downloadHeadersFuture = FutureRunner<CachedResponseHeaders>();
  final _validateCacheFuture = FutureRunner<bool?>();
  final _initFuture = FutureRunner<void>();
  double? _lastProgress; //The last progress value emitted by the stream
  Object? _lastError; //The last error emitted by the stream
  Timer? _lifeCycleTimer; //Timer for auto-disposing the stream after release
  late final _writeLock = Lock(); //Lock for modifying cache files
  final _disposeCompleter = Completer<void>(); //Completer for the dispose future
  CachedResponseHeaders? _cachedResponseHeaders; //The cached response headers, if any

  HttpCacheStream({
    required this.sourceUrl,
    required this.cacheUrl,
    required this.files,
    required this.config,
  }) {
    _initFuture.run(() async {
      try {
        _cachedResponseHeaders = await CachedResponseHeaders.fromCacheFilesAsync(files);
      } catch (e) {
        _addError(e, closeRequests: false);
      } finally {
        _calculateCacheProgress();
        if (config.validateOutdatedCache) {
          validateCache(force: false, resetInvalid: true).ignore();
        }
      }
    });
  }

  Future<void> _ensureInit() async {
    if (_initFuture.isRunning) await _initFuture();
    if (_validateCacheFuture.isRunning) await _validateCacheFuture();
  }

  /// Requests a [StreamResponse] for the given byte range.
  ///
  /// If [start] or [end] are null, they default to the beginning and end
  /// of the file respectively.
  Future<StreamResponse> request({final int? start, final int? end}) async {
    if (end != null && start == end) {
      return head(start: start, end: end); //Requested range is empty, return only headers
    }
    await _ensureInit();
    _checkDisposed();

    final range = IntRange.validate(start, end, headers?.sourceLength);

    if (isCached) {
      return StreamResponse.fromFile(range, files, headers!);
    }

    final rangeThreshold = config.rangeRequestSplitThreshold;
    if (rangeThreshold != null && range.start >= rangeThreshold && (range.start - cachePosition) >= rangeThreshold) {
      return StreamResponse.fromDownload(sourceUrl, range, config);
    }

    if (!isDownloading) {
      download().ignore(); //Start download
    }

    final streamRequest = StreamRequest.construct(range);
    final downloader = _cacheDownloader;

    if (downloader != null && downloader.processRequest(streamRequest)) {
      return streamRequest.response; //Request was processed immediately
    } else {
      _queuedRequests.addSorted(streamRequest); //Add request to queue, sorted by range

      final requestTimeout = config.requestTimeout;
      final timeoutTimer = Timer(requestTimeout, () {
        _queuedRequests.remove(streamRequest);
        streamRequest.completeError(StreamRequestTimedOutException(requestTimeout));
      });

      return streamRequest.response.whenComplete(timeoutTimer.cancel);
    }
  }

  /// Validates the cache. Returns true if the cache is valid, false if it is not, and null if cache does not exist or is downloading.
  ///
  /// Cache is only revalidated if [CachedResponseHeaders.shouldRevalidate()] or [force] is true.
  /// Partial cache is automatically revalidated when the download is resumed, and cannot be validated manually.
  Future<bool?> validateCache({
    final bool force = false,
    final bool resetInvalid = false,
  }) {
    return _validateCacheFuture.run(() async {
      await _initFuture();
      _checkDisposed();
      if (isDownloading || !isCached) {
        return null; //Cache does not exist or is downloading
      }
      final currentHeaders = _cachedResponseHeaders ??= CachedResponseHeaders.fromFile(cacheFile)!;
      if (!force && currentHeaders.shouldRevalidate() == false) return true;
      try {
        final latestHeaders = await CachedResponseHeaders.fromUrl(
          sourceUrl,
          httpClient: config.httpClient,
          requestHeaders: config.combinedRequestHeaders(),
        ).timeout(config.requestTimeout);

        if (CachedResponseHeaders.validateCacheResponse(currentHeaders, latestHeaders) == true) {
          _setCachedResponseHeaders(latestHeaders);
          return true;
        } else {
          if (resetInvalid) {
            await _resetCache(CacheSourceChangedException(sourceUrl));
          }
          return false;
        }
      } catch (e) {
        _addError(e, closeRequests: false);
        rethrow;
      } finally {
        _calculateCacheProgress();
      }
    });
  }

  /// Requests only the headers for the given byte range.
  Future<HeaderStreamResponse> head({final int? start, final int? end}) async {
    await _ensureInit();
    _checkDisposed();

    final responseHeaders = _cachedResponseHeaders ??
        await CachedResponseHeaders.fromUrl(
          sourceUrl,
          httpClient: config.httpClient,
          requestHeaders: config.combinedRequestHeaders(),
        ).then((headers) {
          _setCachedResponseHeaders(headers);
          return headers;
        }).timeout(
          config.requestTimeout,
          onTimeout: () => throw StreamRequestTimedOutException(config.requestTimeout),
        );

    final range = IntRange.validate(start, end, responseHeaders.sourceLength);
    return HeaderStreamResponse(range, responseHeaders);
  }

  /// Downloads and returns [cacheFile]. If the file already exists, returns immediately. If a download is already in progress, returns the same future.
  ///
  /// This method will return [DownloadStoppedException] if the cache stream is disposed before the download is complete. Other errors will be emitted to the [progressStream].
  Future<File> download() {
    return _downloadFuture.run(() async {
      await _ensureInit();
      _checkDisposed();

      File? completedFile;

      bool isComplete() {
        if (completedFile != null) return true;
        if (_calculateCacheProgress() == 1.0) {
          completedFile = cacheFile;
          return true;
        }
        return false;
      }

      while (isRetained && !isComplete()) {
        try {
          final downloader = _cacheDownloader = CacheDownloader.construct(metadata, config);
          await downloader.download(
            onPosition: (position) {
              const double maxProgressBeforeCompletion = 0.99;
              final int? sourceLength = downloader.sourceLength;
              double? progress;

              if (sourceLength != null) {
                progress = ((position / sourceLength * 100).round() / 100);
                if (progress >= maxProgressBeforeCompletion) {
                  _updateProgressStream(maxProgressBeforeCompletion);
                  return;
                }
              }

              _updateProgressStream(progress);
              while (_queuedRequests.isNotEmpty && downloader.processRequest(_queuedRequests.first)) {
                _queuedRequests.removeAt(0);
              }
            },
            onComplete: () async {
              completedFile = await files.partial.rename(files.complete.path);
              final cachedHeaders = _cachedResponseHeaders!;
              if (cachedHeaders.sourceLength != downloader.downloadPosition || !cachedHeaders.acceptsRangeRequests) {
                _setCachedResponseHeaders(cachedHeaders.setSourceLength(downloader.downloadPosition));
              }
              _updateProgressStream(1.0);
              config.handleCacheCompletion(this, completedFile!);
            },
            onHeaders: (responseHeaders) {
              _setCachedResponseHeaders(responseHeaders);
            },
            onError: (e) {
              assert(e is! InvalidCacheException);
              _addError(e, closeRequests: true);
            },
          );
        } catch (e) {
          _cacheDownloader = null;
          if (e is InvalidCacheException) {
            await _resetCache(e);
          } else if (isRetained) {
            _addError(e, closeRequests: true);
            await Future.delayed(const Duration(seconds: 5));
          }
        }
      }

      _cacheDownloader = null;

      if (!isComplete()) {
        final error = isRetained ? DownloadStoppedException(sourceUrl) : CacheStreamDisposedException(sourceUrl);
        _addError(error, closeRequests: true);
        throw error;
      }

      return completedFile!;
    });
  }

  Future<CachedResponseHeaders> downloadHeaders(bool resetCacheIfInvalid) {
    return _downloadHeadersFuture.run(() async {
      final latestHeaders = await CachedResponseHeaders.fromUrl(
        sourceUrl,
        httpClient: config.httpClient,
        requestHeaders: config.combinedRequestHeaders(),
      ).timeout(config.requestTimeout);

      final currentHeaders = _cachedResponseHeaders;
      if (currentHeaders == null || CachedResponseHeaders.validateCacheResponse(currentHeaders, latestHeaders)) {
        _setCachedResponseHeaders(latestHeaders);
      } else if (resetCacheIfInvalid) {
        await _resetCache(CacheSourceChangedException(sourceUrl));
      }
      return latestHeaders;
    });
  }

  /// Disposes this [HttpCacheStream].
  ///
  /// If [force] is true, the stream will be disposed immediately, regardless of the [retain] count.
  /// Prefer using [release] instead when the stream may be reused again
  /// Returns a future that completes when the stream is disposed.
  Future<void> dispose({final bool force = false}) {
    _retainCounter.release(force: force);
    _performDispose();
    return _disposeCompleter.future;
  }

  void _performDispose() async {
    if (isDisposed || isRetained) return;
    _lifeCycleTimer?.cancel();
    _lifeCycleTimer = null;

    try {
      final downloader = _cacheDownloader;
      if (downloader != null) {
        await downloader.cancel();
        if (isRetained) {
          return; //Stream was retained again during download cancellation
        }
      }
      if (!config.savePartialCache && progress != 1.0) {
        await resetCache();
      } else if (!config.saveMetadata && progress == 1.0 && files.metadata.existsSync()) {
        await _writeLock.synchronized(files.metadata.delete);
        _cachedResponseHeaders = null;
      }
    } catch (e) {
      _addError(e, closeRequests: false);
    } finally {
      if (!_disposeCompleter.isCompleted && !isRetained) {
        _disposeCompleter.complete();
        if (_queuedRequests.isNotEmpty) {
          _addError(CacheStreamDisposedException(sourceUrl), closeRequests: true);
        }
        _progressController.close().ignore();
      }
    }
  }

  /// Resets the cache files used by this [HttpCacheStream], interrupting any ongoing download.
  Future<void> resetCache() => _resetCache(CacheResetException(sourceUrl));

  Future<void> _resetCache(final InvalidCacheException exception) {
    final downloader = _cacheDownloader;
    if (downloader != null && !downloader.isClosed) {
      return downloader.cancel(exception); //Close the ongoing download, which will rethrow the exception and reset the cache
    } else {
      return _writeLock.synchronized(() async {
        if (progress != null || _cachedResponseHeaders != null) {
          try {
            _cachedResponseHeaders = null;
            _updateProgressStream(null);
            if (exception is! CacheResetException) {
              _addError(exception, closeRequests: false);
            }
            await files.delete(partialOnly: false);
          } catch (e) {
            _addError(e, closeRequests: false);
          } finally {
            if (_queuedRequests.isNotEmpty && !isDownloading && isRetained) {
              download().ignore(); //Restart download to fulfill pending requests
            }
          }
        }
      });
    }
  }

  void _setCachedResponseHeaders(CachedResponseHeaders headers) {
    if (!config.saveAllHeaders) {
      headers = headers.essentialHeaders();
    }
    _cachedResponseHeaders = headers;

    _writeLock.synchronized(() async {
      try {
        await files.metadata.parent.create(recursive: true);
        await files.metadata.writeAsString(jsonEncode(metadata.toJson()));
      } catch (e) {
        _addError(e, closeRequests: false);
      }
    });
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
    if (progress != _lastProgress) {
      _lastProgress = progress;
      if (!_progressController.isClosed) {
        _progressController.add(progress);
      }
    }
    if (progress == 1.0 && _queuedRequests.isNotEmpty && headers != null) {
      _queuedRequests.processAndRemove((request) {
        request.complete(() => StreamResponse.fromFile(request.range, files, headers!));
      });
    }
  }

  void _addError(final Object error, {required final bool closeRequests}) {
    _lastError = error;
    if (!_progressController.isClosed && (isRetained || _queuedRequests.isNotEmpty)) {
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

  /// Returns a stream of download progress 0-1, rounded to 2 decimal places, and any errors that occur.
  ///
  /// Returns null if the source length is unknown. Returns 1.0 only if the cache file exists.
  /// To get the latest progress value use the [progress] property.
  Stream<double?> get progressStream => _progressController.stream;

  /// Returns true if the complete cache file and response headers exist. This indicates that the cache is fully available.
  /// This method validates the existence of the cache file and metadata
  bool get isCached {
    if (progress == 1.0) {
      if (_cachedResponseHeaders != null && cacheFile.existsSync()) {
        return true;
      }
      _calculateCacheProgress(); //Cache file is missing or metadata is incomplete, recalculate progress
    }
    return false;
  }

  /// If this [HttpCacheStream] has been disposed. A disposed stream cannot be used.
  bool get isDisposed => _disposeCompleter.isCompleted;

  /// If this [HttpCacheStream] is actively downloading data to cache file.
  bool get isDownloading => _downloadFuture.isRunning;

  /// The current position of the cache file.
  ///
  /// If a download is in progress, returns the current download position.
  /// Otherwise, returns the size of the cache file.
  int get cachePosition {
    final downloadPosition = _cacheDownloader?.downloadPosition;
    if (downloadPosition != null) {
      return downloadPosition;
    } else if (progress != null && headers?.sourceLength != null) {
      return (progress! * headers!.sourceLength!).round();
    } else {
      return files.cacheFileSize() ?? 0;
    }
  }

  /// If this [HttpCacheStream] is retained.
  ///
  /// A retained stream will not be disposed until the [dispose] method is
  /// called the same number of times as [retain] was called.
  bool get isRetained => _retainCounter.isRetained;

  /// The number of active holders of this stream. Starts at 1 when the stream is created.
  /// Incremented by [retain] and decremented by [release] or [dispose].
  int get retainCount => _retainCounter.count;

  /// The latest download progress 0-1, rounded to 2 decimal places.
  ///
  /// Returns null if the source length is unknown. Returns 1.0 only if the cache file exists.
  double? get progress => _lastProgress ?? _calculateCacheProgress();

  /// Returns the last emitted error, or null if error events haven't yet been emitted.
  Object? get lastErrorOrNull => _lastError;

  /// The current [CacheMetadata] for this [HttpCacheStream].
  CacheMetadata get metadata => CacheMetadata(files, sourceUrl, _cachedResponseHeaders);

  /// The cached response headers for this [HttpCacheStream], if available.
  CachedResponseHeaders? get headers => _cachedResponseHeaders;

  /// The output cache file for this [HttpCacheStream].
  ///
  /// This is the file that will be used to save the downloaded content.
  File get cacheFile => files.complete;

  /// Retains this [HttpCacheStream] instance.
  ///
  /// This method is automatically called when the stream is obtained
  /// using [HttpCacheManager.createStream]. The stream will not be
  /// disposed until the [dispose] or [release] method is called the same number of times
  /// as this method.
  void retain() {
    _checkDisposed();
    _retainCounter.retain();
    _lifeCycleTimer?.cancel();
    _lifeCycleTimer = null;
    _cacheDownloader?.resume();
  }

  /// Releases this [HttpCacheStream] instance.
  ///
  /// Once released, [StreamLifecycleConfig.pauseDelay] determines how long to wait
  /// before pausing an ongoing download.  After [StreamLifecycleConfig.disposeDelay]
  /// the stream will be disposed automatically. If [retain] is called before
  /// disposal, the lifecycle timers are cancelled and the download resumes.
  void release() {
    if (!isRetained) return;
    _retainCounter.release();
    _lifeCycleTimer?.cancel();

    if (!isRetained) {
      final lifecycleConfig = config.lifecycleConfig;

      _lifeCycleTimer = Timer(lifecycleConfig.pauseDelay, () {
        final remainingDuration = lifecycleConfig.disposeDelay - lifecycleConfig.pauseDelay;
        if (remainingDuration > Duration.zero) {
          _lifeCycleTimer = Timer(remainingDuration, _performDispose);
          _cacheDownloader?.pause();
        } else {
          _performDispose();
        }
      });
    }
  }

  /// Returns a future that completes when this [HttpCacheStream] is disposed.
  Future get future => _disposeCompleter.future;

  @override
  String toString() => 'HttpCacheStream{sourceUrl: $sourceUrl, cacheUrl: $cacheUrl, cacheFile: $cacheFile}';
}
