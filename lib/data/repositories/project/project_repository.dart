import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dto/project_dto.dart';
import '../../file_handler/file_handler.dart';

// ... (FileOperationEvent and related providers are unchanged) ...
sealed class FileOperationEvent {
  const FileOperationEvent();
}

class FileCreateEvent extends FileOperationEvent {
  final ProjectDocumentFile createdFile;
  const FileCreateEvent({required this.createdFile});
}

class FileRenameEvent extends FileOperationEvent {
  final ProjectDocumentFile oldFile;
  final ProjectDocumentFile newFile;
  const FileRenameEvent({required this.oldFile, required this.newFile});
}

class FileDeleteEvent extends FileOperationEvent {
  final ProjectDocumentFile deletedFile;
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

// REMOVED projectHierarchyProvider

final projectRepositoryProvider = StateProvider<ProjectRepository?>(
  (ref) => null,
);

// ... (ProjectRepository abstract class is unchanged) ...
abstract class ProjectRepository {
  FileHandler get fileHandler;
  Future<ProjectDto> loadProjectDto();
  Future<void> saveProjectDto(ProjectDto projectDto);
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

  Future<List<ProjectDocumentFile>> listDirectory(
    String uri, {
    bool includeHidden = false,
  });
  Future<String> readFile(String uri);
  Future<Uint8List> readFileAsBytes(String uri);
  Future<ProjectDocumentFile> writeFile(
    ProjectDocumentFile file,
    String content,
  );
  Future<ProjectDocumentFile> writeFileAsBytes(
    ProjectDocumentFile file,
    Uint8List bytes,
  );
  Future<ProjectDocumentFile?> getFileMetadata(String uri);
}
