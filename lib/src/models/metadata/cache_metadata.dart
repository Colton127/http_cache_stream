import 'dart:convert';
import 'dart:io';

import 'package:http_cache_stream/src/models/files/cache_files.dart';
import 'package:http_cache_stream/src/models/metadata/cached_response_headers.dart';

/// Metadata for a cached file.
class CacheMetadata {
  /// The files associated with the cache.
  final CacheFiles cacheFiles;

  /// The source URL of the content.
  final Uri sourceUrl;

  /// The cached response headers, if any.
  final CachedResponseHeaders? headers;
  const CacheMetadata._(this.cacheFiles, this.sourceUrl, {this.headers});

  /// Constructs [CacheMetadata] from [CacheFiles] and sourceUrl.
  factory CacheMetadata.construct(final CacheFiles cacheFiles, final Uri sourceUrl) {
    return CacheMetadata._(
      cacheFiles,
      sourceUrl,
      headers: CachedResponseHeaders.fromCacheFiles(cacheFiles),
    );
  }

  ///Attempts to load the metadata file for the given [file]. Returns null if the metadata file does not exist.
  ///The [file] parameter accepts metadata, partial, or complete cache files. The metadata file is determined by the file extension.
  static CacheMetadata? load(final File file) {
    return fromCacheFiles(CacheFiles.fromFile(file));
  }

  static CacheMetadata? fromCacheFiles(final CacheFiles cacheFiles) {
    final metadataFile = cacheFiles.metadata;
    if (!metadataFile.existsSync()) return null;
    final metadataJson = jsonDecode(metadataFile.readAsStringSync()) as Map<String, dynamic>;
    final urlValue = metadataJson['Url'];
    final sourceUrl = urlValue == null ? null : Uri.tryParse(urlValue);
    if (sourceUrl == null) return null;
    return CacheMetadata._(
      cacheFiles,
      sourceUrl,
      headers: CachedResponseHeaders.fromJson(metadataJson['headers']),
    );
  }

  ///Returns the cache download progress as a percentage, rounded to 2 decimal places. Returns null if the source length is unknown. Returns 1.0 only if the cache file exists.
  ///The progress reported here may be inaccurate if a download is ongoing. Use [progress] on [HttpCacheStream] to get the most accurate progress.
  double? cacheProgress() {
    if (isComplete) return 1.0;
    final sourceLength = this.sourceLength;
    if (sourceLength == null) return null;

    final partialCacheSize = partialCacheFile.statSync().size;
    if (partialCacheSize <= 0) {
      return 0.0;
    } else if (partialCacheSize == sourceLength) {
      partialCacheFile.renameSync(cacheFile.path); //Rename the partial cache to the complete cache
      return 1.0;
    } else if (partialCacheSize > sourceLength) {
      partialCacheFile.deleteSync(); //Reset the cache if the partial cache is larger than the source
      return 0.0;
    } else {
      return ((partialCacheSize / sourceLength) * 100).floor() / 100; //Round to 2 decimal places
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

  CacheMetadata setHeaders(CachedResponseHeaders? headers) {
    return CacheMetadata._(
      cacheFiles, //immutable
      sourceUrl, //immutable
      headers: headers,
    );
  }

  @override
  String toString() => 'CacheFileMetadata('
      'Files: $cacheFiles, '
      'sourceUrl: $sourceUrl, '
      'sourceLength: $sourceLength';
}
