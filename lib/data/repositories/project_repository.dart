// lib/data/repositories/project_repository.dart
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../file_handler/file_handler.dart';
import '../project_models.dart';
import 'project_hierarchy_cache.dart';
import '../../logs/logs_provider.dart'; // NEW IMPORT

// REFACTOR: The hierarchy cache is now its own StateNotifierProvider.
// It watches the active repository and re-initializes when the project changes.
final projectHierarchyProvider = StateNotifierProvider.autoDispose<
    ProjectHierarchyCache, Map<String, List<DocumentFile>>>((ref) {
  final repo = ref.watch(projectRepositoryProvider);
  if (repo == null) {
    // Return an empty cache if no project is active.
    return ProjectHierarchyCache(null, ref.read(talkerProvider));
  }
  return ProjectHierarchyCache(repo.fileHandler, ref.read(talkerProvider));
});

final projectRepositoryProvider =
    StateProvider<ProjectRepository?>((ref) => null);

/// REFACTOR: The repository no longer owns the cache.
abstract class ProjectRepository {
  FileHandler get fileHandler;

  Future<Project> loadProject(ProjectMetadata metadata);
  Future<void> saveProject(Project project);

  // File operations now take a Ref to interact with the cache provider
  Future<DocumentFile> createDocumentFile(
    Ref ref,
    String parentUri,
    String name, {
    bool isDirectory = false,
    String? initialContent,
    Uint8List? initialBytes,
    bool overwrite = false,
  });

  Future<void> deleteDocumentFile(Ref ref, DocumentFile file);
  Future<DocumentFile?> renameDocumentFile(
      Ref ref, DocumentFile file, String newName);
  Future<DocumentFile?> copyDocumentFile(
      Ref ref, DocumentFile source, String destinationParentUri);
  Future<DocumentFile?> moveDocumentFile(
      Ref ref, DocumentFile source, String destinationParentUri);

  // These methods don't modify the hierarchy, so they don't need a Ref
  Future<List<DocumentFile>> listDirectory(
    String uri, {
    bool includeHidden = false,
  });
  Future<String> readFile(String uri);
  Future<Uint8List> readFileAsBytes(String uri);
  Future<DocumentFile> writeFile(DocumentFile file, String content);
  Future<DocumentFile> writeFileAsBytes(DocumentFile file, Uint8List bytes);
  Future<DocumentFile?> getFileMetadata(String uri);
}