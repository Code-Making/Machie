// lib/explorer/services/explorer_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project_repository.dart';
import '../../explorer/explorer_workspace_state.dart';
import '../../project/project_models.dart';
import '../../app/app_notifier.dart';
import '../../utils/clipboard.dart'; // REFACTOR: Add this missing import

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

  /// Updates a specific part of the explorer's workspace state and persists it.
  Future<Project> updateWorkspace(
    Project project,
    ExplorerWorkspaceState Function(ExplorerWorkspaceState) updater,
  ) async {
    final newWorkspace = updater(project.workspace);
    final newProject = project.copyWith(workspace: newWorkspace);
    await _repo.saveProject(newProject);
    return newProject;
  }

  // REFACTOR: New methods to replace performFileOperation
  Future<void> createFile(String parentUri, String name) async {
    await _repo.createDocumentFile(parentUri, name, isDirectory: false);
    _ref.invalidate(currentProjectDirectoryContentsProvider);
  }

  Future<void> createFolder(String parentUri, String name) async {
    await _repo.createDocumentFile(parentUri, name, isDirectory: true);
    _ref.invalidate(currentProjectDirectoryContentsProvider);
  }

  Future<void> renameItem(DocumentFile item, String newName) async {
    await _repo.renameDocumentFile(item, newName);
    _ref.invalidate(currentProjectDirectoryContentsProvider);
  }

  Future<void> deleteItem(DocumentFile item) async {
    await _repo.deleteDocumentFile(item);
    _ref.invalidate(currentProjectDirectoryContentsProvider);
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
      await _repo.copyDocumentFile(sourceFile, destinationFolder.uri);
    } else {
      await _repo.moveDocumentFile(sourceFile, destinationFolder.uri);
    }
    _ref.invalidate(currentProjectDirectoryContentsProvider);
  }

  Future<void> importFile(DocumentFile pickedFile, String projectRootUri) async {
    await _repo.copyDocumentFile(pickedFile, projectRootUri);
    _ref.invalidate(currentProjectDirectoryContentsProvider);
  }
}