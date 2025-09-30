// =========================================
// UPDATED: lib/explorer/services/explorer_service.dart
// =========================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project_repository.dart';
import '../../explorer/explorer_workspace_state.dart';
import '../../project/project_models.dart';
import '../../utils/clipboard.dart';
import '../../data/dto/project_dto.dart';
import '../../logs/logs_provider.dart'; // ADDED for logging

final explorerServiceProvider = Provider<ExplorerService>((ref) {
  return ExplorerService(ref);
});

class ExplorerService {
  final Ref _ref;
  ExplorerService(this._ref);

  Talker get _talker => _ref.read(talkerProvider);

  ProjectRepository get _repo {
    final repo = _ref.read(projectRepositoryProvider);
    if (repo == null) {
      throw StateError('ProjectRepository is not available.');
    }
    return repo;
  }
  
  // ... (rehydrateWorkspace and updateWorkspace are unchanged) ...
  ExplorerWorkspaceState rehydrateWorkspace(ExplorerWorkspaceStateDto dto) {
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
    return newProject;
  }
  
  // ... (createFile and createFolder are unchanged) ...
  Future<void> createFile(String parentUri, String name) async {
    final newFile = await _repo.createDocumentFile(
      parentUri,
      name,
      isDirectory: false,
    );
    _ref.read(projectHierarchyProvider.notifier).add(newFile, parentUri);
    _ref
        .read(fileOperationControllerProvider)
        .add(FileCreateEvent(createdFile: newFile));
  }

  Future<void> createFolder(String parentUri, String name) async {
    final newFolder = await _repo.createDocumentFile(
      parentUri,
      name,
      isDirectory: true,
    );
    _ref.read(projectHierarchyProvider.notifier).add(newFolder, parentUri);
    _ref
        .read(fileOperationControllerProvider)
        .add(FileCreateEvent(createdFile: newFolder));
  }

  // REFACTORED: Added try/catch and logging.
  Future<void> renameItem(DocumentFile item, String newName) async {
    try {
      final parentUri = item.uri.substring(0, item.uri.lastIndexOf('%2F'));
      final renamedFile = await _repo.renameDocumentFile(item, newName);
      
      _ref.read(projectHierarchyProvider.notifier).rename(item, renamedFile, parentUri);
      _ref.read(fileOperationControllerProvider).add(FileRenameEvent(oldFile: item, newFile: renamedFile));
      _talker.info('Renamed "${item.name}" to "${renamedFile.name}"');
    } catch (e, st) {
      _talker.handle(e, st, 'Failed to rename item: ${item.name}');
      rethrow;
    }
  }
  
  // ... (deleteItem is unchanged) ...
  Future<void> deleteItem(DocumentFile item) async {
    final parentUri = item.uri.substring(0, item.uri.lastIndexOf('%2F'));
    await _repo.deleteDocumentFile(item);
    _ref.read(projectHierarchyProvider.notifier).remove(item, parentUri);
    _ref
        .read(fileOperationControllerProvider)
        .add(FileDeleteEvent(deletedFile: item));
  }
  
  // REFACTORED: Added try/catch and logging.
  Future<void> pasteItem(
    DocumentFile destinationFolder,
    ClipboardItem clipboardItem,
  ) async {
    try {
      final sourceFile = await _repo.getFileMetadata(clipboardItem.uri);
      if (sourceFile == null) {
        throw Exception('Clipboard source file not found.');
      }

      if (clipboardItem.operation == ClipboardOperation.copy) {
        final copiedFile = await _repo.copyDocumentFile(
          sourceFile,
          destinationFolder.uri,
        );
        _ref.read(projectHierarchyProvider.notifier).add(copiedFile, destinationFolder.uri);
        _ref.read(fileOperationControllerProvider).add(FileCreateEvent(createdFile: copiedFile));
        _talker.info('Pasted (copy) "${copiedFile.name}" into "${destinationFolder.name}"');
      } else {
        await moveItem(sourceFile, destinationFolder);
      }
    } catch (e, st) {
      _talker.handle(e, st, 'Failed to paste item into ${destinationFolder.name}');
      rethrow;
    }
  }

  // REFACTORED: Added try/catch and logging.
  Future<void> moveItem(
    DocumentFile source,
    DocumentFile destinationFolder,
  ) async {
    if (!destinationFolder.isDirectory) {
      throw Exception('Destination must be a folder.');
    }
    try {
      final sourceParentUri = source.uri.substring(
        0,
        source.uri.lastIndexOf('%2F'),
      );
      final movedFile = await _repo.moveDocumentFile(
        source,
        destinationFolder.uri,
      );
      
      _ref.read(projectHierarchyProvider.notifier).remove(source, sourceParentUri);
      _ref.read(projectHierarchyProvider.notifier).add(movedFile, destinationFolder.uri);
      _ref.read(fileOperationControllerProvider).add(FileRenameEvent(oldFile: source, newFile: movedFile));
      _talker.info('Moved "${source.name}" into "${destinationFolder.name}"');
    } catch (e, st) {
      _talker.handle(e, st, 'Failed to move "${source.name}" into "${destinationFolder.name}"');
      rethrow;
    }
  }
  
  // REFACTORED: Added try/catch and logging.
  Future<void> importFile(
    DocumentFile pickedFile,
    String projectRootUri,
  ) async {
    try {
      final importedFile = await _repo.copyDocumentFile(
        pickedFile,
        projectRootUri,
      );
      
      _ref.read(projectHierarchyProvider.notifier).add(importedFile, projectRootUri);
      _ref.read(fileOperationControllerProvider).add(FileCreateEvent(createdFile: importedFile));
      _talker.info('Imported file: "${importedFile.name}"');
    } catch (e, st) {
      _talker.handle(e, st, 'Failed to import file: ${pickedFile.name}');
      rethrow;
    }
  }
}