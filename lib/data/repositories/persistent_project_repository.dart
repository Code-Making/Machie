// =========================================
// FILE: lib/data/repositories/persistent_project_repository.dart
// =========================================

// lib/data/repositories/persistent_project_repository.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:collection/collection.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart'; // REMOVED: No longer needed
import '../../data/file_handler/file_handler.dart';
import 'project_repository.dart';
import '../../data/dto/project_dto.dart'; // ADDED

const _projectFileName = 'project.json';

class PersistentProjectRepository implements ProjectRepository {
  @override
  final FileHandler fileHandler;
  final String _projectDataPath;

  PersistentProjectRepository(this.fileHandler, this._projectDataPath);

  @override
  Future<ProjectDto> loadProjectDto() async {
    final files = await fileHandler.listDirectory(
      _projectDataPath,
      includeHidden: true,
    );
    final projectFile = files.firstWhereOrNull(
      (f) => f.name == _projectFileName,
    );

    if (projectFile != null) {
      try {
        final content = await fileHandler.readFile(projectFile.uri);
        final json = jsonDecode(content);
        return ProjectDto.fromJson(json);
      } catch (e) {
        // Fallback for corrupted file. Return a fresh, empty DTO.
        return const ProjectDto(
          session: TabSessionStateDto(
            tabs: [],
            currentTabIndex: 0,
            tabMetadata: {},
          ),
          // FIXED: Provide the required 'workspace' argument.
          workspace: ExplorerWorkspaceStateDto(
            activeExplorerPluginId: 'com.machine.file_explorer',
            pluginStates: {},
          ),
        );
      }
    } else {
      // Return a fresh, empty DTO if no file exists.
      return const ProjectDto(
        session: TabSessionStateDto(
          tabs: [],
          currentTabIndex: 0,
          tabMetadata: {},
        ),
        // FIXED: Provide the required 'workspace' argument.
        workspace: ExplorerWorkspaceStateDto(
          activeExplorerPluginId: 'com.machine.file_explorer',
          pluginStates: {},
        ),
      );
    }
  }

  // REFACTORED: Now accepts a DTO.
  @override
  Future<void> saveProjectDto(ProjectDto projectDto) async {
    final content = jsonEncode(projectDto.toJson());
    await fileHandler.createDocumentFile(
      _projectDataPath,
      _projectFileName,
      initialContent: content,
      overwrite: true,
    );
  }

  // REFACTORED: Methods are now pure data operations.
  @override
  Future<DocumentFile> createDocumentFile(
    // REMOVED: Ref ref,
    String parentUri,
    String name, {
    bool isDirectory = false,
    String? initialContent,
    Uint8List? initialBytes,
    bool overwrite = false,
  }) async {
    final newFile = await fileHandler.createDocumentFile(
      parentUri,
      name,
      isDirectory: isDirectory,
      initialContent: initialContent,
      initialBytes: initialBytes,
      overwrite: overwrite,
    );
    // REMOVED: All ref.read() calls. This logic moves to the service layer.
    return newFile;
  }

  @override
  Future<void> deleteDocumentFile(
    /* REMOVED: Ref ref,*/ DocumentFile file,
  ) async {
    // REMOVED: parentUri calculation and ref.read() calls. This moves to the service.
    await fileHandler.deleteDocumentFile(file);
  }

  @override
  Future<DocumentFile?> renameDocumentFile(
    // REMOVED: Ref ref,
    DocumentFile file,
    String newName,
  ) async {
    final renamedFile = await fileHandler.renameDocumentFile(file, newName);
    // REMOVED: All ref.read() calls. This logic moves to the service layer.
    return renamedFile;
  }

  @override
  Future<DocumentFile?> copyDocumentFile(
    // REMOVED: Ref ref,
    DocumentFile source,
    String destinationParentUri,
  ) async {
    final copiedFile = await fileHandler.copyDocumentFile(
      source,
      destinationParentUri,
    );
    // REMOVED: All ref.read() calls. This logic moves to the service layer.
    return copiedFile;
  }

  @override
  Future<DocumentFile?> moveDocumentFile(
    // REMOVED: Ref ref,
    DocumentFile source,
    String destinationParentUri,
  ) async {
    final movedFile = await fileHandler.moveDocumentFile(
      source,
      destinationParentUri,
    );
    // REMOVED: All ref.read() calls. This logic moves to the service layer.
    return movedFile;
  }

  // --- Unchanged Delegations ---
  @override
  Future<DocumentFile?> getFileMetadata(String uri) =>
      fileHandler.getFileMetadata(uri);
  @override
  Future<List<DocumentFile>> listDirectory(
    String uri, {
    bool includeHidden = false,
  }) => fileHandler.listDirectory(uri, includeHidden: includeHidden);
  @override
  Future<String> readFile(String uri) => fileHandler.readFile(uri);
  @override
  Future<Uint8List> readFileAsBytes(String uri) =>
      fileHandler.readFileAsBytes(uri);
  @override
  Future<DocumentFile> writeFile(DocumentFile file, String content) =>
      fileHandler.writeFile(file, content);
  @override
  Future<DocumentFile> writeFileAsBytes(DocumentFile file, Uint8List bytes) =>
      fileHandler.writeFileAsBytes(file, bytes);
}
