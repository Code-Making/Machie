// lib/explorer/explorer_plugin_registry.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../project/project_models.dart';
import 'explorer_plugin_models.dart';
import 'plugins/file_explorer/file_explorer_plugin.dart';
import 'plugins/file_explorer/file_explorer_state.dart';
import 'plugins/search_explorer/search_explorer_plugin.dart';
import 'services/explorer_service.dart';
import '../app/app_notifier.dart';

export 'explorer_plugin_models.dart';

final explorerRegistryProvider = Provider<List<ExplorerPlugin>>((ref) {
  return [
    FileExplorerPlugin(),
    SearchExplorerPlugin(),
  ];
});

final activeExplorerProvider = StateProvider<ExplorerPlugin>((ref) {
  return ref.watch(explorerRegistryProvider).first;
});

final activeExplorerSettingsProvider =
    Provider<ExplorerPluginSettings?>((ref) {
  final project = ref.watch(appNotifierProvider).value?.currentProject;
  final activePlugin = ref.watch(activeExplorerProvider);
  if (project == null || activePlugin.settings == null) {
    return null;
  }

  final pluginStateJson =
      project.workspace.pluginStates[activePlugin.id];
  if (pluginStateJson != null && pluginStateJson is Map<String, dynamic>) {
    if (activePlugin.id == 'com.machine.file_explorer') {
      return FileExplorerSettings.fromJson(pluginStateJson);
    }
  }
  return activePlugin.settings;
});

final activeExplorerNotifierProvider =
    Provider((ref) => ActiveExplorerNotifier(ref));

class ActiveExplorerNotifier {
  final Ref _ref;
  ActiveExplorerNotifier(this._ref);

  Future<void> updateSettings(
      ExplorerPluginSettings Function(ExplorerPluginSettings?) updater) async {
    final project = _ref.read(appNotifierProvider).value?.currentProject;
    final activePlugin = _ref.read(activeExplorerProvider);
    final explorerService = _ref.read(explorerServiceProvider);
    final appNotifier = _ref.read(appNotifierProvider.notifier);

    if (project == null || activePlugin.settings == null) return;

    final currentSettings = _ref.read(activeExplorerSettingsProvider);
    final newSettings = updater(currentSettings);

    final newProject = await explorerService.updateWorkspace(
      project,
      (w) {
        final newPluginStates = Map<String, dynamic>.from(w.pluginStates);
        newPluginStates[activePlugin.id] = newSettings.toJson();
        return w.copyWith(pluginStates: newPluginStates);
      },
    );
    
    // REFACTOR: Call the new, generic update method.
    appNotifier.updateCurrentProject(newProject);
  }
}