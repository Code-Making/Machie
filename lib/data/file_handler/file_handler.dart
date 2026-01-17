import 'dart:typed_data';

import 'package:flutter/foundation.dart';
//TODO: CHANGE LOCATION maybe ?
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
  Future<List<ProjectDocumentFile>> listDirectory(
    String uri, {
    bool includeHidden = false,
  });
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
// ... existing imports
import 'dart:typed_data'; // ensure this is present

// ... existing PermissionDeniedException and DocumentFile classes ...

/// The contract for handling file system operations.
abstract class FileHandler {
  // --- Existing Methods ---
  Future<List<ProjectDocumentFile>> listDirectory(
    String uri, {
    bool includeHidden = false,
  });
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

  // --- NEW: Path Math Methods ---

  /// Resolves a [relativePath] against a [basePath].
  /// Both paths should be project-relative "display paths" (e.g. "assets/images").
  /// Returns a normalized, canonical project-relative path.
  String resolveRelativePath(String basePath, String relativePath);

  /// Calculates the relative path from [basePath] to [targetPath].
  /// Used to generate the string stored in TMX files (e.g. "../tilesets/wall.tsx").
  String makePathRelative(String basePath, String targetPath);

  /// Returns the directory part of a project-relative path.
  String getDirectoryName(String path);
}
