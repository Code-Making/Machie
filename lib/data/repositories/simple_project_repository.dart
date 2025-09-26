// =========================================
// FILE: lib/data/repositories/simple_project_repository.dart
// =========================================

import 'dart:typed_data';
import '../../data/dto/project_dto.dart';
import '../../data/file_handler/file_handler.dart';
import 'project_repository.dart';

/// A repository for "simple" projects that do not persist a `project.json`
/// file in their directory. Their state is loaded from a JSON map provided
/// at creation time (typically from SharedPreferences). Saving is a no-op.
class SimpleProjectRepository implements ProjectRepository {
  @override
  final FileHandler fileHandler;
  final Map<String, dynamic>? _projectStateJson;

  SimpleProjectRepository(this.fileHandler, this._projectStateJson);

  // REFACTORED: Implements the new DTO-based method.
  @override
  Future<ProjectDto> loadProjectDto() async {
    if (_projectStateJson != null) {
      return ProjectDto.fromJson(_projectStateJson);
    } else {
      // Return a fresh, empty DTO for a new simple project.
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

  // REFACTORED: Implements the new DTO-based method.
  @override
  Future<void> saveProjectDto(ProjectDto projectDto) async {
    // No-op. Simple projects are not saved to their own directory.
    // Their state is handled by the AppState/PersistenceService.
    return;
  }

  // --- File operations are delegated directly to the fileHandler ---
  // These methods are now pure data operations, as the service layer
  // handles all the UI state updates (cache, events, etc.).

  @override
  Future<DocumentFile> createDocumentFile(
    String parentUri,
    String name, {
    bool isDirectory = false,
    String? initialContent,
    Uint8List? initialBytes,
    bool overwrite = false,
  }) async {
    return await fileHandler.createDocumentFile(
      parentUri,
      name,
      isDirectory: isDirectory,
      initialContent: initialContent,
      initialBytes: initialBytes,
      overwrite: overwrite,
    );
  }

  @override
  Future<void> deleteDocumentFile(DocumentFile file) async {
    await fileHandler.deleteDocumentFile(file);
  }

  @override
  Future<DocumentFile?> renameDocumentFile(
    DocumentFile file,
    String newName,
  ) async {
    return await fileHandler.renameDocumentFile(file, newName);
  }

  @override
  Future<DocumentFile?> copyDocumentFile(
    DocumentFile source,
    String destinationParentUri,
  ) async {
    return await fileHandler.copyDocumentFile(source, destinationParentUri);
  }

  @override
  Future<DocumentFile?> moveDocumentFile(
    DocumentFile source,
    String destinationParentUri,
  ) async {
    return await fileHandler.moveDocumentFile(source, destinationParentUri);
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
