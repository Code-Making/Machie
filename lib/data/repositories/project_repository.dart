// lib/data/repositories/project_repository.dart
import 'dart:async'; // NEW IMPORT
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/file_handler/file_handler.dart';
import '../../project/project_models.dart';
import 'project_hierarchy_cache.dart';
import '../../logs/logs_provider.dart';

// --- NEW: File Operation Event Stream ---

sealed class FileOperationEvent {
  const FileOperationEvent();
}

class FileCreateEvent extends FileOperationEvent {
  final DocumentFile createdFile;
  const FileCreateEvent({required this.createdFile});
}

class FileRenameEvent extends FileOperationEvent {
  final DocumentFile oldFile;
  final DocumentFile newFile;
  const FileRenameEvent({required this.oldFile, required this.newFile});
}

class FileDeleteEvent extends FileOperationEvent {
  final DocumentFile deletedFile;
  const FileDeleteEvent({required this.deletedFile});
}

// FIX: Create a provider for the StreamController itself. We use .broadcast()
// to allow multiple listeners if needed in the future.
final fileOperationControllerProvider =
    Provider<StreamController<FileOperationEvent>>((ref) {
  final controller = StreamController<FileOperationEvent>.broadcast();
  ref.onDispose(() => controller.close());
  return controller;
});

// FIX: The StreamProvider now simply listens to the controller's stream.
final fileOperationStreamProvider =
    StreamProvider.autoDispose<FileOperationEvent>((ref) {
  return ref.watch(fileOperationControllerProvider).stream;
});

// --- End of New Section ---

final projectHierarchyProvider = StateNotifierProvider.autoDispose<
    ProjectHierarchyCache, Map<String, List<DocumentFile>>>((ref) {
  // ... implementation unchanged
  final repo = ref.watch(projectRepositoryProvider);
  if (repo == null) {
    return ProjectHierarchyCache(null, ref.read(talkerProvider));
  }
  return ProjectHierarchyCache(repo.fileHandler, ref.read(talkerProvider));
});

final projectRepositoryProvider =
    StateProvider<ProjectRepository?>((ref) => null);

// ... ProjectRepository abstract class is unchanged ...
abstract class ProjectRepository {
  FileHandler get fileHandler;
  Future<Project> loadProject(ProjectMetadata metadata);
  Future<void> saveProject(Project project);
  Future<DocumentFile> createDocumentFile(Ref ref, String parentUri, String name, {bool isDirectory = false, String? initialContent, Uint8List? initialBytes, bool overwrite = false});
  Future<void> deleteDocumentFile(Ref ref, DocumentFile file);
  Future<DocumentFile?> renameDocumentFile(Ref ref, DocumentFile file, String newName);
  Future<DocumentFile?> copyDocumentFile(Ref ref, DocumentFile source, String destinationParentUri);
  Future<DocumentFile?> moveDocumentFile(Ref ref, DocumentFile source, String destinationParentUri);
  Future<List<DocumentFile>> listDirectory(String uri, {bool includeHidden = false});
  Future<String> readFile(String uri);
  Future<Uint8List> readFileAsBytes(String uri);
  Future<DocumentFile> writeFile(DocumentFile file, String content);
  Future<DocumentFile> writeFileAsBytes(DocumentFile file, Uint8List bytes);
  Future<DocumentFile?> getFileMetadata(String uri);
}