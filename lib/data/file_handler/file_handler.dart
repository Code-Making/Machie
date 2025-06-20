import 'dart:typed_data';
import 'package:flutter/foundation.dart';

// Abstract interface for a file-like entity.
abstract class DocumentFile {
  String get uri;
  String get name;
  bool get isDirectory;
  int get size;
  DateTime get modifiedDate;
  String get mimeType;
}

// Abstract interface for file operations.
abstract class FileHandler {
  Future<DocumentFile?> pickDirectory();
  Future<List<DocumentFile>> listDirectory(
    String uri, {
    bool includeHidden = false,
  });
  Future<DocumentFile?> pickFile();
  Future<List<DocumentFile>> pickFiles();

  Future<String> readFile(String uri);
  Future<Uint8List> readFileAsBytes(String uri); // NEW METHOD

  Future<DocumentFile> writeFile(DocumentFile file, String content);
  Future<DocumentFile> writeFileAsBytes(
    DocumentFile file,
    Uint8List bytes,
  ); // NEW METHOD

  Future<DocumentFile> createDocumentFile(
    String parentUri,
    String name, {
    bool isDirectory = false,
    String? initialContent,
    Uint8List? initialBytes, // NEW
    bool overwrite = false,
  });

  Future<void> deleteDocumentFile(DocumentFile file);

  Future<DocumentFile?> renameDocumentFile(DocumentFile file, String newName);
  Future<DocumentFile?> copyDocumentFile(
    DocumentFile source,
    String destinationParentUri,
  );
  Future<DocumentFile?> moveDocumentFile(
    DocumentFile source,
    String destinationParentUri,
  );

  Future<DocumentFile?> getFileMetadata(String uri);
}