// lib/explorer/services/explorer_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project_repository.dart';
import '../../explorer/explorer_workspace_state.dart';
import '../../project/project_models.dart';
import '../../utils/clipboard.dart';

final explorerServiceProvider = Provider<ExplorerService>((ref) {
  return ExplorerService(ref);
});

class ExplorerService {
  final Ref _ref;
  ExplorerService(this._ref);

  ProjectRepository get _repo {
    final repo = _ref.read(projectRepositoryProvider);
    if (repo == null) {
      throw StateError('ProjectRepository is not available.');
    }
    return repo;
  }

  // ... (updateWorkspace is unchanged) ...
  Future<Project> updateWorkspace(
    Project project,
    ExplorerWorkspaceState Function(ExplorerWorkspaceState) updater,
  ) async {
    final newWorkspace = updater(project.workspace);
    final newProject = project.copyWith(workspace: newWorkspace);
    await _repo.saveProject(newProject);
    return newProject;
  }

  // REFACTOR: Pass the service's Ref to the repository methods.
  Future<void> createFile(String parentUri, String name) async {
    await _repo.createDocumentFile(_ref, parentUri, name, isDirectory: false);
  }

  Future<void> createFolder(String parentUri, String name) async {
    await _repo.createDocumentFile(_ref, parentUri, name, isDirectory: true);
  }

  Future<void> renameItem(DocumentFile item, String newName) async {
    await _repo.renameDocumentFile(_ref, item, newName);
  }

  Future<void> deleteItem(DocumentFile item) async {
    await _repo.deleteDocumentFile(_ref, item);
  }

  Future<void> pasteItem(
    DocumentFile destinationFolder,
    ClipboardItem clipboardItem,
  ) async {
    final sourceFile = await _repo.getFileMetadata(clipboardItem.uri);
    if (sourceFile == null) {
      throw Exception('Clipboard source file not found.');
    }
    if (clipboardItem.operation == ClipboardOperation.copy) {
      await _repo.copyDocumentFile(_ref, sourceFile, destinationFolder.uri);
    } else {
      await _repo.moveDocumentFile(_ref, sourceFile, destinationFolder.uri);
    }
  }

  Future<void> importFile(
    DocumentFile pickedFile,
    String projectRootUri,
  ) async {
    await _repo.copyDocumentFile(_ref, pickedFile, projectRootUri);
  }
}
