import 'dart:async';
import 'dart:io';
import 'dart:math' show min;

import 'package:http_cache_stream/src/cache_stream/cache_downloader/cache_downloader.dart';
import 'package:http_cache_stream/src/etc/extensions/future_extensions.dart';
import 'package:http_cache_stream/src/models/cache_config/stream_cache_config.dart';
import 'package:http_cache_stream/src/models/cache_files/cache_files.dart';
import 'package:http_cache_stream/src/models/metadata/cached_response_headers.dart';
import 'package:http_cache_stream/src/models/stream_requests/int_range.dart';
import 'package:rxdart/subjects.dart';
import 'package:synchronized/synchronized.dart';

import '../etc/counters/retain_counter.dart';
import '../etc/extensions/list_extensions.dart';
import '../etc/future_runner.dart';
import '../etc/helpers.dart';
import '../models/cache_state/cache_state.dart';
import '../models/exceptions/http_exceptions.dart';
import '../models/exceptions/invalid_cache_exceptions.dart';
import '../models/exceptions/state_errors.dart';
import '../models/exceptions/stream_response_exceptions.dart';
import '../models/metadata/cache_metadata.dart';
import '../models/stream_requests/stream_request.dart';
import '../models/stream_response/file_stream_response.dart';
import '../models/stream_response/header_stream_response.dart';
import '../models/stream_response/range_download_stream_response.dart';
import '../models/stream_response/stream_response.dart';

/// A stream that handles downloading, caching, and serving content.
///
/// Use [request] to obtain a stream of data for a specific range.
class HttpCacheStream {
  /// The source Url of the file to be downloaded (e.g., https://example.com/file.mp3)
  final Uri sourceUrl;

  /// The Url of the cached stream served by the local cache server (e.g., http://localhost:8080/http/example.com/file.mp3)
  ///
  /// Throws a [CacheServerUnavailableException] when the stream has no cache URL, which is the case when
  /// `HttpCacheManager.init` was called with `startServer: false`. Check [hasCacheUrl] first, or read the content
  /// through [request] instead.
  Uri get cacheUrl =>
      _cacheUrl ?? (throw CacheServerUnavailableException(sourceUrl));
  final Uri? _cacheUrl;

  /// Whether this stream is served by the local cache server, i.e. whether [cacheUrl] is available.
  bool get hasCacheUrl => _cacheUrl != null;

  /// The complete, partial, and metadata files used for the cache.
  final CacheFiles files;

  /// The cache config used for this stream. By default, values from [GlobalCacheConfig] are used.
  final StreamCacheConfig config;

  final List<StreamRequest> _queuedRequests = [];

  final _stateController = BehaviorSubject<CacheState>();
  final _retainCounter = RetainCounter();
  CacheDownloader?
      _cacheDownloader; //The active cache downloader, if any. This can be used to cancel the download.
  final _downloadFuture = FutureRunner<File>();
  late final _downloadHeadersFuture = FutureRunner<CachedResponseHeaders>();
  final _validateCacheFuture = FutureRunner<bool?>();
  final _initFuture = FutureRunner<void>();
  Timer? _lifeCycleTimer; //Timer for auto-disposing the stream after release
  final _fileLock = Lock(); //Lock for modifying cache files
  final _disposeCompleter =
      Completer<void>(); //Completer for the dispose future
  CachedResponseHeaders?
      _cachedResponseHeaders; //The cached response headers, if any

  HttpCacheStream({
    required this.sourceUrl,
    final Uri? cacheUrl,
    required this.files,
    required this.config,
  }) : _cacheUrl = cacheUrl {
    _initFuture.run(() async {
      try {
        _cachedResponseHeaders =
            await CachedResponseHeaders.fromCacheFilesAsync(files);
      } catch (e) {
        _addError(e, closeRequests: false);
      } finally {
        await refreshCacheState();
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
      return head(
          start: start,
          end: end); //Requested range is empty, return only headers
    }
    await _ensureInit();
    _checkDisposed();

    //Revalidated for every request: cache files deleted or changed underneath
    //(by the device's cache management, say) reset the cache here, and the
    //request waits for its range to download again, rather than its response
    //failing to read them.
    final state = await refreshCacheState();
    final responseHeaders = _cachedResponseHeaders;
    final range = IntRange.validate(start, end, responseHeaders?.sourceLength);

    if (responseHeaders != null && state.isComplete) {
      return FileStreamResponse(range, files, responseHeaders);
    }

    final rangeThreshold = config.rangeRequestSplitThreshold;
    if (rangeThreshold != null &&
        range.start >= rangeThreshold &&
        (range.start - state.position) >= rangeThreshold) {
      return RangeDownloadStreamResponse.construct(sourceUrl, range, config);
    }

    if (!isDownloading) {
      download().ignore(); //Start download
    }

    final streamRequest = StreamRequest.construct(range);
    final downloader = _cacheDownloader;

    if (downloader != null && downloader.processRequest(streamRequest)) {
      return streamRequest.response; //Request was processed immediately
    } else {
      _queuedRequests
          .addSorted(streamRequest); //Add request to queue, sorted by range

      final requestTimeout = config.requestTimeout;
      final timeoutTimer = Timer(requestTimeout, () {
        _queuedRequests.remove(streamRequest);
        streamRequest
            .completeError(StreamRequestTimedOutException(requestTimeout));
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
      if (isDownloading || !cacheState.isComplete) {
        return null; //Cache does not exist or is downloading
      }
      final currentHeaders =
          _cachedResponseHeaders ??= CachedResponseHeaders.fromFile(cacheFile)!;
      if (!force && currentHeaders.shouldRevalidate() == false) return true;
      try {
        final latestHeaders = await downloadHeaders(save: false);
        if (CachedResponseHeaders.validateCacheResponse(
                currentHeaders, latestHeaders) ==
            true) {
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
        await refreshCacheState();
      }
    });
  }

  /// Requests only the headers for the given byte range.
  Future<HeaderStreamResponse> head({final int? start, final int? end}) async {
    await _ensureInit();
    _checkDisposed();

    final responseHeaders =
        _cachedResponseHeaders ?? await downloadHeaders(save: true);
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

      ///Attempts in a row that ended on an error, see [_retryDelay].
      int failedAttempts = 0;
      while (true) {
        final state = await refreshCacheState();
        if (state.isComplete) {
          return files.complete;
        }
        if (!isRetained) {
          throw DownloadStoppedException(sourceUrl);
        }

        ///The content is fully downloaded, but the cache file could not be renamed because a response stream still holds the partial cache file open.
        ///There is nothing left to download; wait for it to be released, then let [refreshCacheState] rename it.
        if (state.sourceLength case final int sourceLength
            when state.position >= sourceLength) {
          await Future.delayed(const Duration(seconds: 10));
          continue;
        }

        ///The error this attempt ended on: one reported after the download last moved on.
        Object? endError;
        try {
          final downloader =
              _cacheDownloader = CacheDownloader.construct(metadata, config);
          await downloader.download(
            onPosition: (position) {
              endError = null; //It moved on, past any error before
              _updateCacheState(CacheState.incomplete(
                  position, downloader.sourceLength,
                  filePosition: downloader.filePosition));
              while (_queuedRequests.isNotEmpty &&
                  downloader.processRequest(_queuedRequests.first)) {
                _queuedRequests.removeAt(0);
              }
            },
            onComplete: (sourceLength) async {
              final cachedHeaders = _cachedResponseHeaders!;
              if (cachedHeaders.sourceLength != sourceLength ||
                  !cachedHeaders.acceptsRangeRequests ||
                  cachedHeaders.isCompressedOrChunked) {
                await _setCachedResponseHeaders(
                    cachedHeaders.setSourceLength(sourceLength));
              }
              //Handles validating and renaming partial cache to complete.
              await refreshCacheState();
            },
            onHeaders: (responseHeaders) {
              _setCachedResponseHeaders(responseHeaders);
            },
            onError: (e) {
              assert(e is! InvalidCacheException);
              endError = e;
              _addError(e, closeRequests: true);
            },
          );
        } catch (e) {
          if (e is InvalidCacheException) {
            await _resetCache(e);
            if (isRetained) continue; //Retry download after resetting cache
          } else {
            _addError(e, closeRequests: true);
          }
          if (!isRetained) rethrow;
          await Future.delayed(const Duration(seconds: 5));
          continue;
        } finally {
          _cacheDownloader = null;
        }

        if (endError == null) {
          failedAttempts = 0;
        } else if (isRetained) {
          await Future.delayed(_retryDelay(++failedAttempts));
        }
      }
    });
  }

  ///How long [download] waits after its [attempts]th attempt in a row that ended on an error: 5 s,
  ///doubling to a minute. The downloader retries what the network does itself, after 5 s; an
  ///attempt ends on an error when it gives up, as a write to the cache file that fails (a full
  ///disk) gives it up, and without the wait the next attempt would request the source again at
  ///once, and fail again.
  static Duration _retryDelay(final int attempts) =>
      Duration(seconds: min(5 << min(attempts - 1, 4), 60));

  Future<CachedResponseHeaders> downloadHeaders({bool save = true}) {
    return _downloadHeadersFuture.run(() async {
      final latestHeaders = await CachedResponseHeaders.fromUrl(
        sourceUrl,
        httpClient: config.httpClient,
        requestHeaders: config.combinedRequestHeaders(),
      ).timeout(
        config.requestTimeout,
        onTimeout: () => throw RequestTimedOutException(
          sourceUrl,
          config.requestTimeout,
        ),
      );
      if (save && !isDisposed) {
        _setCachedResponseHeaders(latestHeaders);
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
    _disposeRequested = true;
    _retainCounter.release(force: force);
    _performDispose();
    return _disposeCompleter.future;
  }

  bool _disposeRequested = false; //If dispose() has been requested
  bool _disposing = false;
  void _performDispose() async {
    if (isDisposed || isRetained || _disposing) return;
    _disposing = true;

    _lifeCycleTimer?.cancel();
    _lifeCycleTimer = null;

    try {
      final downloader = _cacheDownloader;
      if (downloader != null) {
        await downloader.cancel().ignoreResult();
        if (isRetained) {
          return; //Stream was retained again during download cancellation
        }
      }

      if (!config.savePartialCache && !(await refreshCacheState()).isComplete) {
        await resetCache();
      } else if (!config.saveMetadata &&
          (await refreshCacheState()).isComplete) {
        await _fileLock.synchronized(() async {
          if (await files.metadata.exists()) {
            await files.metadata.delete();
          }
        });
      }
    } catch (e) {
      _addError(e, closeRequests: false);
    } finally {
      _disposing = false;
      if (!_disposeCompleter.isCompleted && !isRetained) {
        _disposeCompleter.complete();
        if (_queuedRequests.isNotEmpty) {
          _addError(CacheStreamDisposedException(sourceUrl),
              closeRequests: true);
        }
        _stateController.close().ignore();
      }
    }
  }

  /// Resets the cache files used by this [HttpCacheStream], interrupting any ongoing download.
  Future<void> resetCache() => _resetCache(CacheResetException(sourceUrl));

  Future<void> _resetCache(final InvalidCacheException exception) {
    final downloader = _cacheDownloader;
    if (downloader != null && !downloader.isClosed) {
      //The download serves no more requests from the cache
      final cancelled = downloader.cancel(exception);
      if (downloader.isWriting) {
        return cancelled; //It ends on the exception, and resets the cache
      }
      //It stopped writing, and completes (refreshing the cache state on the
      //way, which may be what is resetting it): reset here, without waiting.
    }
    return _fileLock.synchronized(() async {
      try {
        _cachedResponseHeaders = null;
        _updateCacheState(const CacheState.zero());
        if (exception is! CacheResetException) {
          _addError(exception, closeRequests: false);
        }
        await files.delete(partialOnly: false);
      } catch (e) {
        _addError(e, closeRequests: false);
      } finally {
        if (_queuedRequests.isNotEmpty && !isDownloading && isRetained) {
          //Restart download to fulfill pending requests
          Timer.run(() => download()
              .ignore()); //Use Timer.run to avoid calling download() within the lock
        }
      }
    });
  }

  Future<void> _setCachedResponseHeaders(CachedResponseHeaders headers) {
    if (!config.saveAllHeaders) {
      headers = headers.essentialHeaders();
    }
    _cachedResponseHeaders = headers; //Set synchronously

    return _fileLock.synchronized(() async {
      try {
        await files.metadata.parent.create(recursive: true);
        await files.metadata.writeAsBytes(jsonEncodeToBytes(metadata.toJson()));
      } catch (e) {
        _addError(e, closeRequests: false);
      }
    });
  }

  /// Reads the cache state from the cache files, checked against the running download, if any, and emits it.
  ///
  /// Resets the cache when its files no longer hold what it recorded (see [InvalidCacheException]), and returns
  /// [CacheState.zero].
  Future<CacheState> refreshCacheState() async {
    try {
      final state = await _fileLock.synchronized(() async {
        try {
          return await _cacheFileState();
        } on InvalidCacheException catch (e) {
          //Cancelled before the lock is released: a refresh waiting for it
          //does not judge the download again (and reset its successor), and no
          //request is served from it.
          _activeDownloader?.cancel(e).ignore();
          rethrow;
        }
      });
      _updateCacheState(state);
      return state;
    } on InvalidCacheException catch (e) {
      await _resetCache(e);
      return const CacheState.zero();
    }
  }

  /// The cache state the cache files hold, checked against the running download, if any.
  ///
  /// Throws an [InvalidCacheSizeException] when the files no longer hold what the cache recorded: a complete
  /// cache file of the wrong size, a partial one longer than the source, or a partial one missing bytes the
  /// download saved to it.
  Future<CacheState> _cacheFileState() async {
    assert(_fileLock.locked,
        '_cacheFileState must be called within _fileLock.synchronized()');
    final downloader = _activeDownloader;
    final writer = downloader?.isWriting == true ? downloader : null;
    //Read before the file is: by then the file holds at least these bytes, while
    //bytes saved during the stat may be missing from its size.
    final savedBytes = downloader?.filePosition ?? 0;
    final sourceLength = _cachedResponseHeaders?.sourceLength;

    if (sourceLength != null) {
      final completeCacheStat = await files.complete.stat();
      if (completeCacheStat.type == FileSystemEntityType.file) {
        InvalidCacheSizeException.validate(
            sourceUrl, completeCacheStat.size, sourceLength);
        return CacheState.complete(completeCacheStat.size);
      }
    } else if (writer == null) {
      return const CacheState.zero(); //Nothing to resume without the length
    }

    final partialCacheStat = await files.partial.stat();
    final partialSize = partialCacheStat.type == FileSystemEntityType.file
        ? partialCacheStat.size
        : null;

    //Deleted or truncated while the download writes into it (by the device's
    //cache management, say), the partial cache file lost bytes the download
    //saved: no response can read them, and the download saves on into a file
    //that no longer holds them (a deleted one, or at the wrong offset).
    if (savedBytes > (partialSize ?? 0)) {
      throw InvalidCacheSizeException(sourceUrl, partialSize ?? -1, savedBytes);
    }

    if (partialSize != null && sourceLength != null) {
      InvalidCacheSizeException.validate(sourceUrl, partialSize, sourceLength,
          partial: true);

      //Renamed once the download stops writing to it
      if (partialSize == sourceLength && writer == null) {
        try {
          await files.partial.rename(files
              .complete.path); //Rename the partial cache to the complete cache
          return CacheState.complete(partialSize);
        } on FileSystemException catch (e) {
          final completeCacheStat = await files.complete.stat();
          if (completeCacheStat.type == FileSystemEntityType.file &&
              completeCacheStat.size == sourceLength) {
            return CacheState.complete(completeCacheStat
                .size); //Renamed by another process, treat as complete.
          }
          //Rename can fail if the file is open by a response stream on Windows.
          if (lastErrorOrNull is! FileSystemException) {
            _addError(e,
                closeRequests:
                    false); //Prevent spamming the error log with repeated rename failures
          }
        }
      }
    }

    if (writer != null) {
      //The download is ahead of the file by the bytes it has yet to save. A
      //partial cache file it did not resume holds none of its bytes until it
      //saves them.
      return CacheState.incomplete(
          writer.downloadPosition, sourceLength ?? writer.sourceLength,
          filePosition: writer.filePosition);
    }
    return CacheState.incomplete(partialSize ?? 0, sourceLength);
  }

  void _updateCacheState(final CacheState cacheState) {
    final previousState = _stateController.valueOrNull;

    if (!_stateController.isClosed) {
      _stateController.add(cacheState);
    }

    if (!cacheState.isComplete) return;

    if (_queuedRequests.isNotEmpty && headers != null) {
      _queuedRequests.processAndRemove((request) {
        request
            .complete(() => FileStreamResponse(request.range, files, headers!));
      });
    }

    ///Only the transition that created the complete cache file counts as completion.
    ///A first state of [CompleteCacheState] means the file already existed on disk, so nothing was completed here.
    if (previousState != null && !previousState.isComplete) {
      config.handleCacheCompletion(this, files.complete);
    }
  }

  void _addError(final Object error, {required final bool closeRequests}) {
    if (!_stateController.isClosed && isRetained) {
      _stateController.addError(error);
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

  /// Returns a stream of download progress 0-1, Returns 1.0 only if the cache file exists.
  /// See [cacheStateStream] for more detailed cache state updates.
  late final Stream<double?> progressStream =
      _stateController.stream.map((state) {
    final p = state.progress;
    if (p == null || p == 1.0) return p;
    return (p * 100).round() / 100.0;
  }).distinct();

  /// Returns a stream of [CacheState] updates for this [HttpCacheStream].
  Stream<CacheState> get cacheStateStream => _stateController.stream;

  /// If this [HttpCacheStream] has been disposed. A disposed stream cannot be used.
  bool get isDisposed => _disposeCompleter.isCompleted;

  /// If this [HttpCacheStream] is actively downloading data to cache file.
  bool get isDownloading => _downloadFuture.isRunning;

  /// Bytes currently available in the cache (downloaded or on disk).
  /// For an active download, this may be ahead of the current read position. For a completed cache, this will match [sourceLength].
  int get cachePosition =>
      _activeDownloader?.downloadPosition ?? cacheState.position;

  ///The download filling the cache, unless it was cancelled for an invalid cache.
  CacheDownloader? get _activeDownloader {
    final downloader = _cacheDownloader;
    return downloader == null || downloader.isInvalidated ? null : downloader;
  }

  /// If this [HttpCacheStream] is retained.
  ///
  /// A retained stream will not be disposed until the [dispose] method is
  /// called the same number of times as [retain] was called.
  bool get isRetained => _retainCounter.isRetained;

  /// The number of active holders of this stream. Starts at 1 when the stream is created.
  /// Incremented by [retain] and decremented by [release] or [dispose].
  int get retainCount => _retainCounter.count;

  /// The latest download progress 0-1.
  /// Returns null if the source length is unknown. Returns 1.0 only if the cache file exists.
  double? get progress => cacheState.progress;

  CacheState get cacheState =>
      _stateController.valueOrNull ?? const CacheState.zero();

  /// Returns the last emitted error, or null if error events haven't yet been emitted.
  Object? get lastErrorOrNull => _stateController.errorOrNull;

  /// The current [CacheMetadata] for this [HttpCacheStream].
  CacheMetadata get metadata =>
      CacheMetadata(files, sourceUrl, _cachedResponseHeaders);

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
    _disposeRequested = false; //A new holder resurrects the stream
    _retainCounter.retain();
    _lifeCycleTimer?.cancel();
    _lifeCycleTimer = null;
    _cacheDownloader?.resume();
  }

  /// Releases this [HttpCacheStream] instance.
  ///
  /// Once released, [StreamLifecycleConfig] is used to manage how long before the stream is paused and disposed. If the stream is retained again before being disposed, it will resume as normal.
  void release() {
    if (!isRetained) return;
    _retainCounter.release();
    _lifeCycleTimer?.cancel();

    if (!isRetained) {
      if (_disposeRequested) {
        _performDispose(); //Honor a pending dispose() instead of deferring to the lifecycle
        return;
      }

      final lifecycleConfig = config.lifecycleConfig;

      _lifeCycleTimer = Timer(lifecycleConfig.pauseAfter, () {
        final remainingAfterPause =
            lifecycleConfig.disposeAfter - lifecycleConfig.pauseAfter;
        if (remainingAfterPause <= Duration.zero) {
          _performDispose();
          return;
        }

        final downloader = _cacheDownloader;
        downloader?.pause();

        final cancelDelay = config.readTimeout;
        final remainingAfterCancel = remainingAfterPause - cancelDelay;

        _lifeCycleTimer = Timer(cancelDelay, () {
          downloader?.cancel().ignore();
          if (remainingAfterCancel > Duration.zero) {
            _lifeCycleTimer = Timer(remainingAfterCancel, _performDispose);
          } else {
            _performDispose();
          }
        });
      });
    }
  }

  /// Returns a future that completes when this [HttpCacheStream] is disposed.
  Future get future => _disposeCompleter.future;

  @override
  String toString() =>
      'HttpCacheStream{sourceUrl: $sourceUrl, cacheUrl: $_cacheUrl, cacheFile: $cacheFile}';
}
