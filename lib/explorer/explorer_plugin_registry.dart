// FILE: lib/explorer/explorer_plugin_registry.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'explorer_plugin_models.dart';
import 'plugins/file_explorer/file_explorer_plugin.dart';
import 'plugins/git_explorer/git_explorer_plugin.dart';
import 'plugins/search_explorer/search_explorer_plugin.dart';

// Keep for other logic if needed
import '../settings/settings_notifier.dart'; // Import settings

export 'explorer_plugin_models.dart';

final explorerRegistryProvider = Provider<List<ExplorerPlugin>>((ref) {
  return [FileExplorerPlugin(), SearchExplorerPlugin(), GitExplorerPlugin()];
});

final activeExplorerProvider = StateProvider<ExplorerPlugin>((ref) {
  return ref.watch(explorerRegistryProvider).first;
});

// FIX: Read settings from the global settingsProvider
final activeExplorerSettingsProvider = Provider<ExplorerPluginSettings?>((ref) {
  final activePlugin = ref.watch(activeExplorerProvider);
  final appSettings = ref.watch(settingsProvider);

  if (appSettings.explorerPluginSettings.containsKey(activePlugin.id)) {
    return appSettings.explorerPluginSettings[activePlugin.id]
        as ExplorerPluginSettings;
  }

  return activePlugin.settings;
});

final activeExplorerNotifierProvider = Provider(
  (ref) => ActiveExplorerNotifier(ref),
);

class ActiveExplorerNotifier {
  final Ref _ref;
  ActiveExplorerNotifier(this._ref);

  Future<void> updateSettings(
    ExplorerPluginSettings Function(ExplorerPluginSettings?) updater,
  ) async {
    final activePlugin = _ref.read(activeExplorerProvider);

    // FIX: Forward updates to the global SettingsNotifier
    // This maintains backward compatibility if other code uses this notifier
    final currentSettings = _ref.read(activeExplorerSettingsProvider);
    final newSettings = updater(currentSettings);

    _ref
        .read(settingsProvider.notifier)
        .updateExplorerPluginSettings(
          activePlugin.id,
          newSettings as MachineSettings,
        );
  }
}
