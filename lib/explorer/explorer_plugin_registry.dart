// lib/explorer/explorer_plugin_registry.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app/app_notifier.dart';
import '../projecprproject_models.dart';
import '../project/local_file_system_project.dart';
import '../project/workspace_service.dart';
import 'explorer_plugin_models.dart';
import 'plugins/file_explorer/file_explorer_plugin.dart';

final explorerRegistryProvider = Provider<List<ExplorerPlugin>>((ref) {
  return [
    FileExplorerPlugin(),
  ];
});

// MODIFIED: This provider now initializes from and saves to the WorkspaceService.
final activeExplorerProvider =
    StateNotifierProvider.autoDispose<ActiveExplorerNotifier, ExplorerPlugin>((ref) {
  final project = ref.watch(appNotifierProvider.select((s) => s.value?.currentProject));
  final registry = ref.read(explorerRegistryProvider);

  if (project == null) {
    return ActiveExplorerNotifier(ref, registry.first);
  }
  // Initialize asynchronously.
  return ActiveExplorerNotifier(ref, registry.first, project: project);
});

class ActiveExplorerNotifier extends StateNotifier<ExplorerPlugin> {
  final Ref _ref;
  final Project? _project;

  ActiveExplorerNotifier(this._ref, ExplorerPlugin defaultPlugin, {Project? project})
      : _project = project,
        super(defaultPlugin) {
    _initState();
  }

  Future<void> _initState() async {
    final project = _project;
    if (project is LocalProject) {
      final workspaceService = _ref.read(workspaceServiceProvider);
      // This is a bit inefficient as it reads the whole file, but it's okay for now.
      // A better implementation might have `workspaceService.loadActiveExplorerId()`.
      final fullState = await workspaceService.loadPluginState(
          project.fileHandler, project.projectDataPath, "dummy"); // hack to read
      if (fullState != null) {
          final registry = _ref.read(explorerRegistryProvider);
          final activeId = fullState['activeExplorerPluginId'];
          final activePlugin =
              registry.firstWhere((p) => p.id == activeId, orElse: () => registry.first);
          if (mounted) state = activePlugin;
      }
    }
  }

  void setActiveExplorer(ExplorerPlugin newPlugin) {
    if (state.id == newPlugin.id) return;
    state = newPlugin;
    final project = _project;
    if (project is LocalProject) {
      final workspaceService = _ref.read(workspaceServiceProvider);
      workspaceService.saveActiveExplorer(
        project.fileHandler,
        project.projectDataPath,
        newPlugin.id,
      );
    }
  }
}