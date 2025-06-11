// lib/explorer/plugins/file_explorer/file_explorer_state.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/app_notifier.dart';
import '../../../project/local_file_system_project.dart';
import '../../../project/project_models.dart';

/// Manages the state specific to the FileExplorerView.
final fileExplorerStateProvider =
    StateNotifierProvider<FileExplorerStateNotifier, FileExplorerViewMode>((ref) {
  // The state of this provider is initialized from the currently open project.
  // It watches the project state so if the project changes, this state updates.
  final currentViewMode = ref.watch(appNotifierProvider.select((appState) {
    final project = appState.value?.currentProject;
    if (project is LocalProject) {
      return project.fileExplorerViewMode;
    }
    return FileExplorerViewMode.sortByNameAsc; // Default fallback
  }));

  return FileExplorerStateNotifier(ref, currentViewMode);
});

class FileExplorerStateNotifier extends StateNotifier<FileExplorerViewMode> {
  final Ref _ref;

  FileExplorerStateNotifier(this._ref, FileExplorerViewMode initialMode) : super(initialMode);

  /// Sets the view mode and updates the global project state.
  void setViewMode(FileExplorerViewMode newMode) {
    if (state == newMode) return;

    // 1. Update the local state for this plugin's UI to react instantly.
    state = newMode;

    // 2. Get the main AppNotifier.
    final appNotifier = _ref.read(appNotifierProvider.notifier);
    final project = _ref.read(appNotifierProvider).value?.currentProject;

    // 3. This is the crucial link: The plugin's notifier tells the main AppNotifier
    //    to update its project model. AppNotifier doesn't need to know *what*
    //    `fileExplorerViewMode` is, it just accepts an updated project model.
    if (project is LocalProject) {
      final updatedProject = project.copyWith(fileExplorerViewMode: newMode);
      appNotifier.updateProject(updatedProject);
    }
  }
}