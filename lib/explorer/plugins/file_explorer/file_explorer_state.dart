// lib/explorer/plugins/file_explorer/file_explorer_state.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/app_notifier.dart';
import '../../explorer_workspace_service.dart';
import '../file_explorer/file_explorer_plugin.dart';

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

// MODIFIED: This is now a standard StateNotifierProvider, not async.
// It returns a nullable state to represent the "loading" period.
final fileExplorerStateProvider = StateNotifierProvider.family
    .autoDispose<FileExplorerStateNotifier, FileExplorerSettings?, String>((
      ref,
      projectId,
    ) {
      return FileExplorerStateNotifier(ref, projectId);
    });

class FileExplorerStateNotifier extends StateNotifier<FileExplorerSettings?> {
  final Ref _ref;
  final String _projectId;
  final String _pluginId = FileExplorerPlugin().id;

  FileExplorerStateNotifier(this._ref, this._projectId) : super(null) {
    _initState();
  }

  Future<void> _initState() async {
    final project = _ref.read(appNotifierProvider).value?.currentProject;
    if (project == null || project.id != _projectId) return;

    // CORRECTED: Read service and pass it to project.
    final workspaceService = _ref.read(explorerWorkspaceServiceProvider);
    final pluginJson = await project.loadPluginState(
      _pluginId,
      workspaceService: workspaceService,
    );

    if (mounted) {
      state =
          pluginJson != null
              ? FileExplorerSettings.fromJson(pluginJson)
              : const FileExplorerSettings();
    }
  }

  void setViewMode(FileExplorerViewMode newMode) {
    if (state == null || state!.viewMode == newMode) return;
    state = state!.copyWith(viewMode: newMode);
    _persistStateIfNecessary();
  }

  void toggleFolderExpansion(String folderUri) {
    if (state == null) return;
    final newExpanded = Set<String>.from(state!.expandedFolders);
    if (newExpanded.contains(folderUri)) {
      newExpanded.remove(folderUri);
    } else {
      newExpanded.add(folderUri);
    }
    state = state!.copyWith(expandedFolders: newExpanded);
    _persistStateIfNecessary();
  }

  void _persistStateIfNecessary() {
    if (state == null) return;
    final project = _ref.read(appNotifierProvider).value?.currentProject;
    if (project == null || project.id != _projectId) return;

    // CORRECTED: Read service and pass it to project.
    final workspaceService = _ref.read(explorerWorkspaceServiceProvider);
    project.savePluginState(
      _pluginId,
      state!.toJson(),
      workspaceService: workspaceService,
    );
  }
}
