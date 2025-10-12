// =========================================
// UPDATED: lib/data/file_handler/file_handler.dart
// =========================================

import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class PermissionDeniedException implements Exception {
  /// The URI for which permission was denied.
  final String uri;
  final String message;

  PermissionDeniedException({required this.uri, String? message})
      : message = message ?? 'Permission denied for URI: $uri';

  @override
  String toString() => message;
}

abstract class DocumentFile {
  String get uri;
  String get name;
  bool get isDirectory;
  int get size;
  DateTime get modifiedDate;
  String get mimeType;
}

abstract class FileHandler {
  Future<bool> reRequestPermission(String uri);
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
  Future<DocumentFile> writeFileAsBytes(DocumentFile file, Uint8List bytes);

  Future<DocumentFile> createDocumentFile(
    String parentUri,
    String name, {
    bool isDirectory = false,
    String? initialContent,
    Uint8List? initialBytes,
    bool overwrite = false,
  });

  Future<void> deleteDocumentFile(DocumentFile file);

  Future<DocumentFile> renameDocumentFile(DocumentFile file, String newName);
  Future<DocumentFile> copyDocumentFile(
    DocumentFile source,
    String destinationParentUri,
  );
  Future<DocumentFile> moveDocumentFile(
    DocumentFile source,
    String destinationParentUri,
  );

  Future<DocumentFile?> getFileMetadata(String uri);

  /// Returns the parent URI of the given URI.
  String getParentUri(String uri);

  /// Returns the final component (file or folder name) of the given URI.
  String getFileName(String uri);

  /// Returns a user-friendly, decoded path string for display purposes.
  /// If `relativeTo` is provided, it returns a relative path.
  String getPathForDisplay(String uri, {String? relativeTo});
}
