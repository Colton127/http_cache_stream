import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

typedef CacheFileResolver = File Function(
    Directory cacheDirectory, Uri sourceUrl);

///Default cache file resolver. Generates a file path based on the URL structure, with sanitization to ensure valid file names and paths. If the generated path exceeds platform limits, it falls back to a hash-based file name.
File defaultCacheFileResolver(Directory cacheDirectory, Uri sourceUrl) {
  final int maxPathLength = Platform.isWindows ? 260 : 1024;
  const int maxComponentLength = 255;
  try {
    final List<String> pathParts = [cacheDirectory.path];
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
    return outputFile;
  } catch (e) {
    if (kDebugMode) print('Error generating default file path: $e');
  }
  //Fallback to a hash-based file name if the above fails
  return hashCacheFileResolver(cacheDirectory, sourceUrl);
}

File hashCacheFileResolver(Directory cacheDirectory, Uri url) {
  String fileName = sha1.convert(utf8.encode(url.toString())).toString();
  final pathExtension = p.extension(url.path);
  final validExtensionRegex = RegExp(r'^\.[a-zA-Z0-9]{1,20}$');
  if (validExtensionRegex.hasMatch(pathExtension)) {
    //Ensure the extension is valid (alphanumeric, 1-20 characters)
    fileName += pathExtension;
  }
  return File(p.join(cacheDirectory.path, fileName));
}
