// =========================================
// FILE: lib/explorer/services/explorer_service.dart
// =========================================

// lib/explorer/services/explorer_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/project_hierarchy_cache.dart';
import '../../explorer/explorer_workspace_state.dart';
import '../../project/project_models.dart';
import '../../utils/clipboard.dart';
import '../../data/dto/project_dto.dart'; // ADDED

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
  
  // NEW: A dedicated rehydration method for the explorer workspace.
  ExplorerWorkspaceState rehydrateWorkspace(ExplorerWorkspaceStateDto dto) {
    // For now, this is a simple 1-to-1 mapping.
    // If explorer plugins needed more complex rehydration (e.g., async calls),
    // that logic would go here.
    return ExplorerWorkspaceState(
      activeExplorerPluginId: dto.activeExplorerPluginId,
      pluginStates: dto.pluginStates,
    );
  }

  Project updateWorkspace(
    Project project,
    ExplorerWorkspaceState Function(ExplorerWorkspaceState) updater,
  ) {
    final newWorkspace = updater(project.workspace);
    final newProject = project.copyWith(workspace: newWorkspace);
    // REMOVED: await _repo.saveProject(newProject);
    return newProject;
  }

  // REFACTORED: Methods now call the pure repository method first,
  // then update the UI state using the service's own Ref.
  Future<void> createFile(String parentUri, String name) async {
    final newFile = await _repo.createDocumentFile(
      parentUri,
      name,
      isDirectory: false,
    );
    _ref.read(projectHierarchyProvider.notifier).add(newFile, parentUri);
    _ref.read(fileOperationControllerProvider).add(FileCreateEvent(createdFile: newFile));
  }

  Future<void> createFolder(String parentUri, String name) async {
    final newFolder = await _repo.createDocumentFile(
      parentUri,
      name,
      isDirectory: true,
    );
    _ref.read(projectHierarchyProvider.notifier).add(newFolder, parentUri);
    _ref.read(fileOperationControllerProvider).add(FileCreateEvent(createdFile: newFolder));
  }

  Future<void> renameItem(DocumentFile item, String newName) async {
    final parentUri = item.uri.substring(0, item.uri.lastIndexOf('%2F'));
    final renamedFile = await _repo.renameDocumentFile(item, newName);
    if (renamedFile != null) {
      _ref.read(projectHierarchyProvider.notifier).rename(item, renamedFile, parentUri);
      _ref.read(fileOperationControllerProvider).add(FileRenameEvent(oldFile: item, newFile: renamedFile));
    }
  }

  Future<void> deleteItem(DocumentFile item) async {
    final parentUri = item.uri.substring(0, item.uri.lastIndexOf('%2F'));
    await _repo.deleteDocumentFile(item);
    _ref.read(projectHierarchyProvider.notifier).remove(item, parentUri);
    _ref.read(fileOperationControllerProvider).add(FileDeleteEvent(deletedFile: item));
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
      final copiedFile = await _repo.copyDocumentFile(
        sourceFile,
        destinationFolder.uri,
      );
      if (copiedFile != null) {
        _ref.read(projectHierarchyProvider.notifier).add(copiedFile, destinationFolder.uri);
        _ref.read(fileOperationControllerProvider).add(FileCreateEvent(createdFile: copiedFile));
      }
    } else { // Move operation
      await moveItem(sourceFile, destinationFolder);
    }
  }
  
  Future<void> moveItem(DocumentFile source, DocumentFile destinationFolder) async {
    if (!destinationFolder.isDirectory) {
      throw Exception('Destination must be a folder.');
    }
    final sourceParentUri = source.uri.substring(0, source.uri.lastIndexOf('%2F'));
    final movedFile = await _repo.moveDocumentFile(
      source,
      destinationFolder.uri,
    );
    if (movedFile != null) {
      _ref.read(projectHierarchyProvider.notifier).remove(source, sourceParentUri);
      _ref.read(projectHierarchyProvider.notifier).add(movedFile, destinationFolder.uri);
      _ref.read(fileOperationControllerProvider).add(FileRenameEvent(oldFile: source, newFile: movedFile));
    }
  }

  Future<void> importFile(
    DocumentFile pickedFile,
    String projectRootUri,
  ) async {
    final importedFile = await _repo.copyDocumentFile(pickedFile, projectRootUri);
    if (importedFile != null) {
      _ref.read(projectHierarchyProvider.notifier).add(importedFile, projectRootUri);
      _ref.read(fileOperationControllerProvider).add(FileCreateEvent(createdFile: importedFile));
    }
  }
}