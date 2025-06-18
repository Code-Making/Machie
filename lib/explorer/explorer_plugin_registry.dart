// lib/explorer/explorer_plugin_registry.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../project/project_models.dart';
import '../project/workspace_service.dart';
import 'explorer_plugin_models.dart';
import 'plugins/file_explorer/file_explorer_plugin.dart';
import 'plugins/search_explorer/search_explorer_plugin.dart'; // NEW IMPORT

final explorerRegistryProvider = Provider<List<ExplorerPlugin>>((ref) {
  return [
    FileExplorerPlugin(),
    SearchExplorerPlugin(), // NEW: Register the search plugin
  ];
});

// MODIFIED: This is now a simple StateProvider. It holds the current
// active plugin, but the logic to initialize it is moved to the UI.
final activeExplorerProvider = StateProvider.autoDispose<ExplorerPlugin>((ref) {
  // Default to the first registered explorer. The UI will override this
  // with the persisted value upon initialization.
  return ref.watch(explorerRegistryProvider).first;
});

class ActiveExplorerNotifier extends StateNotifier<ExplorerPlugin> {
  final Ref _ref;
  final Project? _project;

  ActiveExplorerNotifier(
    this._ref,
    ExplorerPlugin defaultPlugin, {
    Project? project,
  }) : _project = project,
       super(defaultPlugin) {
    _initState();
  }

  Future<void> _initState() async {
    final project = _project;
    if (project != null) {
      final workspaceService = _ref.read(workspaceServiceProvider);
      // This is a bit inefficient as it reads the whole file, but it's okay for now.
      // A better implementation might have `workspaceService.loadActiveExplorerId()`.
      final fullState = await workspaceService.loadPluginState(
        project.fileHandler,
        project.projectDataPath,
        "dummy",
      ); // hack to read
      if (fullState != null) {
        final registry = _ref.read(explorerRegistryProvider);
        final activeId = fullState['activeExplorerPluginId'];
        final activePlugin = registry.firstWhere(
          (p) => p.id == activeId,
          orElse: () => registry.first,
        );
        if (mounted) state = activePlugin;
      }
    }
  }

  void setActiveExplorer(ExplorerPlugin newPlugin) {
    if (state.id == newPlugin.id) return;
    state = newPlugin;
    final project = _project;
    if (project != null) {
      final workspaceService = _ref.read(workspaceServiceProvider);
      workspaceService.saveActiveExplorer(
        project.fileHandler,
        project.projectDataPath,
        newPlugin.id,
      );
    }
  }
}
