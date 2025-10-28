import 'dart:async';
import 'dart:io';

import 'package:http_cache_stream/src/cache_stream/cache_downloader/cache_downloader.dart';
import 'package:http_cache_stream/src/cache_stream/cache_downloader/downloader.dart';
import 'package:http_cache_stream/src/etc/extensions.dart';
import 'package:http_cache_stream/src/models/config/stream_cache_config.dart';
import 'package:http_cache_stream/src/models/metadata/cache_files.dart';
import 'package:http_cache_stream/src/models/metadata/cached_response_headers.dart';
import 'package:http_cache_stream/src/models/stream_response/int_range.dart';

import '../etc/exceptions.dart';
import '../models/metadata/cache_metadata.dart';
import '../models/stream_response/stream_request.dart';
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
  CacheDownloader?
      _cacheDownloader; //The active cache downloader, if any. This can be used to cancel the download.
  int _retainCount = 1; //The number of times the stream has been retained
  Future<File>? _downloadFuture; //The future for the current download, if any.
  Future<bool>? _validateCacheFuture;
  double? _lastProgress; //The last progress value emitted by the stream
  Object? _lastError; //The last error emitted by the stream
  bool _initProgressEmitted =
      false; //Whether the initial progress value has been emitted
  final _disposeCompleter =
      Completer<void>(); //Completer for the dispose future
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
    _progressController.onListen = () {
      _progressController.onListen = null;
      if (!_initProgressEmitted) _getCacheProgress();
    };
  }

  Future<StreamResponse> request({final int? start, final int? end}) async {
    if (_validateCacheFuture != null) {
      await _validateCacheFuture!;
    }
    final range = IntRange.construct(start, end, metadata.sourceLength);
    final completedCacheSize = cacheFile.statSync().size;
    if (completedCacheSize > 0) {
      _updateProgressStream(1.0);
      return StreamResponse.fromFile(range, cacheFile, completedCacheSize);
    }
    _checkDisposed();
    if (!isDownloading) {
      download().ignore(); //Start download
    }

    final downloader = _cacheDownloader;
    if (downloader != null && downloader.isActive) {
      final downloadPosition = downloader.downloadPosition;
      if (downloadPosition > 0) {
        final bytesRemaining = range.start - downloadPosition;
        if (bytesRemaining <= 0) {
          final streamRequest = StreamRequest.construct(range);
          downloader.processRequest(
              streamRequest); //Process request with the downloader immediately
          return streamRequest.response;
        } else if (downloader.acceptRangeRequests) {
          final rangeThreshold = config.rangeRequestSplitThreshold;
          if (rangeThreshold != null && bytesRemaining > rangeThreshold) {
            return StreamResponse.fromDownload(sourceUrl, range,
                config); //Serve request directly from download
          }
        }
      }
    }

    final streamRequest = StreamRequest.construct(range);
    _queuedRequests.add(streamRequest); //Add request to queue
    return streamRequest.response;
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
    if (isDownloading || _getCacheProgress() != 1.0) {
      return null; //Cache does not exist or is downloading
    }
    final currentHeaders =
        metadata.headers ?? CachedResponseHeaders.fromFile(cacheFile)!;
    if (!force && currentHeaders.shouldRevalidate() == false) return true;
    _validateCacheFuture = CachedResponseHeaders.fromUrl(
      sourceUrl,
      httpClient: config.httpClient,
      requestHeaders: config.combinedRequestHeaders(),
    ).then((latestHeaders) async {
      if (currentHeaders.validate(latestHeaders) == true) {
        _setCachedResponseHeaders(latestHeaders);
        return true;
      } else {
        if (resetInvalid) {
          await resetCache(CacheSourceChangedException(sourceUrl));
        }
        return false;
      }
    }).whenComplete(() {
      _validateCacheFuture = null;
      _getCacheProgress();
    });
    return _validateCacheFuture;
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
      final completed = _getCacheProgress() == 1.0;
      if (completed) {
        downloadCompleter.complete(cacheFile);
      }
      return completed;
    }

    try {
      while (isRetained && !isComplete()) {
        try {
          final downloader =
              _cacheDownloader = CacheDownloader.construct(metadata, config);
          await downloader.download(
            onPosition: (position) {
              final int? sourceLength = downloader.sourceLength;

              if (sourceLength == null || sourceLength <= 0) {
                _updateProgressStream(null);
              } else {
                final progress =
                    ((position / sourceLength * 100).round() / 100);
                if (progress >= 0.99) {
                  _updateProgressStream(
                      0.99); //Avoid setting progress to 1.0 before completion
                  return; //If near completion, avoid processing requests using partial data.
                }
                _updateProgressStream(progress);
              }

              if (_queuedRequests.isEmpty) return;

              final rangeThreshold = downloader.acceptRangeRequests
                  ? config.rangeRequestSplitThreshold
                  : null;
              _queuedRequests.removeWhere((request) {
                final bytesRemaining = request.start - position;
                if (bytesRemaining <= 0) {
                  downloader.processRequest(request);
                  return true;
                } else if (rangeThreshold != null &&
                    bytesRemaining > rangeThreshold) {
                  request.complete(StreamResponse.fromDownload(
                      sourceUrl, request.range, config));
                  return true;
                } else {
                  return false;
                }
              });
            },
            onComplete: () async {
              await files.partial.rename(files.complete.path);
              config.onCacheComplete(this, files.complete);
              final cachedHeaders = metadata.headers!;
              if (cachedHeaders.sourceLength != downloader.downloadPosition ||
                  !cachedHeaders.acceptsRangeRequests) {
                _setCachedResponseHeaders(
                    cachedHeaders.setSourceLength(downloader.downloadPosition));
              }
            },
            onHeaders: (cacheHttpHeaders) {
              _setCachedResponseHeaders(cacheHttpHeaders);
            },
            onError: (e) {
              _addError(e, closeRequests: true);
            },
          );
        } catch (e) {
          _cacheDownloader = null;
          if (e is InvalidCacheException) {
            await resetCache(e);
          } else if (isRetained) {
            _addError(e, closeRequests: true);
            await Future.delayed(const Duration(seconds: 5));
          }
        }
      }
    } finally {
      _cacheDownloader = null;
      _downloadFuture = null;

      if (!isComplete()) {
        final error = isRetained
            ? DownloadStoppedException(sourceUrl)
            : CacheStreamDisposedException(sourceUrl);
        downloadCompleter.future
            .ignore(); // Prevent unhandled error during completion
        downloadCompleter.completeError(error);
        _addError(error, closeRequests: true);
      }
    }

    return downloadCompleter.future;
  }

  ///Disposes this [HttpCacheStream]. This method should be called when you are done with the stream.
  ///If [force] is true, the stream will be disposed immediately, regardless of the [retain] count. [retain] is incremented when the stream is obtained using [HttpCacheManager.createStream].
  ///Returns a future that completes when the stream is disposed.
  Future<void> dispose({final bool force = false}) async {
    if (isDisposed) return;

    if (!force && _retainCount > 1) {
      _retainCount--;
    } else {
      _retainCount = 0;
      late final error = CacheStreamDisposedException(sourceUrl);
      if (_queuedRequests.isNotEmpty) {
        _addError(error, closeRequests: true);
      }
      final downloader = _cacheDownloader;
      if (downloader != null) {
        await downloader
            .cancel(error)
            .ignoreError(); //Allow downloader to complete cleanly
      }

      if (!_disposeCompleter.isCompleted && !isRetained) {
        _disposeCompleter.complete();
        _progressController.close().ignore();
        if (!config.savePartialCache) {
          files.delete(partialOnly: true).ignore();
        }
        if (!config.saveMetadata &&
            files.metadata.existsSync() &&
            cacheFile.existsSync()) {
          files.metadata.delete().ignore();
        }
      }
    }

    return _disposeCompleter.future;
  }

  ///Resets the cache files used by this [HttpCacheStream], interrupting any ongoing download.
  Future<void> resetCache([InvalidCacheException? exception]) async {
    final error = exception ?? CacheDeletedException(sourceUrl);
    final downloader = _cacheDownloader;
    if (downloader != null && downloader.isActive) {
      return downloader.cancel(
          error); //Close the ongoing download, which will rethrow the exception and reset the cache
    } else {
      _queuedRequests.removeWhere((request) {
        if (request.isRangeRequest) {
          //If the request is a range request, complete it with an error as it will not be valid anymore
          request.completeError(error);
          return true;
        }
        return false;
      });
      _cacheMetadata = _cacheMetadata.copyWith(headers: null);
      _updateProgressStream(null);
      _addError(error, closeRequests: false);
      await files.delete().catchError((_) => false);
      if (_queuedRequests.isNotEmpty && !isDownloading && isRetained) {
        download().ignore(); //Restart download to fulfill pending requests
      }
    }
  }

  void _setCachedResponseHeaders(CachedResponseHeaders headers) {
    _validateRequests(_cacheMetadata.sourceLength, headers.sourceLength);
    _cacheMetadata = _cacheMetadata.copyWith(headers: headers)..save();
  }

  ///Validates the requests in the queue. If any requests exceed the new source length, they are removed from the queue and completed with a [RangeError].
  void _validateRequests(int? previousSourceLength, int? nextSourceLength) {
    if (_queuedRequests.isEmpty ||
        nextSourceLength == null ||
        previousSourceLength == nextSourceLength) {
      return;
    }
    _queuedRequests.removeWhere((request) {
      if (request.range.exceeds(nextSourceLength)) {
        request.completeError(
          RangeError.range(request.range.greatest, 0, nextSourceLength),
        );
        return true;
      }
      return false;
    });
  }

  double? _getCacheProgress() {
    final cacheProgress = metadata.cacheProgress();
    _updateProgressStream(cacheProgress);
    return cacheProgress;
  }

  void _updateProgressStream(final double? progress) {
    _initProgressEmitted = true;

    if (progress == 1.0 && _queuedRequests.isNotEmpty) {
      _queuedRequests.removeWhere((request) {
        request.complete(
          StreamResponse.fromFile(
            request.range,
            cacheFile,
            metadata.sourceLength,
          ),
        );
        return true;
      });
    }

    if (progress != _lastProgress) {
      _lastProgress = progress;
      if (_progressController.hasListener && !_progressController.isClosed) {
        _progressController.add(progress);
      }
    }
  }

  void _addError(final Object error, {final bool closeRequests = true}) {
    _lastError = error;
    if (_progressController.hasListener && !_progressController.isClosed) {
      _progressController.addError(error);
    }
    if (closeRequests) {
      _queuedRequests.removeWhere((request) {
        request.completeError(error);
        return true;
      });
    }
  }

  void _checkDisposed() {
    if (isDisposed) {
      throw CacheStreamDisposedException(sourceUrl);
    }
  }

  ///Retains this [HttpCacheStream] instance, increasing [retainCount] by 1. This method is automatically called when the stream is obtained using [HttpCacheManager.createStream].
  ///The stream will not be disposed until the [dispose] method is called the same number of times as this method.
  void retain() {
    _checkDisposed();
    _retainCount = _retainCount <= 0 ? 1 : _retainCount + 1;
  }

  ///Returns a stream of download progress 0-1, rounded to 2 decimal places, and any errors that occur.
  ///Returns null if the source length is unknown. Returns 1.0 only if the cache file exists.
  Stream<double?> get progressStream => _progressController.stream;

  ///Returns true if the cache file exists.
  bool get isCached => cacheFile.existsSync();

  ///If this [HttpCacheStream] has been disposed. A disposed stream cannot be used.
  bool get isDisposed => _disposeCompleter.isCompleted;

  ///If this [HttpCacheStream] is actively downloading data to cache file
  bool get isDownloading => _downloadFuture != null;

  ///If this [HttpCacheStream] is retained. A retained stream will not be disposed until the [dispose] method is called the same number of times as [retain] was called.
  bool get isRetained => _retainCount > 0;

  /// The number of times this [HttpCacheStream] has been retained. This is incremented when the stream is obtained using [HttpCacheManager.createStream], and decremented when [dispose] is called.
  int get retainCount => _retainCount;

  ///The latest download progress 0-1, rounded to 2 decimal places. Returns null if the source length is unknown. Returns 1.0 only if the cache file exists.
  double? get progress {
    if (!_initProgressEmitted) _getCacheProgress();
    return _lastProgress;
  }

  ///Returns the last emitted error, or null if error events haven't yet been emitted.
  Object? get lastErrorOrNull => _lastError;

  ///The current [CacheMetadata] for this [HttpCacheStream].
  CacheMetadata get metadata => _cacheMetadata;

  ///The output cache file for this [HttpCacheStream]. This is the file that will be used to save the downloaded content.
  File get cacheFile => files.complete;

  ///Returns a future that completes when this [HttpCacheStream] is disposed.
  Future get future => _disposeCompleter.future;

  @override
  String toString() =>
      'HttpCacheStream{sourceUrl: $sourceUrl, cacheUrl: $cacheUrl, cacheFile: $cacheFile}';
}
