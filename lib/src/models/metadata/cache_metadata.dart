import 'dart:io';

import 'package:http_cache_stream/src/etc/extensions/file_extensions.dart';
import 'package:http_cache_stream/src/models/cache_files/cache_files.dart';
import 'package:http_cache_stream/src/models/metadata/cached_response_headers.dart';

import '../../etc/helpers.dart';
import '../cache_state/cache_state.dart';
import '../exceptions/invalid_cache_exceptions.dart';

/// Metadata for a cached file.
class CacheMetadata {
  /// The files associated with the cache.
  final CacheFiles cacheFiles;

  /// The source URL of the content.
  final Uri sourceUrl;

  /// The cached response headers, if any.
  final CachedResponseHeaders? headers;
  const CacheMetadata(this.cacheFiles, this.sourceUrl, this.headers);

  ///Attempts to load the metadata file for the given [file]. Returns null if the metadata file does not exist.
  ///The [file] parameter accepts metadata, partial, or complete cache files. The metadata file is determined by the file extension.
  static CacheMetadata? load(final File file) {
    return fromCacheFiles(CacheFiles.fromFile(file));
  }

  static CacheMetadata? fromCacheFiles(final CacheFiles cacheFiles) {
    final metadataFile = cacheFiles.metadata;
    if (!metadataFile.existsSync()) return null;
    final metadataJson =
        jsonDecodeBytes(metadataFile.readAsBytesSync()) as Map<String, dynamic>;
    return CacheMetadata(
      cacheFiles,
      Uri.parse(metadataJson['Url']),
      CachedResponseHeaders.fromJson(metadataJson['headers']),
    );
  }

  Future<CacheState> cacheState() async {
    final sourceLength = this.sourceLength;
    if (sourceLength == null) return const CacheState.zero();

    final completeCacheSize = await cacheFile.lengthOrNull();
    if (completeCacheSize != null) {
      InvalidCacheSizeException.validate(
          sourceUrl, completeCacheSize, sourceLength);
      return CacheState.complete(completeCacheSize);
    }

    final partialCacheSize = await partialCacheFile.lengthOrNull();
    if (partialCacheSize == null || partialCacheSize <= 0) {
      return const CacheState.zero();
    } else if (partialCacheSize == sourceLength) {
      await partialCacheFile.rename(
          cacheFile.path); //Rename the partial cache to the complete cache
      return CacheState.complete(partialCacheSize);
    } else if (partialCacheSize > sourceLength) {
      throw InvalidCacheSizeException(
          sourceUrl, partialCacheSize, sourceLength);
    } else {
      return CacheState.incomplete(partialCacheSize, sourceLength);
    }
  }

  ///Returns true if the cache is complete. Returns false if the cache is incomplete or does not exist.
  bool get isComplete => headers != null && cacheFile.existsSync();

  int? get sourceLength => headers?.sourceLength;
  File get metaDataFile => cacheFiles.metadata;
  File get partialCacheFile => cacheFiles.partial;
  File get cacheFile => cacheFiles.complete;

  Map<String, dynamic> toJson() {
    return {
      'Url': sourceUrl.toString(),
      if (headers != null) 'headers': headers!.toJson(),
    };
  }

  @override
  String toString() => 'CacheFileMetadata('
      'Files: $cacheFiles, '
      'sourceUrl: $sourceUrl, '
      'sourceLength: $sourceLength';
}
