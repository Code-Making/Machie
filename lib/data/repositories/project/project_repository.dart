import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dto/project_dto.dart';
import '../../file_handler/file_handler.dart';
import 'project_state_persistence_strategy.dart';

sealed class FileOperationEvent {
  const FileOperationEvent();
}

class FileCreateEvent extends FileOperationEvent {
  final ProjectDocumentFile createdFile;
  const FileCreateEvent({required this.createdFile});
}
//TODO: implement in code
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

  // The event controller for broadcasting file system events.
  final StreamController<FileOperationEvent> _eventController;

  /// Handles loading and saving of the project's session state DTO.
  final ProjectStatePersistenceStrategy persistenceStrategy;

  ProjectRepository({
    required this.rootUri,
    required this.fileHandler,
    required this.persistenceStrategy,
    required StreamController<FileOperationEvent> eventController,
  }) : _eventController = eventController;

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
  }) async {
    final file = await fileHandler.createDocumentFile(
      parentUri,
      name,
      isDirectory: isDirectory,
      initialContent: initialContent,
      initialBytes: initialBytes,
      overwrite: overwrite,
    );
    _eventController.add(FileCreateEvent(createdFile: file));
    return file;
  }

  Future<void> deleteDocumentFile(ProjectDocumentFile file) async {
    await fileHandler.deleteDocumentFile(file);
    _eventController.add(FileDeleteEvent(deletedFile: file));
  }

  Future<ProjectDocumentFile> renameDocumentFile(
    ProjectDocumentFile file,
    String newName,
  ) async {
    final newFile = await fileHandler.renameDocumentFile(file, newName);
    _eventController.add(FileRenameEvent(oldFile: file, newFile: newFile));
    return newFile;
  }

  Future<ProjectDocumentFile> copyDocumentFile(
    ProjectDocumentFile source,
    String destinationParentUri,
  ) async {
    final newFile = await fileHandler.copyDocumentFile(
      source,
      destinationParentUri,
    );
    _eventController.add(FileCreateEvent(createdFile: newFile));
    return newFile;
  }

  Future<ProjectDocumentFile> moveDocumentFile(
    ProjectDocumentFile source,
    String destinationParentUri,
  ) async {
    final newFile = await fileHandler.moveDocumentFile(
      source,
      destinationParentUri,
    );
    _eventController.add(FileRenameEvent(oldFile: source, newFile: newFile));
    return newFile;
  }
  
  Future<({ProjectDocumentFile file, List<ProjectDocumentFile> createdDirs})>
      createDirectoryAndFile(
    String parentUri,
    String relativePath, {
    String? initialContent,
  }) async {
    final result = await fileHandler.createDirectoryAndFile(
      parentUri,
      relativePath,
      initialContent: initialContent,
    );
    // Fire events for all the newly created parent directories.
    for (final dir in result.createdDirs) {
      _eventController.add(FileCreateEvent(createdFile: dir));
    }
    // Fire the event for the final file.
    _eventController.add(FileCreateEvent(createdFile: result.file));
    return result;
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
  ) async {
    final newFile = await fileHandler.writeFile(file, content);
    _eventController.add(FileModifyEvent(modifiedFile: newFile));
    return newFile;
  }

  Future<ProjectDocumentFile> writeFileAsBytes(
    ProjectDocumentFile file,
    Uint8List bytes,
  ) async {
    final newFile = await fileHandler.writeFileAsBytes(file, bytes);
    _eventController.add(FileModifyEvent(modifiedFile: newFile));
    return newFile;
  }
  
  /// Resolves a [relativePath] against a [contextPath] to return a canonical
  /// project-relative path.
  ///
  /// This handles path normalization and `..` segments.
  /// Use this when reading paths *from* a Tiled file to find the actual asset in the map.
  String resolveRelativePath(String contextPath, String relativePath) {
    return fileHandler.resolveRelativePath(contextPath, relativePath);
  }

  /// Calculates the relative path string needed to go from [fromContext] to [toTarget].
  ///
  /// Use this when saving a picked file reference *into* a Tiled file.
  String calculateRelativePath(String fromContext, String toTarget) {
    return fileHandler.calculateRelativePath(fromContext, toTarget);
  }
}
