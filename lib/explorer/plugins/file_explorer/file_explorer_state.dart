// lib/explorer/plugins/file_explorer/file_explorer_state.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/app_notifier.dart';
import '../../../project/local_file_system_project.dart';
import '../../../project/project_models.dart';
import '../../../project/simple_local_file_project.dart'; // NEW: Add missing import
import '../../../project/workspace_service.dart';
import '../../../project/workspace_state.dart';

// DELETED: This class is redundant. We will use WorkspaceState directly.
/*
class FileExplorerState extends WorkspaceState {
  const FileExplorerState({
    super.viewMode,
    super.expandedFolders,
  });
}
*/

// MODIFIED: Provider now correctly uses WorkspaceState as its state type.
// It is no longer AutoDispose to prevent state loss on quick rebuilds.
// It is no longer a Future, initialization is handled inside the notifier.
final fileExplorerStateProvider = StateNotifierProvider.family<
    FileExplorerStateNotifier, WorkspaceState, String>((ref, projectId) {
  return FileExplorerStateNotifier(ref, projectId);
});

class FileExplorerStateNotifier extends StateNotifier<WorkspaceState> {
  final Ref _ref;
  final String _projectId;
  // NEW: Add a flag to prevent multiple initializations
  bool _isInitialized = false;

  FileExplorerStateNotifier(this._ref, this._projectId) : super(const WorkspaceState()) {
    _initState();
  }

  Future<void> _initState() async {
    // Prevent re-initialization on rebuilds
    if (_isInitialized) return;
    _isInitialized = true;

    final project = _ref.read(appNotifierProvider).value?.currentProject;
    final workspaceService = _ref.read(workspaceServiceProvider);

    if (project != null && project.id == _projectId) {
      if (project is LocalProject) {
        final loadedState = await workspaceService.loadState(
          project.fileHandler,
          project.projectDataPath,
        );
        if (mounted) state = loadedState;
      } else if (project is SimpleLocalFileProject) {
        // Simple projects always start with a default, non-persistent state.
        if (mounted) state = const WorkspaceState();
      }
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

    if (project is LocalProject && project.id == _projectId) {
      workspaceService.saveState(project.fileHandler, project.projectDataPath, state);
    }
  }
}