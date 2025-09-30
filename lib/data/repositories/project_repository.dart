// =========================================
// UPDATED: lib/data/repositories/project_repository.dart
// =========================================

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/file_handler/file_handler.dart';
import 'project_hierarchy_cache.dart';
import '../../logs/logs_provider.dart';
import '../../data/dto/project_dto.dart';

// ... (FileOperationEvent and providers are unchanged) ...
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

final fileOperationControllerProvider =
    Provider<StreamController<FileOperationEvent>>((ref) {
      final controller = StreamController<FileOperationEvent>.broadcast();
      ref.onDispose(() => controller.close());
      return controller;
    });

final fileOperationStreamProvider =
    StreamProvider.autoDispose<FileOperationEvent>((ref) {
      return ref.watch(fileOperationControllerProvider).stream;
    });

final projectHierarchyProvider = StateNotifierProvider.autoDispose<
  ProjectHierarchyCache,
  Map<String, List<DocumentFile>>
>((ref) {
  final repo = ref.watch(projectRepositoryProvider);
  if (repo == null) {
    return ProjectHierarchyCache(null, ref.read(talkerProvider));
  }
  return ProjectHierarchyCache(repo.fileHandler, ref.read(talkerProvider));
});

final projectRepositoryProvider = StateProvider<ProjectRepository?>(
  (ref) => null,
);

abstract class ProjectRepository {
  FileHandler get fileHandler;
  Future<ProjectDto> loadProjectDto();
  Future<void> saveProjectDto(ProjectDto projectDto);
  Future<DocumentFile> createDocumentFile(
    String parentUri,
    String name, {
    bool isDirectory = false,
    String? initialContent,
    Uint8List? initialBytes,
    bool overwrite = false,
  });
  Future<void> deleteDocumentFile(DocumentFile file);
  
  // REFACTORED: These methods are now non-nullable.
  Future<DocumentFile> renameDocumentFile(
    DocumentFile file,
    String newName,
  );
  Future<DocumentFile> copyDocumentFile(
    DocumentFile source,
    String destinationParentUri,
  );
  Future<DocumentFile> moveDocumentFile(
    DocumentFile source,
    String destinationParentUri,
  );

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