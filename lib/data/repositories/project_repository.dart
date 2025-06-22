// lib/data/repositories/project_repository.dart
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/file_handler/file_handler.dart';
import '../../project/project_models.dart'; // FIX: Corrected import path
import 'project_hierarchy_cache.dart';
import '../../logs/logs_provider.dart';

final projectHierarchyProvider = StateNotifierProvider.autoDispose<
    ProjectHierarchyCache, Map<String, List<DocumentFile>>>((ref) {
  final repo = ref.watch(projectRepositoryProvider);
  if (repo == null) {
    return ProjectHierarchyCache(null, ref.read(talkerProvider));
  }
  return ProjectHierarchyCache(repo.fileHandler, ref.read(talkerProvider));
});

final projectRepositoryProvider =
    StateProvider<ProjectRepository?>((ref) => null);

abstract class ProjectRepository {
  FileHandler get fileHandler;

  Future<Project> loadProject(ProjectMetadata metadata);
  Future<void> saveProject(Project project);

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