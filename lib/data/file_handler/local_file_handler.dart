// FILE: lib/data/file_handler/local_file_handler.dart


import 'dart:io';

import 'file_handler.dart';

import 'local_file_handler_saf.dart'; // Android implementation

// Abstract class for local file handlers
abstract class LocalFileHandler implements FileHandler {}

class LocalFileHandlerFactory {
  /// Creates an instance of a platform-specific LocalFileHandler.
  static LocalFileHandler create(String rootUri) {
    if (Platform.isAndroid) {
      return SafFileHandler(rootUri);
    } else {
      throw UnsupportedError(
        'Local file handling is not supported on this platform.',
      );
    }
  }
}