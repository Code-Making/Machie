// lib/data/repositories/project_repository.dart
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/file_handler/file_handler.dart';
import '../../project/project_models.dart';

// REFACTOR: This provider will hold the repository instance for the currently active project.
// It is managed by the AppNotifier.
final projectRepositoryProvider =
    StateProvider<ProjectRepository?>((ref) => null);

/// REFACTOR: Defines the abstract interface for all data operations related to a project.
/// This is the single source of truth for loading/saving project state and accessing its files.
abstract class ProjectRepository {
  /// The underlying file handler for this repository (e.g., SAF or desktop IO).
  FileHandler get fileHandler;

  /// Loads the full project state (session, workspace, etc.) from its data source.
  Future<Project> loadProject(ProjectMetadata metadata);

  /// Saves the full project state to its data source.
  Future<void> saveProject(Project project);

  // --- File Operation Delegations ---
  // These methods provide a consistent API for services to interact with files,
  // delegating the actual work to the underlying FileHandler.

  Future<List<DocumentFile>> listDirectory(
    String uri, {
    bool includeHidden = false,
  }) =>
      fileHandler.listDirectory(uri, includeHidden: includeHidden);

  Future<String> readFile(String uri) => fileHandler.readFile(uri);

  Future<Uint8List> readFileAsBytes(String uri) =>
      fileHandler.readFileAsBytes(uri);

  Future<DocumentFile> writeFile(DocumentFile file, String content) =>
      fileHandler.writeFile(file, content);

  Future<DocumentFile> writeFileAsBytes(DocumentFile file, Uint8List bytes) =>
      fileHandler.writeFileAsBytes(file, bytes);

  Future<DocumentFile> createDocumentFile(
    String parentUri,
    String name, {
    bool isDirectory = false,
    String? initialContent,
    Uint8List? initialBytes,
    bool overwrite = false,
  }) =>
      fileHandler.createDocumentFile(
        parentUri,
        name,
        isDirectory: isDirectory,
        initialContent: initialContent,
        initialBytes: initialBytes,
        overwrite: overwrite,
      );

  Future<void> deleteDocumentFile(DocumentFile file) =>
      fileHandler.deleteDocumentFile(file);

  Future<DocumentFile?> renameDocumentFile(DocumentFile file, String newName) =>
      fileHandler.renameDocumentFile(file, newName);

  Future<DocumentFile?> copyDocumentFile(
    DocumentFile source,
    String destinationParentUri,
  ) =>
      fileHandler.copyDocumentFile(source, destinationParentUri);

  Future<DocumentFile?> moveDocumentFile(
    DocumentFile source,
    String destinationParentUri,
  ) =>
      fileHandler.moveDocumentFile(source, destinationParentUri);

  Future<DocumentFile?> getFileMetadata(String uri) =>
      fileHandler.getFileMetadata(uri);
}