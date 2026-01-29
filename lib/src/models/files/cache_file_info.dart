import 'dart:io';

import '../../../http_cache_stream.dart';
import 'cache_file_type.dart';

class CacheFileInfo {
  final File file;
  final CacheFileType type;
  final FileStat? _stat;
  const CacheFileInfo._(this.file, this.type, this._stat);

  bool get exists => _stat != null;
  int? get lengthOrNull => _stat?.size;
  DateTime? get modified => _stat?.modified;

  factory CacheFileInfo.active(final CacheFiles cacheFiles) {
    final completeInfo = CacheFileInfo.construct(cacheFiles, CacheFileType.complete);
    return completeInfo.exists ? completeInfo : CacheFileInfo.construct(cacheFiles, CacheFileType.partial);
  }

  factory CacheFileInfo.construct(final CacheFiles cacheFiles, final CacheFileType type) {
    final file = switch (type) {
      CacheFileType.metadata => cacheFiles.metadata,
      CacheFileType.partial => cacheFiles.partial,
      CacheFileType.complete => cacheFiles.complete,
    };
    FileStat? stat = file.statSync();
    if (stat.type == FileSystemEntityType.notFound) {
      stat = null;
    }
    return CacheFileInfo._(file, type, stat);
  }
}
