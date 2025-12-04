import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dto/project_dto.dart';
import '../../file_handler/file_handler.dart';
import 'project_state_persistence_strategy.dart';

// ... (FileOperationEvent and related providers are unchanged) ...
sealed class FileOperationEvent {
  const FileOperationEvent();
}


class FileCreateEvent extends FileOperationEvent {
  final ProjectDocumentFile createdFile;
  const FileCreateEvent({required this.createdFile});
}

class FileModifyEvent extends FileOperationEvent {
  final ProjectDocumentFile modifiedFile;
  const FileModifyEvent({required this.modifiedFile});
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


final projectRepositoryProvider = StateProvider<ProjectRepository?>(
  (ref) => null,
);


/// The primary public interface and concrete implementation for all data
/// operations related to an active project.
///
/// It acts as a facade, delegating all tasks to its injected dependencies,
/// providing a single, consistent interface for project data.
class ProjectRepository {
  /// The root URI of the project this repository manages.
  final String rootUri;

  /// Handles direct file system operations.
  final FileHandler fileHandler;

  /// Handles loading and saving of the project's session state DTO.
  final ProjectStatePersistenceStrategy persistenceStrategy;

  ProjectRepository({
    required this.rootUri,
    required this.fileHandler,
    required this.persistenceStrategy,
  });

  // --- Persistence Methods (Delegated) ---

  Future<ProjectDto> loadProjectDto() {
    return persistenceStrategy.load();
  }

  Future<void> saveProjectDto(ProjectDto projectDto) {
    return persistenceStrategy.save(projectDto);
  }

  // --- File Operation Methods (Delegated to FileHandler) ---

  Future<ProjectDocumentFile> createDocumentFile(
    String parentUri,
    String name, {
    bool isDirectory = false,
    String? initialContent,
    Uint8List? initialBytes,
    bool overwrite = false,
  }) {
    return fileHandler.createDocumentFile(
      parentUri,
      name,
      isDirectory: isDirectory,
      initialContent: initialContent,
      initialBytes: initialBytes,
      overwrite: overwrite,
    );
  }

  Future<void> deleteDocumentFile(ProjectDocumentFile file) {
    return fileHandler.deleteDocumentFile(file);
  }

  Future<ProjectDocumentFile> renameDocumentFile(
    ProjectDocumentFile file,
    String newName,
  ) {
    return fileHandler.renameDocumentFile(file, newName);
  }

  Future<ProjectDocumentFile> copyDocumentFile(
    ProjectDocumentFile source,
    String destinationParentUri,
  ) {
    return fileHandler.copyDocumentFile(source, destinationParentUri);
  }

  Future<ProjectDocumentFile> moveDocumentFile(
    ProjectDocumentFile source,
    String destinationParentUri,
  ) {
    return fileHandler.moveDocumentFile(source, destinationParentUri);
  }

  Future<ProjectDocumentFile?> getFileMetadata(String uri) {
    return fileHandler.getFileMetadata(uri);
  }

  Future<List<ProjectDocumentFile>> listDirectory(
    String uri, {
    bool includeHidden = false,
  }) {
    return fileHandler.listDirectory(uri, includeHidden: includeHidden);
  }

  Future<String> readFile(String uri) {
    return fileHandler.readFile(uri);
  }

  Future<Uint8List> readFileAsBytes(String uri) {
    return fileHandler.readFileAsBytes(uri);
  }

  Future<ProjectDocumentFile> writeFile(
    ProjectDocumentFile file,
    String content,
  ) {
    return fileHandler.writeFile(file, content);
  }

  Future<ProjectDocumentFile> writeFileAsBytes(
    ProjectDocumentFile file,
    Uint8List bytes,
  ) {
    return fileHandler.writeFileAsBytes(file, bytes);
  }
}
