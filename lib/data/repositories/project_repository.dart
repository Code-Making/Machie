// lib/data/repositories/project_repository.dart
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/file_handler/file_handler.dart';
import '../../project/project_models.dart';
import 'project_hierarchy_cache.dart'; // NEW IMPORT

// REFACTOR: This provider now exposes the entire cache notifier.
final projectHierarchyProvider =
    Provider.autoDispose<ProjectHierarchyCache?>((ref) {
  // Watching the notifier directly ensures that we get the instance
  // as soon as it's available and that our UI provider rebuilds.
  final repo = ref.watch(projectRepositoryProvider);
  return repo?.hierarchyCache;
});

// REFACTOR: The main repository provider is unchanged.
final projectRepositoryProvider =
    StateProvider<ProjectRepository?>((ref) => null);

/// REFACTOR: Defines the abstract interface for all data operations related to a project.
/// This is the single source of truth for loading/saving project state and accessing its files.
abstract class ProjectRepository {
  /// The underlying file handler for this repository (e.g., SAF or desktop IO).
  FileHandler get fileHandler;

  /// REFACTOR: The repository now owns and exposes its hierarchy cache.
  ProjectHierarchyCache get hierarchyCache;

  /// Loads the full project state (session, workspace, etc.) from its data source.
  Future<Project> loadProject(ProjectMetadata metadata);

  /// Saves the full project state to its data source.
  Future<void> saveProject(Project project);

  // --- File Operation Delegations ---
  // REFACTOR: These methods now also handle updating the hierarchy cache.
  // Their signatures change to return the created/modified DocumentFile for this purpose.

  Future<List<DocumentFile>> listDirectory(
    String uri, {
    bool includeHidden = false,
  });

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