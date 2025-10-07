// =========================================
// UPDATED: lib/data/repositories/persistent_project_repository.dart
// =========================================

import 'dart:convert';
import 'dart:typed_data';
import 'package:collection/collection.dart';
import '../../data/file_handler/file_handler.dart';
import 'project_repository.dart';
import '../../data/dto/project_dto.dart';

const _projectFileName = 'project.json';

class PersistentProjectRepository implements ProjectRepository {
  @override
  final FileHandler fileHandler;
  final String _projectDataPath;

  PersistentProjectRepository(this.fileHandler, this._projectDataPath);

  // ... (loadProjectDto and saveProjectDto are unchanged) ...
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
        return const ProjectDto(
          session: TabSessionStateDto(
            tabs: [],
            currentTabIndex: 0,
            tabMetadata: {},
          ),
          workspace: ExplorerWorkspaceStateDto(
            activeExplorerPluginId: 'com.machine.file_explorer',
            pluginStates: {},
          ),
        );
      }
    } else {
      return const ProjectDto(
        session: TabSessionStateDto(
          tabs: [],
          currentTabIndex: 0,
          tabMetadata: {},
        ),
        workspace: ExplorerWorkspaceStateDto(
          activeExplorerPluginId: 'com.machine.file_explorer',
          pluginStates: {},
        ),
      );
    }
  }

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

  // ... (createDocumentFile and deleteDocumentFile are unchanged) ...
  @override
  Future<DocumentFile> createDocumentFile(
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
    return newFile;
  }

  @override
  Future<void> deleteDocumentFile(DocumentFile file) async {
    await fileHandler.deleteDocumentFile(file);
  }

  // REFACTORED: Signatures updated to return non-nullable Futures.
  @override
  Future<DocumentFile> renameDocumentFile(
    DocumentFile file,
    String newName,
  ) async {
    return fileHandler.renameDocumentFile(file, newName);
  }

  @override
  Future<DocumentFile> copyDocumentFile(
    DocumentFile source,
    String destinationParentUri,
  ) async {
    return fileHandler.copyDocumentFile(source, destinationParentUri);
  }

  @override
  Future<DocumentFile> moveDocumentFile(
    DocumentFile source,
    String destinationParentUri,
  ) async {
    return fileHandler.moveDocumentFile(source, destinationParentUri);
  }

  // ... (Unchanged Delegations) ...
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
