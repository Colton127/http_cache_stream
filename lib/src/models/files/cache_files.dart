import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http_cache_stream/src/etc/extensions/file_extensions.dart';
import 'package:http_cache_stream/src/models/files/cache_file_type.dart';
import 'package:path/path.dart' as p;

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

  ///Creates a [CacheFiles] instance from the given [file]. The file can be a complete, partial, or metadata cache file.
  factory CacheFiles.fromFile(final File file) {
    final completeFile = CacheFileType.completeFile(file);
    return CacheFiles._(
      complete: completeFile,
      partial: CacheFileType.partialFile(completeFile),
      metadata: CacheFileType.metaDataFile(completeFile),
    );
  }

  factory CacheFiles.fromUrl(final Directory cacheDir, final Uri sourceUrl) {
    final completeFile = _defaultCacheFile(cacheDir, sourceUrl);
    return CacheFiles._(
      complete: completeFile,
      partial: CacheFileType.partialFile(completeFile),
      metadata: CacheFileType.metaDataFile(completeFile),
    );
  }

  @override
  String toString() =>
      'CacheFiles(complete: $complete, partial: $partial, metadata: $metadata)';
}

File _defaultCacheFile(Directory cacheDir, Uri sourceUrl) {
  final int maxPathLength = Platform.isWindows ? 260 : 1024;
  const int maxComponentLength = 255;
  try {
    final List<String> pathParts = [cacheDir.path];
    void addPart(String part) {
      if (part.isEmpty) return;
      String sanitized = part.replaceAll(RegExp(r'[^a-zA-Z0-9_\-.]'), '_');
      if (sanitized.length > maxComponentLength) {
        sanitized = sanitized.substring(0, maxComponentLength);
      }
      pathParts.add(sanitized);
    }

    addPart(sourceUrl.host);
    sourceUrl.pathSegments.forEach(addPart);

    if (pathParts.length == 1) {
      throw ('No valid path segments found in URL');
    }
    if (!pathParts.last.contains('.')) {
      pathParts.add('file.cache'); // Default file name if no extension is found
    }
    final outputFile = File(p.joinAll(pathParts));
    if (outputFile.path.length > maxPathLength) {
      throw ('Generated file path exceeds maximum length of $maxPathLength characters');
    }
    outputFile.parent.createSync(
      recursive: true,
    ); //Create parent directories if they don't exist. This also helps validate the path.
    return outputFile;
  } catch (e) {
    if (kDebugMode) print('Error generating default file path: $e');
  }
  //Fallback to a hash-based file name if the above fails
  return _cacheFileFromHash(cacheDir, sourceUrl);
}

File _cacheFileFromHash(Directory cacheDir, Uri url) {
  String fileName = sha1.convert(utf8.encode(url.toString())).toString();
  final pathExtension = p.extension(url.path);
  final validExtensionRegex = RegExp(r'^\.[a-zA-Z0-9]{1,20}$');
  if (validExtensionRegex.hasMatch(pathExtension)) {
    //Ensure the extension is valid (alphanumeric, 1-20 characters)
    fileName += pathExtension;
  }
  return File(p.join(cacheDir.path, fileName));
}
