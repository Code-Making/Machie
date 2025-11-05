import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dto/project_dto.dart';
import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project/project_repository.dart';
import '../../explorer/explorer_workspace_state.dart';
import '../../logs/logs_provider.dart';
import '../../project/project_models.dart';
import '../../utils/clipboard.dart';
import '../../utils/toast.dart';

// Any class that wants to be notified of file events will implement this.
mixin FileOperationEventListener {
  Future<void> onFileOperation(FileOperationEvent event);
}

final explorerServiceProvider = Provider<ExplorerService>((ref) {
  return ExplorerService(ref);
});

class ExplorerService {
  final Ref _ref;
  final List<FileOperationEventListener> _listeners = [];

  ExplorerService(this._ref) {
    // The service itself becomes the single, persistent listener to the global stream.
    _ref.listen<AsyncValue<FileOperationEvent>>(fileOperationStreamProvider, (
      _,
      next,
    ) {
      next.whenData((event) {
        _dispatchEvent(event);
      });
    });
  }

  // NEW: Method to allow other parts of the app to register for notifications.
  void addListener(FileOperationEventListener listener) {
    _listeners.add(listener);
  }

  // NEW: Method to allow listeners to clean up after themselves.
  void removeListener(FileOperationEventListener listener) {
    _listeners.remove(listener);
  }

  void _dispatchEvent(FileOperationEvent event) {
    // Iterate over a copy of the list in case a listener modifies the original list during dispatch.
    for (final listener in List.of(_listeners)) {
      try {
        // Notify each listener.
        listener.onFileOperation(event);
      } catch (e, st) {
        _talker.handle(e, st, 'Error in a FileOperationEventListener');
      }
    }
  }

  Talker get _talker => _ref.read(talkerProvider);

  ProjectRepository get _repo {
    final repo = _ref.read(projectRepositoryProvider);
    if (repo == null) {
      throw StateError('ProjectRepository is not available.');
    }
    return repo;
  }

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

  Future<ProjectDocumentFile> createFileWithHierarchy(
    String projectRootUri,
    String relativePath,
  ) async {
    final result = await _repo.fileHandler.createDirectoryAndFile(
      projectRootUri,
      relativePath,
    );

    final eventController = _ref.read(fileOperationControllerProvider);

    // Fire events for all the newly created parent directories.
    for (final dir in result.createdDirs) {
      eventController.add(FileCreateEvent(createdFile: dir));
    }

    // Fire the event for the final file.
    eventController.add(FileCreateEvent(createdFile: result.file));

    _talker.info('Created file with hierarchy: "$relativePath"');
    return result.file;
  }

  Future<void> createFile(String parentUri, String name) async {
    final newFile = await _repo.createDocumentFile(
      parentUri,
      name,
      isDirectory: false,
    );
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
    _ref
        .read(fileOperationControllerProvider)
        .add(FileCreateEvent(createdFile: newFolder));
  }

  Future<void> deleteItem(ProjectDocumentFile item) async {
    await _repo.deleteDocumentFile(item);
    _ref
        .read(fileOperationControllerProvider)
        .add(FileDeleteEvent(deletedFile: item));
  }

  Future<void> renameItem(ProjectDocumentFile item, String newName) async {
    try {
      final renamedFile = await _repo.renameDocumentFile(item, newName);
      _ref
          .read(fileOperationControllerProvider)
          .add(FileRenameEvent(oldFile: item, newFile: renamedFile));
      _talker.info('Renamed "${item.name}" to "${renamedFile.name}"');
    } catch (e, st) {
      _talker.handle(e, st, 'Failed to rename item: ${item.name}');
      MachineToast.error(
        "Failed to rename '${item.name}'. The name might be invalid or already exist.",
      );
    }
  }

  Future<void> pasteItem(
    ProjectDocumentFile destinationFolder,
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
        _ref
            .read(fileOperationControllerProvider)
            .add(FileCreateEvent(createdFile: copiedFile));
        _talker.info(
          'Pasted (copy) "${copiedFile.name}" into "${destinationFolder.name}"',
        );
      } else {
        await moveItem(sourceFile, destinationFolder);
      }
    } catch (e, st) {
      _talker.handle(
        e,
        st,
        'Failed to paste item into ${destinationFolder.name}',
      );
      MachineToast.error("Paste operation failed. Please try again.");
    }
  }

  Future<void> moveItem(
    ProjectDocumentFile source,
    ProjectDocumentFile destinationFolder,
  ) async {
    if (!destinationFolder.isDirectory) {
      MachineToast.error('Destination must be a folder.');
      return;
    }
    try {
      final movedFile = await _repo.moveDocumentFile(
        source,
        destinationFolder.uri,
      );
      _ref
          .read(fileOperationControllerProvider)
          .add(FileRenameEvent(oldFile: source, newFile: movedFile));
      _talker.info('Moved "${source.name}" into "${destinationFolder.name}"');
    } catch (e, st) {
      _talker.handle(
        e,
        st,
        'Failed to move "${source.name}" into "${destinationFolder.name}"',
      );
      MachineToast.error(
        "Failed to move '${source.name}'. Your device may not support this operation.",
      );
    }
  }

  Future<void> importFile(
    ProjectDocumentFile pickedFile,
    String projectRootUri,
  ) async {
    try {
      final importedFile = await _repo.copyDocumentFile(
        pickedFile,
        projectRootUri,
      );
      _ref
          .read(fileOperationControllerProvider)
          .add(FileCreateEvent(createdFile: importedFile));
      _talker.info('Imported file: "${importedFile.name}"');
    } catch (e, st) {
      _talker.handle(e, st, 'Failed to import file: ${pickedFile.name}');
      MachineToast.error("Failed to import '${pickedFile.name}'.");
    }
  }
}
