import 'dart:async';
import 'dart:io';

import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:http_cache_stream/src/etc/exceptions.dart';
import 'package:http_cache_stream/src/models/stream_response/stream_request.dart';

import 'cache_file_sink.dart';
import 'downloader.dart';

class CacheDownloader {
  final CacheMetadata _initMetadata;
  final Downloader _downloader;
  final CacheFileSink _sink;
  final _streamController = StreamController<List<int>>.broadcast(sync: true);
  final _completer = Completer<void>();
  CacheDownloader._(this._initMetadata, this._downloader, this._sink)
      : _sourceLength = _initMetadata.sourceLength;

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
    final sink = CacheFileSink(
      cacheMetadata.partialCacheFile,
      startPosition,
    );
    return CacheDownloader._(cacheMetadata, downloader, sink);
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
            ///TODO: Decide if non-fatal errors should be added to [streamController] to inform subscribers
            assert(
              error is! InvalidCacheException,
              'InvalidCacheException should be handled in the future',
            );
            onError(error);
          },
          onHeaders: (cacheHttpHeaders) {
            if (_downloader.downloadRange.start > 0 &&
                _initMetadata.headers?.validate(cacheHttpHeaders) == false) {
              throw CacheSourceChangedException(sourceUrl);
            }
            _sourceLength = cacheHttpHeaders.sourceLength;
            _acceptRangeRequests =
                _sourceLength != null && cacheHttpHeaders.acceptsRangeRequests;
            onHeaders(cacheHttpHeaders);
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

          final partialCacheLength = _sink.partialCacheFile.statSync().size;
          final sourceLength = _sourceLength ??=
              (_downloader.isDone ? _downloader.position : null);
          if (partialCacheLength == sourceLength) {
            await onComplete();
          } else if (partialCacheLength != downloadPosition) {
            throw InvalidCacheLengthException(
              sourceUrl,
              partialCacheLength,
              downloadPosition,
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
            if (!_downloader.isDone && _streamController.hasListener) {
              _streamController.addError(DownloadStoppedException(sourceUrl));
            }
            _streamController.close().ignore();
          },
        );
  }

  /// Cancels the download and closes the stream. An error must be provided to indicate the reason for cancellation.
  Future<void> cancel(final Object error) {
    _downloader.close(error);
    return _completer.future;
  }

  void processRequest(final StreamRequest request) async {
    _processingRequests.add(request);
    if (_isProcessingRequests) return;
    _isProcessingRequests = true;

    try {
      _downloader.pauseEmission(
          flush:
              true); //Pause the emission of new data while processing requests.
      await _sink.flush(); //Ensure all buffered data is flushed to disk.

      if (_downloader.isClosed) {
        throw DownloadStoppedException(sourceUrl);
      }
      assert(partialCacheFile.statSync().size == downloadPosition,
          'CacheDownloader: processRequests: partialCacheFileSize (${partialCacheFile.statSync().size}) != downloadPosition ($downloadPosition)');

      _processingRequests.removeWhere((request) {
        if (!request.isComplete) {
          final response = StreamResponse.fromCacheStream(
            request.range,
            partialCacheFile,
            _streamController
                .stream, //The next data emitted from the stream must begin from the current flush position
            downloadPosition,
            _sourceLength,
          );
          request.complete(response);
        }
        return true;
      });
    } catch (e, st) {
      _processingRequests.removeWhere((request) {
        request.completeError(e, st);
        return true;
      });
    } finally {
      _isProcessingRequests = false;
      _downloader.resumeEmission();
    }
  }

  bool _isProcessingRequests = false;
  final List<StreamRequest> _processingRequests = [];
  bool? _acceptRangeRequests;
  int? _sourceLength;
  int get downloadPosition => _downloader.position;
  int? get sourceLength => _sourceLength;
  Uri get sourceUrl => _downloader.sourceUrl;
  bool get isActive => _downloader.isActive;
  File get partialCacheFile => _sink.partialCacheFile;
  bool get acceptRangeRequests => _acceptRangeRequests == true;
}

int _startPosition(final CacheMetadata cacheMetadata) {
  final partialCacheFile = cacheMetadata.cacheFiles.partial;

  if (cacheMetadata.headers?.canResumeDownload() == true) {
    final partialCacheStat = partialCacheFile.statSync();
    if (partialCacheStat.type == FileSystemEntityType.file &&
        partialCacheStat.size >= 0) {
      return partialCacheStat.size; //Return the size of the partial cache.
    }
  }

  partialCacheFile.parent.createSync(
      recursive: true); //Create the parent directory if it doesn't exist.
  return 0; //The IOSink will manage the file creation.
}
