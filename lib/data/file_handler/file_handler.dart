// =========================================
// UPDATED: lib/data/file_handler/file_handler.dart
// =========================================

import 'dart:typed_data';
import 'package:flutter/foundation.dart';

abstract class DocumentFile {
  String get uri;
  String get name;
  bool get isDirectory;
  int get size;
  DateTime get modifiedDate;
  String get mimeType;
}

abstract class FileHandler {
  Future<DocumentFile?> pickDirectory();
  Future<List<DocumentFile>> listDirectory(
    String uri, {
    bool includeHidden = false,
  });
  Future<DocumentFile?> pickFile();
  Future<List<DocumentFile>> pickFiles();

  Future<String> readFile(String uri);
  Future<Uint8List> readFileAsBytes(String uri);

  Future<DocumentFile> writeFile(DocumentFile file, String content);
  Future<DocumentFile> writeFileAsBytes(
    DocumentFile file,
    Uint8List bytes,
  );

  Future<DocumentFile> createDocumentFile(
    String parentUri,
    String name, {
    bool isDirectory = false,
    String? initialContent,
    Uint8List? initialBytes,
    bool overwrite = false,
  });

  Future<void> deleteDocumentFile(DocumentFile file);

  // REFACTORED: These methods are now non-nullable and will throw on failure.
  Future<DocumentFile> renameDocumentFile(DocumentFile file, String newName);
  Future<DocumentFile> copyDocumentFile(
    DocumentFile source,
    String destinationParentUri,
  );
  Future<DocumentFile> moveDocumentFile(
    DocumentFile source,
    String destinationParentUri,
  );

  // This remains nullable as "not found" is a valid state, not an exception.
  Future<DocumentFile?> getFileMetadata(String uri);
}