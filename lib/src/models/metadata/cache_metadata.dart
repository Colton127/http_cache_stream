import 'dart:convert';
import 'dart:io';

import 'package:http_cache_stream/src/models/metadata/cache_files.dart';
import 'package:http_cache_stream/src/models/metadata/cached_response_headers.dart';

class CacheMetadata {
  final CacheFiles cacheFiles;
  final Uri sourceUrl;
  final CachedResponseHeaders? headers;
  const CacheMetadata._(this.cacheFiles, this.sourceUrl, {this.headers});

  ///Constructs [CacheMetadata] from [CacheFiles] and sourceUrl.
  factory CacheMetadata.construct(
      final CacheFiles cacheFiles, final Uri sourceUrl) {
    return CacheMetadata._(cacheFiles, sourceUrl,
        headers: CachedResponseHeaders.fromCacheFiles(cacheFiles));
  }

  ///Attempts to load the metadata file for the given [file]. Returns null if the metadata file does not exist.
  ///The [file] parameter accepts metadata, partial, or complete cache files. The metadata file is determined by the file extension.
  static CacheMetadata? load(final File file) {
    return fromCacheFiles(CacheFiles.fromFile(file));
  }

  static CacheMetadata? fromCacheFiles(final CacheFiles cacheFiles) {
    final metadataFile = cacheFiles.metadata;
    if (!metadataFile.existsSync()) return null;
    final metadataJson =
        jsonDecode(metadataFile.readAsStringSync()) as Map<String, dynamic>;
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
  ///If cache is incomplete and download cannot be resumed, resets the partial cache and returns 0.0.
  ///The progress reported here may be inaccurate if a download is ongoing. Use [progress] on [HttpCacheStream] to get the most accurate progress.
  ///On the other hand, if a download is not ongoing, this method is the most accurate way to get the progress.
  double? cacheProgress() {
    try {
      if (isComplete) {
        return 1.0;
      }
      final sourceLength = this.sourceLength;
      final hasSourceLength = sourceLength != null && sourceLength > 0;

      final partialCacheSize = partialCacheFile.statSync().size;
      if (partialCacheSize <= 0) {
        return hasSourceLength ? 0.0 : null;
      } else if (partialCacheSize == sourceLength) {
        partialCacheFile.renameSync(
          cacheFile.path,
        ); //Rename the partial cache to the complete cache
        return 1.0;
      } else if (!hasSourceLength ||
          partialCacheSize > sourceLength ||
          headers?.canResumeDownload() != true) {
        partialCacheFile
            .deleteSync(); //Reset the cache, since the download cannot be resumed
        return 0.0;
      } else {
        return ((partialCacheSize / sourceLength) * 100).floor() /
            100; //Round to 2 decimal places
      }
    } catch (e) {
      assert(false, 'CacheMetadata: cacheProgress: error $e');
      return null;
    }
  }

  ///Returns true if the cache is complete. Returns false if the cache is incomplete or does not exist.
  bool get isComplete => cacheFiles.complete.existsSync();

  Future<void> save() {
    return metaDataFile.writeAsString(jsonEncode(toJson()));
  }

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

  CacheMetadata copyWith({
    CacheFiles? cacheFiles,
    Uri? sourceUrl,
    CachedResponseHeaders? headers,
  }) {
    return CacheMetadata._(
      cacheFiles ?? this.cacheFiles,
      sourceUrl ?? this.sourceUrl,
      headers: headers ?? this.headers,
    );
  }

  @override
  String toString() => 'CacheFileMetadata('
      'Files: $cacheFiles, '
      'sourceUrl: $sourceUrl, '
      'sourceLength: $sourceLength';
}
