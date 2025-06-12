// lib/explorer/plugins/file_explorer/file_explorer_state.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/app_notifier.dart';
import '../../../project/local_file_system_project.dart';
import '../../../project/project_models.dart';
import '../../../project/workspace_service.dart'; // NEW
import '../../../project/workspace_state.dart';   // NEW

// MODIFIED: State is now WorkspaceState
class FileExplorerState extends WorkspaceState {
  const FileExplorerState({
    super.viewMode,
    super.expandedFolders,
  });
}

// MODIFIED: Provider now returns a Future because it loads state asynchronously.
final fileExplorerStateProvider = StateNotifierProvider.family
    .autoDispose<FileExplorerStateNotifier, FileExplorerState, String>(
        (ref, projectId) {
  return FileExplorerStateNotifier(ref, projectId);
});

class FileExplorerStateNotifier extends StateNotifier<FileExplorerState> {
  final Ref _ref;
  final String _projectId;

  FileExplorerStateNotifier(this._ref, this._projectId) : super(const FileExplorerState()) {
    _initState();
  }

  // NEW: Asynchronous initialization method.
  Future<void> _initState() async {
    final project = _ref.read(appNotifierProvider).value?.currentProject;
    final workspaceService = _ref.read(workspaceServiceProvider);

    if (project is LocalProject && project.id == _projectId) {
      // Load persisted state for LocalProject
      final loadedState = await workspaceService.loadState(
        project.fileHandler,
        project.projectDataPath,
      );
      if (mounted) state = loadedState;
    } else if (project is SimpleLocalFileProject && project.id == _projectId) {
      // Simple projects start with a default, non-persistent state
      if (mounted) state = const FileExplorerState();
    }
  }

  void setViewMode(FileExplorerViewMode newMode) {
    if (state.fileExplorerViewMode == newMode) return;
    state = state.copyWith(fileExplorerViewMode: newMode);
    _persistStateIfNecessary();
  }

  void toggleFolderExpansion(String folderUri) {
    final newExpanded = Set<String>.from(state.expandedFolders);
    if (newExpanded.contains(folderUri)) {
      newExpanded.remove(folderUri);
    } else {
      newExpanded.add(folderUri);
    }
    state = state.copyWith(expandedFolders: newExpanded);
    _persistStateIfNecessary();
  }

  void _persistStateIfNecessary() {
    final project = _ref.read(appNotifierProvider).value?.currentProject;
    final workspaceService = _ref.read(workspaceServiceProvider);

    // Only persist the state for LocalProject
    if (project is LocalProject && project.id == _projectId) {
      workspaceService.saveState(project.fileHandler, project.projectDataPath, state);
    }
  }
}