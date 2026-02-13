import 'dart:io';

import 'package:http_cache_stream/src/etc/extensions/file_extensions.dart';
import 'package:http_cache_stream/src/models/cache_files/cache_file_type.dart';

class CacheFiles {
  ///The complete cache file. This file contains the fully downloaded content.
  final File complete;

  ///The partial cache file. This file contains the partially downloaded content.
  final File partial;

  ///The metadata file. This file contains the metadata for the cache, including headers and other information.
  final File metadata;
  const CacheFiles._({
    required this.complete,
    required this.partial,
    required this.metadata,
  });

  ///Creates a [CacheFiles] instance from the given [file]. The file can be a complete, partial, or metadata cache file.
  factory CacheFiles.fromFile(final File file) {
    final completeFile = CacheFileType.completeFile(file);
    return CacheFiles._(
      complete: completeFile,
      partial: CacheFileType.partialFile(completeFile),
      metadata: CacheFileType.metaDataFile(completeFile),
    );
  }

  List<String> get paths => [complete.path, partial.path, metadata.path];
  Directory get directory => complete.parent;

  ///Returns the active cache file. If the complete cache file exists, it is returned. Otherwise, the partial cache file is returned.
  ///Does not guarantee that the returned file exists.
  File activeCacheFile() => complete.existsSync() ? complete : partial;

  ///Returns the length, in bytes, of the active cache file, or null if neither cache file exists.
  int? cacheFileSize() =>
      complete.lengthSyncOrNull() ?? partial.lengthSyncOrNull();

  ///Deletes the cache file and metadata file. If [partialOnly] is true, only partially cached files will be deleted.
  ///Returns true if any files were deleted.
  Future<bool> delete({final bool partialOnly = false}) async {
    final cacheFiles = [complete, partial, metadata];
    if (partialOnly) {
      if (await complete.exists()) {
        return false;
      } else {
        cacheFiles.remove(complete);
      }
    }
    bool deleted = false;
    for (final file in cacheFiles) {
      if (await file.exists()) {
        deleted = true;
        await file.delete();
      }
    }
    return deleted;
  }

  @override
  String toString() =>
      'CacheFiles(complete: $complete, partial: $partial, metadata: $metadata)';
}
