// lib/explorer/plugins/file_explorer/file_explorer_state.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/app_notifier.dart';
import '../../../project/local_file_system_project.dart';
import '../../../project/project_models.dart';

// No change to the state class
class FileExplorerState {
  final FileExplorerViewMode viewMode;
  final Set<String> expandedFolders;

  FileExplorerState({
    this.viewMode = FileExplorerViewMode.sortByNameAsc,
    this.expandedFolders = const {},
  });

  FileExplorerState copyWith({
    FileExplorerViewMode? viewMode,
    Set<String>? expandedFolders,
  }) {
    return FileExplorerState(
      viewMode: viewMode ?? this.viewMode,
      expandedFolders: expandedFolders ?? this.expandedFolders,
    );
  }
}

// MODIFIED: Provider now just creates the notifier.
// We select the data we need inside the view instead.
final fileExplorerStateProvider = StateNotifierProvider.autoDispose
    .family<FileExplorerStateNotifier, FileExplorerState, String>((ref, projectId) {
  return FileExplorerStateNotifier(ref, projectId);
});

class FileExplorerStateNotifier extends StateNotifier<FileExplorerState> {
  final Ref _ref;
  final String _projectId;

  FileExplorerStateNotifier(this._ref, this._projectId) : super(FileExplorerState()) {
    // Initialize the state when the notifier is created.
    _initialize();
  }
  
  void _initialize() {
    final project = _ref.read(appNotifierProvider).value?.currentProject;
    if (project != null && project.id == _projectId) {
      if (project is LocalProject) {
        // For persistent projects, initialize from its data.
        state = FileExplorerState(
          viewMode: project.fileExplorerViewMode,
          expandedFolders: project.expandedFolders,
        );
      } else {
        // For simple projects, initialize with defaults (including root expanded).
        state = FileExplorerState(expandedFolders: {project.rootUri});
      }
    }
  }

  void setViewMode(FileExplorerViewMode newMode) {
    if (state.viewMode == newMode) return;
    
    // Update the local UI state immediately.
    state = state.copyWith(viewMode: newMode);

    // Now, update the persistent model in the background.
    final project = _ref.read(appNotifierProvider).value?.currentProject;
    if (project is LocalProject) {
      final updatedProject = project.copyWith(fileExplorerViewMode: newMode);
      _ref.read(appNotifierProvider.notifier).updateProject(updatedProject);
    }
  }

  void toggleFolderExpansion(String folderUri) {
    final newExpanded = Set<String>.from(state.expandedFolders);
    if (newExpanded.contains(folderUri)) {
      newExpanded.remove(folderUri);
    } else {
      newExpanded.add(folderUri);
    }
    
    // Update local UI state.
    state = state.copyWith(expandedFolders: newExpanded);

    // Update persistent model.
    final project = _ref.read(appNotifierProvider).value?.currentProject;
    if (project is LocalProject) {
      final updatedProject = project.copyWith(expandedFolders: newExpanded);
      _ref.read(appNotifierProvider.notifier).updateProject(updatedProject);
    }
  }
}