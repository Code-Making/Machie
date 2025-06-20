// lib/explorer/plugins/file_explorer/file_explorer_state.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/app_notifier.dart';
import '../../explorer_workspace_state.dart';
import 'file_explorer_plugin.dart';
import '../../services/explorer_service.dart'; // REFACTOR

enum FileExplorerViewMode { sortByNameAsc, sortByNameDesc, sortByDateModified }

// NEW: This model is now specific to the file explorer.
class FileExplorerSettings {
  final FileExplorerViewMode viewMode;
  final Set<String> expandedFolders;

  const FileExplorerSettings({
    this.viewMode = FileExplorerViewMode.sortByNameAsc,
    this.expandedFolders = const {},
  });

  FileExplorerSettings copyWith({
    FileExplorerViewMode? viewMode,
    Set<String>? expandedFolders,
  }) {
    return FileExplorerSettings(
      viewMode: viewMode ?? this.viewMode,
      expandedFolders: expandedFolders ?? this.expandedFolders,
    );
  }

  factory FileExplorerSettings.fromJson(Map<String, dynamic> json) {
    return FileExplorerSettings(
      viewMode: FileExplorerViewMode.values.firstWhere(
        (e) => e.name == json['viewMode'],
        orElse: () => FileExplorerViewMode.sortByNameAsc,
      ),
      expandedFolders: Set<String>.from(json['expandedFolders'] ?? []),
    );
  }

  Map<String, dynamic> toJson() => {
        'viewMode': viewMode.name,
        'expandedFolders': expandedFolders.toList(),
      };
}

// REFACTOR: This provider now returns the settings directly from the main project state.
final fileExplorerStateProvider =
    Provider.autoDispose.family<FileExplorerSettings, String>((ref, projectId) {
  final project = ref.watch(appNotifierProvider).value?.currentProject;
  if (project == null || project.id != projectId) {
    return const FileExplorerSettings(); // Return default if project not ready
  }

  final pluginStateJson =
      project.workspace.pluginStates[FileExplorerPlugin().id];
  if (pluginStateJson != null && pluginStateJson is Map<String, dynamic>) {
    return FileExplorerSettings.fromJson(pluginStateJson);
  }

  return const FileExplorerSettings();
});

// REFACTOR: The notifier is now much simpler.
final fileExplorerNotifierProvider = Provider.autoDispose
    .family<FileExplorerNotifier, String>((ref, projectId) {
  return FileExplorerNotifier(ref, projectId);
});

class FileExplorerNotifier {
  final Ref _ref;
  final String _projectId;
  final String _pluginId = FileExplorerPlugin().id;

  FileExplorerNotifier(this._ref, this._projectId);

  Future<void> _updateState(
    FileExplorerSettings Function(FileExplorerSettings) updater,
  ) async {
    final project = _ref.read(appNotifierProvider).value?.currentProject;
    if (project == null || project.id != _projectId) return;

    final explorerService = _ref.read(explorerServiceProvider);
    final appNotifier = _ref.read(appNotifierProvider.notifier);

    // Get current settings
    final currentSettings = _ref.read(fileExplorerStateProvider(_projectId));
    final newSettings = updater(currentSettings);

    final newProject = await explorerService.updateWorkspace(
      project,
      (w) {
        final newPluginStates = Map<String, dynamic>.from(w.pluginStates);
        newPluginStates[_pluginId] = newSettings.toJson();
        return w.copyWith(pluginStates: newPluginStates);
      },
    );
    // Update the project in the global state
    appNotifier.updateCurrentTab(newProject.session.currentTab!);
  }

  void setViewMode(FileExplorerViewMode newMode) {
    _updateState((s) => s.copyWith(viewMode: newMode));
  }

  void toggleFolderExpansion(String folderUri) {
    _updateState((s) {
      final newExpanded = Set<String>.from(s.expandedFolders);
      if (newExpanded.contains(folderUri)) {
        newExpanded.remove(folderUri);
      } else {
        newExpanded.add(folderUri);
      }
      return s.copyWith(expandedFolders: newExpanded);
    });
  }
}