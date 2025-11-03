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

/// The base abstract class for any file-like entity in the application.
abstract class DocumentFile {
  String get uri;
  String get name;
  bool get isDirectory;
  int get size;
  DateTime get modifiedDate;
  String get mimeType;
}

/// A specialized [DocumentFile] that represents a file or directory physically
/// present within the project's structure and managed by the [ProjectRepository].
abstract class ProjectDocumentFile extends DocumentFile {}

/// The contract for handling file system operations.
/// It now explicitly produces and consumes [ProjectDocumentFile] instances.
abstract class FileHandler {
  Future<bool> hasPermission(String uri);
  Future<bool> reRequestPermission(String uri);
  Future<ProjectDocumentFile?> pickDirectory();
  Future<List<ProjectDocumentFile>> listDirectory(
    String uri, {
    bool includeHidden = false,
  });
  Future<ProjectDocumentFile?> pickFile();
  Future<List<ProjectDocumentFile>> pickFiles();

  Future<String> readFile(String uri);
  Future<Uint8List> readFileAsBytes(String uri);
  Future<Uint8List> readFileAsBytesRange(String uri, int start, int end);

  Future<ProjectDocumentFile> writeFile(
    ProjectDocumentFile file,
    String content,
  );
  Future<ProjectDocumentFile> writeFileAsBytes(
    ProjectDocumentFile file,
    Uint8List bytes,
  );

  Future<ProjectDocumentFile> createDocumentFile(
    String parentUri,
    String name, {
    bool isDirectory = false,
    String? initialContent,
    Uint8List? initialBytes,
    bool overwrite = false,
  });

  Future<void> deleteDocumentFile(ProjectDocumentFile file);

  Future<ProjectDocumentFile> renameDocumentFile(
    ProjectDocumentFile file,
    String newName,
  );
  Future<ProjectDocumentFile> copyDocumentFile(
    ProjectDocumentFile source,
    String destinationParentUri,
  );
  Future<ProjectDocumentFile> moveDocumentFile(
    ProjectDocumentFile source,
    String destinationParentUri,
  );

  Future<ProjectDocumentFile?> getFileMetadata(String uri);

  Future<ProjectDocumentFile?> resolvePath(
    String parentUri,
    String relativePath,
  );

  Future<({ProjectDocumentFile file, List<ProjectDocumentFile> createdDirs})>
  createDirectoryAndFile(
    String parentUri,
    String relativePath, {
    String? initialContent,
  });

  String getParentUri(String uri);
  String getFileName(String uri);
  String getPathForDisplay(String uri, {String? relativeTo});
}
