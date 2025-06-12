// lib/explorer/plugins/file_explorer/file_explorer_state.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/app_notifier.dart';
import '../../../project/local_file_system_project.dart';
import '../../../project/project_models.dart';

// NEW: A class to hold all state for the file explorer UI.
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

// MODIFIED: This is now a family provider, keyed by the project's unique ID.
final fileExplorerStateProvider = StateNotifierProvider.family<
    FileExplorerStateNotifier, FileExplorerState, String>((ref, projectId) {
      
  final project = ref.watch(appNotifierProvider.select((app) => app.value?.currentProject));

  // Initialize state based on project type.
  if (project != null && project.id == projectId) {
    if (project is LocalProject) {
      // For persistent projects, initialize from the project's saved data.
      return FileExplorerStateNotifier(
        ref,
        initialState: FileExplorerState(
          viewMode: project.fileExplorerViewMode,
          expandedFolders: project.expandedFolders,
        ),
      );
    }
  }
  // For Simple projects or if no project is found, use a default state.
  return FileExplorerStateNotifier(ref, initialState: FileExplorerState());
});

class FileExplorerStateNotifier extends StateNotifier<FileExplorerState> {
  final Ref _ref;

  FileExplorerStateNotifier(this._ref, {required FileExplorerState initialState}) : super(initialState);

  void setViewMode(FileExplorerViewMode newMode) {
    if (state.viewMode == newMode) return;
    state = state.copyWith(viewMode: newMode);
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

  // This is the key: the plugin's local state change triggers an update
  // to the persistent project model if needed.
  void _persistStateIfNecessary() {
    final appNotifier = _ref.read(appNotifierProvider.notifier);
    final project = _ref.read(appNotifierProvider).value?.currentProject;

    if (project is LocalProject) {
      // Create an updated project model with the new state and pass it to the AppNotifier.
      final updatedProject = project.copyWith(
        fileExplorerViewMode: state.viewMode,
        expandedFolders: state.expandedFolders,
      );
      appNotifier.updateProject(updatedProject);
    }
    // If it's a SimpleLocalFileProject, we do nothing. The state lives and dies with the provider.
  }
}