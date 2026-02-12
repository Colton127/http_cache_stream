import 'dart:io';

enum CacheFileType {
  metadata('.metadata'),
  partial('.part'),
  complete;

  final String extension;
  const CacheFileType([this.extension = '']);

  static CacheFileType parse(File file) {
    if (isMetadata(file)) {
      return metadata;
    } else if (isPartial(file)) {
      return partial;
    } else {
      return complete;
    }
  }

  static File construct(File cacheFile, CacheFileType type) {
    return File('${cacheFile.path}${type.extension}');
  }

  static bool isMetadata(File file) =>
      file.path.endsWith(CacheFileType.metadata.extension);
  static bool isPartial(File file) =>
      file.path.endsWith(CacheFileType.partial.extension);
  static bool isComplete(File file) => parse(file) == CacheFileType.complete;

  static File metaDataFile(File cacheFile) =>
      construct(cacheFile, CacheFileType.metadata);
  static File partialFile(File cacheFile) =>
      construct(cacheFile, CacheFileType.partial);
  static File completeFile(File file) {
    final inputType = parse(file);
    if (inputType == CacheFileType.complete) return file;
    return File(file.path.replaceFirst(inputType.extension, ''));
  }
}
