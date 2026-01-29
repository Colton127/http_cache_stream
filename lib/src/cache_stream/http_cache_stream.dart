import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http_cache_stream/src/cache_stream/cache_downloader/cache_downloader.dart';
import 'package:synchronized/synchronized.dart';

import '../../http_cache_stream.dart';
import '../etc/extensions/list_extensions.dart';
import '../models/stream_requests/stream_request.dart';
import '../models/stream_response/head_stream_response.dart';

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

  /// The list of queued [StreamRequest] waiting to be processed, sorted asc by start position.
  final List<StreamRequest> _queuedRequests = [];

  final _progressController = StreamController<double?>.broadcast();
  CacheDownloader? _cacheDownloader; //The active cache downloader, if any. This can be used to cancel the download.
  int _retainCount = 1; //The number of times the stream has been retained
  Future<File>? _downloadFuture; //The future for the current download, if any.
  Future<bool>? _validateCacheFuture;
  Future<CachedResponseHeaders>? _downloadHeadersFuture;
  double? _lastProgress; //The last progress value emitted by the stream
  Object? _lastError; //The last error emitted by the stream
  late final _writeLock = Lock(); //Lock for modifying cache files
  final _disposeCompleter = Completer<void>(); //Completer for the dispose future
  CacheMetadata _cacheMetadata; //The metadata for the cache

  HttpCacheStream({
    required this.sourceUrl,
    required this.cacheUrl,
    required this.files,
    required this.config,
  }) : _cacheMetadata = CacheMetadata.construct(files, sourceUrl) {
    if (config.validateOutdatedCache) {
      validateCache(force: false, resetInvalid: true).ignore();
    }
  }

  /// Returns a [StreamResponse] for the given byte range.
  ///
  /// If [start] or [end] are null, they default to the beginning and end
  /// of the file respectively.
  Future<StreamResponse> request({final int? start, final int? end}) async {
    if (_validateCacheFuture != null) {
      await _validateCacheFuture!;
    }
    _checkDisposed();
    final range = IntRange.validate(start, end, metadata.sourceLength);
    if (range.isEmpty) {
      return HeaderStreamResponse(range, await downloadResponseHeaders(refresh: false));
    }

    if (metadata.headers != null && isCached) {
      return StreamResponse.fromFile(range, files, metadata.headers!);
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
      _queuedRequests.addSorted(streamRequest); //Add request to queue, sorted by start position

      final timeoutTimer = Timer(config.readTimeout, () {
        _queuedRequests.remove(streamRequest);
        streamRequest.completeError(ResponseTimedOutException(sourceUrl, config.readTimeout));
      });

      return streamRequest.response.whenComplete(timeoutTimer.cancel);
    }
  }

  /// Requests only the headers for the given byte range.
  Future<HeaderStreamResponse> head({final int? start, final int? end}) async {
    final range = IntRange.validate(start, end, metadata.sourceLength);
    final responseHeaders = await downloadResponseHeaders(refresh: false);
    return HeaderStreamResponse(range, responseHeaders);
  }

  /// Validates the cache. Returns true if the cache is valid, false if it is not, and null if cache does not exist or is downloading.
  ///
  /// Cache is only revalidated if [CachedResponseHeaders.shouldRevalidate()] or [force] is true.
  /// Partial cache is automatically revalidated when the download is resumed, and cannot be validated manually.
  Future<bool?> validateCache({
    final bool force = false,
    final bool resetInvalid = false,
  }) async {
    if (_validateCacheFuture != null) {
      return _validateCacheFuture;
    }
    if (isDownloading || !cacheFile.existsSync()) {
      return null; //Cache does not exist or is downloading
    }
    final currentHeaders = metadata.headers ?? CachedResponseHeaders.fromFile(cacheFile)!;
    if (!force && currentHeaders.shouldRevalidate() == false) return true;
    _validateCacheFuture = CachedResponseHeaders.fromUrl(
      sourceUrl,
      httpClient: config.httpClient,
      requestHeaders: config.combinedRequestHeaders(),
    ).then((latestHeaders) async {
      if (CachedResponseHeaders.validateCacheResponse(currentHeaders, latestHeaders) == true) {
        _setCachedResponseHeaders(latestHeaders);
        return true;
      } else {
        if (resetInvalid) {
          await _resetCache(CacheSourceChangedException(sourceUrl));
        }
        return false;
      }
    }).whenComplete(() {
      _validateCacheFuture = null;
      _calculateCacheProgress();
    });
    return _validateCacheFuture;
  }

  /// Downloads, saves, and returns the latest [CachedResponseHeaders] from the source URL.
  ///
  /// If [refresh] is false and headers are already cached, returns the cached headers.
  Future<CachedResponseHeaders> downloadResponseHeaders({final bool refresh = false}) {
    final cachedHeaders = refresh ? null : metadata.headers;
    if (cachedHeaders != null) {
      return Future.value(cachedHeaders);
    }
    return _downloadHeadersFuture ??= () async {
      try {
        final headers = await CachedResponseHeaders.fromUrl(
          sourceUrl,
          httpClient: config.httpClient,
          requestHeaders: config.combinedRequestHeaders(),
        );
        _setCachedResponseHeaders(headers);
        return headers;
      } catch (e) {
        _addError(e, closeRequests: false);
        rethrow;
      } finally {
        _downloadHeadersFuture = null;
      }
    }();
  }

  /// Downloads and returns [cacheFile]. If the file already exists, returns immediately. If a download is already in progress, returns the same future.
  ///
  /// This method will return [DownloadStoppedException] if the cache stream is disposed before the download is complete. Other errors will be emitted to the [progressStream].
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
            const double maxProgressBeforeCompletion = 0.99; //To avoid setting progress to 1.0 before complete cache is ready
            final int? sourceLength = downloader.sourceLength;
            double? progress;

            if (sourceLength != null) {
              progress = ((position / sourceLength * 100).round() / 100); //Round to 2 decimal places
              if (progress >= maxProgressBeforeCompletion) {
                _updateProgressStream(maxProgressBeforeCompletion);
                return; //Avoid processing queued requests until download is complete
              }
            }

            _updateProgressStream(progress);
            while (_queuedRequests.isNotEmpty && downloader.processRequest(_queuedRequests.first)) {
              _queuedRequests.removeAt(0);
            }
          },
          onComplete: () async {
            final completedCacheFile = await _writeLock.synchronized(() => files.partial.rename(files.complete.path));
            final cachedHeaders = metadata.headers!;
            if (cachedHeaders.sourceLength != downloader.downloadPosition || !cachedHeaders.acceptsRangeRequests) {
              _setCachedResponseHeaders(cachedHeaders.setSourceLength(downloader.downloadPosition));
            }
            _updateProgressStream(1.0);
            downloadCompleter.complete(completedCacheFile);
            config.onCacheComplete(this, completedCacheFile);
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
        assert(_cacheDownloader?.isActive == false, 'Downloader should not be active after an error');
        _cacheDownloader = null;
        if (e is InvalidCacheException) {
          await _resetCache(e);
        } else if (isRetained) {
          _addError(e, closeRequests: true);
          await Future.delayed(config.retryDelay);
        }
      }
    }
    _cacheDownloader = null;
    _downloadFuture = null;
    if (!isComplete()) {
      final error = isRetained ? CacheDownloadStoppedException(sourceUrl) : CacheStreamDisposedException(sourceUrl);
      downloadCompleter.future.ignore(); // Prevent unhandled error during completion
      downloadCompleter.completeError(error);
      if (_queuedRequests.isNotEmpty) {
        _addError(error, closeRequests: true);
      }
    }
    return downloadCompleter.future;
  }

  /// Disposes this [HttpCacheStream]. This method should be called when you are done with the stream.
  ///
  /// If [force] is true, the stream will be disposed immediately, regardless of the [retain] count.
  /// [retain] is incremented when the stream is obtained using [HttpCacheManager.createStream].
  /// Returns a future that completes when the stream is disposed.
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
              if (isRetained) return; //Stream was retained again during download cancellation
            }
            if (!config.savePartialCache && progress != 1.0) {
              await _writeLock.synchronized(() => files.delete(partialOnly: true));
            } else if (!config.saveMetadata && progress == 1.0 && files.metadata.existsSync()) {
              await _writeLock.synchronized(files.metadata.delete);
            }
          } catch (e) {
            _addError(e, closeRequests: false);
          } finally {
            if (!_disposeCompleter.isCompleted && !isRetained) {
              _disposeCompleter.complete();
              if (_queuedRequests.isNotEmpty) {
                _addError(error, closeRequests: true);
              }
              _progressController.close().ignore();
            }
          }
        }();
      }
    }

    return _disposeCompleter.future;
  }

  /// Resets the cache files used by this [HttpCacheStream], interrupting any ongoing download.
  Future<void> resetCache() => _resetCache(CacheResetException(sourceUrl));

  Future<void> _resetCache(final InvalidCacheException exception) async {
    final downloader = _cacheDownloader;
    if (downloader != null && downloader.isActive) {
      return downloader.cancel(exception); //Close the ongoing download, which will rethrow the exception and reset the cache
    } else if (progress != null || metadata.headers != null) {
      _cacheMetadata = _cacheMetadata.setHeaders(null);
      _updateProgressStream(null);
      if (exception is! CacheResetException) {
        _addError(exception, closeRequests: false);
      }
      try {
        await _writeLock.synchronized(files.delete);
      } catch (e) {
        _addError(e, closeRequests: false);
      }
      if (_queuedRequests.isNotEmpty && !isDownloading && isRetained) {
        download().ignore(); //Restart download to fulfill pending requests
      }
    }
  }

  void _setCachedResponseHeaders(CachedResponseHeaders headers) async {
    try {
      if (!config.saveAllHeaders) {
        headers = headers.essentialHeaders();
      }
      _cacheMetadata = _cacheMetadata.setHeaders(headers);
      await _writeLock.synchronized(() async {
        await files.metadata.parent.create(recursive: true);
        await files.metadata.writeAsString(jsonEncode(_cacheMetadata.toJson()));
      });
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
    if (progress != _lastProgress) {
      _lastProgress = progress;
      if (!_progressController.isClosed) {
        _progressController.add(progress);
      }
    }
    if (progress == 1.0 && _queuedRequests.isNotEmpty && metadata.headers != null) {
      _queuedRequests.processAndRemove((request) {
        request.complete(() => StreamResponse.fromFile(request.range, files, metadata.headers!));
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

  // /// Returns true if the cache file exists.
  // bool get isCached => progress == 1.0;

  /// Returns true if the cache file exists.
  bool get isCached {
    //Validate progress to ensure file existence
    return progress == 1.0 && _calculateCacheProgress() == 1.0;
  }

  /// If this [HttpCacheStream] has been disposed. A disposed stream cannot be used.
  bool get isDisposed => _disposeCompleter.isCompleted;

  /// If this [HttpCacheStream] is actively downloading data to cache file.
  bool get isDownloading => _cacheDownloader?.isActive ?? false;

  /// The current position of the cache file.
  ///
  /// If a download is in progress, returns the current download position.
  /// Otherwise, returns the size of the cache file.
  int get cachePosition {
    final downloadPosition = _cacheDownloader?.downloadPosition;
    if (downloadPosition != null) {
      return downloadPosition;
    } else if (progress != null && metadata.sourceLength != null) {
      return (progress! * metadata.sourceLength!).round();
    } else {
      return files.cacheFileSize() ?? 0;
    }
  }

  /// If this [HttpCacheStream] is retained.
  ///
  /// A retained stream will not be disposed until the [dispose] method is
  /// called the same number of times as [retain] was called.
  bool get isRetained => _retainCount > 0;

  /// The number of times this [HttpCacheStream] has been retained.
  ///
  /// This is incremented when the stream is obtained using [HttpCacheManager.createStream],
  /// and decremented when [dispose] is called.
  int get retainCount => _retainCount;

  /// The latest download progress 0-1, rounded to 2 decimal places.
  ///
  /// Returns null if the source length is unknown. Returns 1.0 only if the cache file exists.
  double? get progress => _lastProgress ?? _calculateCacheProgress();

  /// Returns the last emitted error, or null if error events haven't yet been emitted.
  Object? get lastErrorOrNull => _lastError;

  /// The current [CacheMetadata] for this [HttpCacheStream].
  CacheMetadata get metadata => _cacheMetadata;

  /// The output cache file for this [HttpCacheStream].
  ///
  /// This is the file that will be used to save the downloaded content.
  File get cacheFile => files.complete;

  /// Retains this [HttpCacheStream] instance.
  ///
  /// This method is automatically called when the stream is obtained
  /// using [HttpCacheManager.createStream]. The stream will not be
  /// disposed until the [dispose] method is called the same number of times
  /// as this method.
  void retain() {
    _checkDisposed();
    _retainCount = _retainCount <= 0 ? 1 : _retainCount + 1;
  }

  /// Returns a future that completes when this [HttpCacheStream] is disposed.
  Future get future => _disposeCompleter.future;

  @override
  String toString() => 'HttpCacheStream{sourceUrl: $sourceUrl, cacheUrl: $cacheUrl, cacheFile: $cacheFile}';
}
