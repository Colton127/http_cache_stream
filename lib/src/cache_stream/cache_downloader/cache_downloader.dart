import 'dart:async';
import 'dart:io';

import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:http_cache_stream/src/models/exceptions.dart';
import 'package:http_cache_stream/src/models/stream_requests/stream_request.dart';

import '../../etc/extensions/list_extensions.dart';
import 'cache_file_sink.dart';
import 'downloader.dart';

class CacheDownloader {
  final Downloader _downloader;
  final CacheFileSink _sink;
  final _streamController = StreamController<List<int>>.broadcast(sync: true);
  final _completer = Completer<void>();
  CacheDownloader._(this._cachedHeaders, this._downloader, this._sink);

  factory CacheDownloader.construct(
    final CacheMetadata cacheMetadata,
    final StreamCacheConfig cacheConfig,
  ) {
    final startPosition = _startPosition(cacheMetadata);
    final downloader = Downloader(
      cacheMetadata.sourceUrl,
      IntRange(startPosition),
      cacheConfig,
    );
    final sink = CacheFileSink(cacheMetadata.cacheFiles, startPosition);
    return CacheDownloader._(cacheMetadata.headers, downloader, sink);
  }

  Future<void> download({
    required final void Function(Object e) onError,
    required final void Function(CachedResponseHeaders headers) onHeaders,
    required final void Function(int position) onPosition,
    required final Future<void> Function() onComplete,
  }) {
    return _downloader
        .download(
          onError: (error) {
            onError(error);
            _streamController.addError(error); //Inform stream subscribers of the error. Subscribers may choose to handle the error.
          },
          onHeaders: (responseHeaders) {
            if (_downloader.downloadRange.start > 0) {
              final prevHeaders = _cachedHeaders;
              if (prevHeaders != null && !CachedResponseHeaders.validateCacheResponse(prevHeaders, responseHeaders)) {
                throw CacheSourceChangedException(sourceUrl);
              }
            }

            _cachedHeaders = responseHeaders;
            onHeaders(responseHeaders);
            onPosition(_downloader.position);
          },
          onData: (data) {
            assert(
              data.isNotEmpty,
              'CacheDownloader: onData: Data should not be empty',
            );
            _sink.add(data);
            _streamController.add(data);
            onPosition(_downloader.position);
          },
        )
        .catchError(onError, test: (e) => e is! InvalidCacheException)
        .then((_) async {
          await _sink.flush(); //Ensure all data is flushed
          await _sink.close(); //Close the sink to release file handles
          final partialCacheLength = (await _sink.partialCacheFile.stat()).size;
          final sourceLength = _cachedHeaders?.sourceLength ?? (_downloader.isDone ? _downloader.position : null);
          if (partialCacheLength == sourceLength) {
            await onComplete();
          } else if (partialCacheLength != dataStreamPosition) {
            throw InvalidCacheLengthException(
              sourceUrl,
              partialCacheLength,
              dataStreamPosition,
            );
          }
        })
        .whenComplete(
          () {
            if (!_completer.isCompleted) {
              _completer.complete();
            }
            if (!_sink.isClosed) {
              ///The sink is not closed on invalid cache exception, so we need to close it here
              _sink.close().ignore();
            }
            if (!_streamController.isClosed) {
              if (!_downloader.isDone && _streamController.hasListener) {
                _streamController.addError(DownloadStoppedException(sourceUrl));
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
    final cachedHeaders = _cachedHeaders;
    if (!isActive || cachedHeaders == null) return false;

    final bytesRemaining = request.start - dataStreamPosition;

    if (bytesRemaining.isNegative) {
      _processingRequests.add(request);
      _processRequests(cachedHeaders); //Process using saved cache and download stream
      return true;
    } else if (_downloader.streamConfig.minChunkSize >= bytesRemaining) {
      ///We can fulfill the request directly from the download stream without needing to combine with the cache file.
      ///if bytesRemaining > 0, the next data chunk from the stream will cover the request start position.
      request.complete(
        () => StreamResponse.fromStream(
          request.range,
          cachedHeaders,
          dataStream,
          dataStreamPosition,
          _downloader.streamConfig,
        ),
      );
      return true;
    } else {
      return false;
    }
  }

  ///Process requests that start before the current download position by combining partial cache file and the download stream.
  void _processRequests(CachedResponseHeaders cachedHeaders) async {
    if (_isProcessingRequests) return;
    _isProcessingRequests = true;
    try {
      _downloader.pauseEmission(flush: true); //Pause the emission of new data while processing requests
      await _sink.flush(); //Ensure all emitted data is flushed to disk.
      if (_downloader.isClosed) {
        throw DownloadStoppedException(sourceUrl);
      }
      assert(() {
        final partialCacheSize = _sink.partialCacheFile.statSync().size;
        if (partialCacheSize != dataStreamPosition) {
          throw StateError('CacheDownloader: processRequests: partialCacheFileSize ($partialCacheSize) != downloadPosition ($dataStreamPosition)');
        }
        return true;
      }());

      _processingRequests.processAndRemove((request) {
        request.complete(
          () => StreamResponse.fromFileAndStream(
            request.range,
            cachedHeaders,
            _sink.partialCacheFile,
            _streamController.stream, //The next data emitted from the stream must begin from the current flush position
            dataStreamPosition,
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
      _downloader.resumeEmission();
    }
  }

  bool _isProcessingRequests = false;
  final List<StreamRequest> _processingRequests = [];
  int? get sourceLength => _cachedHeaders?.sourceLength;
  Uri get sourceUrl => _downloader.sourceUrl;
  bool get isActive => _downloader.isActive;
  CachedResponseHeaders? _cachedHeaders;
  Stream<List<int>> get dataStream => _streamController.stream;
  int get dataStreamPosition => _downloader.position;
}

int _startPosition(final CacheMetadata cacheMetadata) {
  final partialCacheFile = cacheMetadata.cacheFiles.partial;

  if (cacheMetadata.headers?.canResumeDownload() == true) {
    final partialCacheStat = partialCacheFile.statSync();
    if (partialCacheStat.type == FileSystemEntityType.file && partialCacheStat.size >= 0) {
      return partialCacheStat.size; //Return the size of the partial cache.
    }
  }

  partialCacheFile.parent.createSync(recursive: true); //Create the parent directory if it doesn't exist.
  return 0; //The IOSink will manage the file creation.
}
