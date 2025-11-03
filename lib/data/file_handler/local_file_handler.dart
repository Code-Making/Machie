// lib/project/file_handler/local_file_handler.dart

// Dart imports:
import 'dart:io';

// Project imports:
import 'file_handler.dart';

import 'local_file_handler_saf.dart'; // Android implementation

// Abstract class for local file handlers
abstract class LocalFileHandler implements FileHandler {}

// Factory constructor that returns the correct platform-specific implementation.
class LocalFileHandlerFactory {
  static LocalFileHandler create() {
    if (Platform.isAndroid) {
      return SafFileHandler();
    }
    // else if (Platform.isWindows || ...) {
    //   return IOFileHandler(); // Future desktop implementation
    // }
    else {
      throw UnsupportedError(
        'Local file handling is not supported on this platform.',
      );
    }
  }
}
