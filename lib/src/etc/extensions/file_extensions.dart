import 'dart:io';

extension FileExtensions on File {
  ///Returns the length of the file, or null if the file does not exist.
  int? lengthSyncOrNull() {
    try {
      return lengthSync();
    } on FileSystemException {
      return null;
    }
  }

  ///Returns the length of the file, or null if the file does not exist.
  Future<int?> lengthOrNull() async {
    try {
      return await length();
    } on FileSystemException {
      return null;
    }
  }
}
