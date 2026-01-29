import 'dart:async';
import 'dart:io';

import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:http_cache_stream/src/cache_stream/cache_downloader/buffered_io_sink.dart';
import 'package:http_cache_stream/src/etc/extensions/list_extensions.dart';
import 'package:http_cache_stream/src/models/stream_requests/stream_request.dart';

import 'downloader.dart';

class CacheDownloader {
  final int startPosition;
  final CacheFiles _cacheFiles;
  final Downloader _downloader;
  final BufferedIOSink _sink;
  final _streamController = StreamController<List<int>>.broadcast(sync: true);
  final _completer = Completer<void>();
  CacheDownloader._(final CacheMetadata cacheMetadata, this.startPosition, this._downloader, this._sink)
      : _cacheFiles = cacheMetadata.cacheFiles,
        _cachedHeaders = cacheMetadata.headers;
  int _receivedBytes = 0; //Total bytes received from downloader
  int _pendingStreamBytes = 0; //Bytes received but not added to stream yet. These bytes will be added within the current event loop.

  factory CacheDownloader.construct(
    final CacheMetadata cacheMetadata,
    final StreamCacheConfig cacheConfig,
  ) {
    final partialCacheFile = cacheMetadata.partialCacheFile;
    int startPosition = 0;

    if (cacheMetadata.headers?.canResumeDownload() == true) {
      final partialCacheStat = partialCacheFile.statSync();
      if (partialCacheStat.type == FileSystemEntityType.file && partialCacheStat.size > 0) {
        startPosition = partialCacheStat.size;
      }
    }

    return CacheDownloader._(
      cacheMetadata,
      startPosition,
      Downloader(cacheMetadata.sourceUrl, cacheConfig),
      BufferedIOSink(partialCacheFile, startPosition),
    );
  }

  Future<void> download({
    required final void Function(Object e) onError,
    required final void Function(CachedResponseHeaders headers) onHeaders,
    required final void Function(int position) onPosition,
    required final Future<void> Function() onComplete,
  }) {
    final int maxBufferSize = _downloader.streamConfig.maxBufferSize;

    return _downloader
        .download(
      downloadRange: () => IntRange(downloadPosition),
      onError: (error) {
        onError(error);
        _streamController.addError(error);
      },
      onHeaders: (cacheHttpHeaders) {
        if (downloadPosition > 0) {
          final prevHeaders = _cachedHeaders;
          if (prevHeaders != null && !CachedResponseHeaders.validateCacheResponse(prevHeaders, cacheHttpHeaders)) {
            throw CacheSourceChangedException(sourceUrl);
          }
        }

        _cachedHeaders = cacheHttpHeaders;
        onHeaders(cacheHttpHeaders);
        onPosition(downloadPosition); //Emit current position to update progress and process queued requests
      },
      onData: (data) {
        assert(data.isNotEmpty);
        assert(!_isProcessingRequests);
        _receivedBytes += data.length;
        _sink.add(data);

        if (_sink.bufferSize > maxBufferSize) {
          _downloader.pause(); //Pause upstream if we are receiving more data than we can write
          _sink.flush().then((_) => _downloader.resume(), onError: cancel); //Resume upstream after flushing
        } else if (!_sink.isFlushing) {
          _sink.flush().catchError(cancel); //Flush to file asynchronously
        }

        _pendingStreamBytes = data.length;
        onPosition(downloadPosition); //Emit current position to update progress and synchronously process queued requests
        _streamController.add(data); //Add after processing queued requests. Requests may be fulfilled from the pendingStreamBytes.
        _pendingStreamBytes = 0;
      },
    )
        .catchError(onError, test: (e) {
      return e is! InvalidCacheException;
    }).then(
      (_) async {
        await _sink.close(flushBuffer: true); //Flushes all buffered data and closes the sink
        final partialCacheLength = (await _sink.file.stat()).size;
        final sourceLength = _cachedHeaders?.sourceLength ?? (_downloader.isDone ? downloadPosition : null);
        if (partialCacheLength == sourceLength) {
          await onComplete();
        } else if (partialCacheLength != downloadPosition) {
          throw InvalidCacheLengthException(
            sourceUrl,
            partialCacheLength,
            downloadPosition,
          );
        }
      },
    ).whenComplete(
      () {
        if (!_completer.isCompleted) {
          _completer.complete();
        }
        if (!_sink.isClosed) {
          ///The sink is not closed on invalid cache exception, so we need to close it here
          _sink.close(flushBuffer: false).ignore();
        }
        if (!_streamController.isClosed) {
          if (!_downloader.isDone) {
            _streamController.addError(CacheDownloadStoppedException(sourceUrl));
          }
          _streamController.close().ignore();
        }
      },
    );
  }

  /// Cancels the download and closes the stream. An error must be provided to indicate the reason for cancellation.
  Future<void> cancel(final Object error) {
    _downloader.close(error);
    return _completer.future;
  }

  bool processRequest(final StreamRequest request) {
    if (request.start > downloadPosition) {
      return false;
    }
    final cachedHeaders = _cachedHeaders;
    if (cachedHeaders == null) {
      return false; //Headers required to process request
    }

    final requestEnd = request.end ?? sourceLength;
    if (requestEnd != null && filePosition >= requestEnd) {
      ///We have enough buffered data in the file to fulfill the request
      request.complete(() => StreamResponse.fromFile(request.range, _cacheFiles, cachedHeaders));
      return true;
    }
    if (!_downloader.isActive) {
      return false; //Cannot fulfill request end if downloader is not active
    }
    if (request.start >= streamPosition) {
      ///We can fulfill the request from the stream alone
      request.complete(
        () => StreamResponse.fromStream(request.range, cachedHeaders, _streamController.stream, streamPosition, _downloader.streamConfig, _cacheFiles),
      );
      return true;
    } else if (filePosition == streamPosition) {
      ///File and stream are already aligned, we can fulfill the request by combining them
      request.complete(
        () => StreamResponse.fromFileAndStream(
          request.range,
          cachedHeaders,
          _cacheFiles,
          _streamController.stream,
          streamPosition,
          _downloader.streamConfig,
        ),
      );
      return true;
    } else {
      //Synchronize file and stream positions before fulfilling the request
      _processCombinedRequests(request, cachedHeaders);
      return true;
    }
  }

  ///Processes requests that start before the current download position by combining file and stream data
  void _processCombinedRequests(final StreamRequest request, final CachedResponseHeaders headers) async {
    _processingRequests.add(request);
    if (_isProcessingRequests) return;
    _isProcessingRequests = true;

    try {
      _downloader.pause(); //Pause download. The download stream must begin where the file ends.
      await _sink.flush(); //Ensure all data is written to the cache file

      if (_downloader.isClosed) {
        throw CacheDownloadStoppedException(sourceUrl);
      }
      _processingRequests.processAndRemove((request) {
        request.complete(
          () => StreamResponse.fromFileAndStream(
            request.range,
            headers,
            _cacheFiles,
            _streamController.stream,
            streamPosition,
            _downloader.streamConfig,
          ),
        );
      });
    } catch (e) {
      _processingRequests.processAndRemove((request) {
        request.completeError(e);
      });
    } finally {
      _isProcessingRequests = false;
      _downloader.resume();
    }
  }

  bool _isProcessingRequests = false;
  final List<StreamRequest> _processingRequests = [];
  int? get sourceLength => _cachedHeaders?.sourceLength;
  int get downloadPosition => startPosition + _receivedBytes;
  int get streamPosition => downloadPosition - _pendingStreamBytes;
  int get filePosition => startPosition + _sink.flushedBytes;
  Uri get sourceUrl => _downloader.sourceUrl;
  bool get isActive => _downloader.isActive;
  CachedResponseHeaders? _cachedHeaders;
}
