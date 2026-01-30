import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../editor/plugins/editor_plugin_registry.dart';
import '../explorer/explorer_plugin_registry.dart';

export 'settings_models.dart';
export '../project/project_settings_notifier.dart';

// FIX: NotifierProvider expects a constructor reference or a builder without arguments
// if the Notifier itself has no arguments and initializes state via build().
// Or, if it takes arguments, it would be a FamilyNotifierProvider.
// Here, SettingsNotifier will get its dependencies via ref.watch in its build method.
final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends Notifier<AppSettings> {
  // FIX: Remove constructor parameters and the super call.
  // The initial state is now provided by the `build` method.
  // The constructor is implicitly `SettingsNotifier();`
  // We remove the explicit constructor that took `plugins` and `explorerPlugins`
  // because those dependencies are now watched directly within the `build` method.

  // FIX: Implement the `build` method as required by `Notifier`.
  @override
  AppSettings build() {
    // Watch dependencies directly within the build method.
    final plugins = ref.watch(activePluginsProvider);
    final explorerPlugins = ref.watch(explorerRegistryProvider);

    // Initialize the default state synchronously.
    final initialSettings = AppSettings(
      pluginSettings: _getDefaultSettings(plugins),
      explorerPluginSettings: _getDefaultExplorerSettings(explorerPlugins),
    );

    // Schedule the async settings loading to happen after the initial state
    // has been returned and the notifier is fully built.
    // This maintains the original behavior of loading settings after
    // the initial default state is set.
    Future.microtask(() {
      loadSettings();
    });

    return initialSettings;
  }

  static Map<Type, MachineSettings> _getDefaultSettings(
    List<EditorPlugin> plugins,
  ) {
    final Map<Type, MachineSettings> defaultSettings = {
      GeneralSettings: GeneralSettings(),
    };
    for (final plugin in plugins) {
      if (plugin.settings != null) {
        defaultSettings[plugin.settings.runtimeType] = plugin.settings!;
      }
    }
    return defaultSettings;
  }

  // CHANGED: Returns Map<String, MachineSettings>
  static Map<String, MachineSettings> _getDefaultExplorerSettings(
    List<ExplorerPlugin> explorerPlugins,
  ) {
    final Map<String, MachineSettings> defaultSettings = {};
    for (final plugin in explorerPlugins) {
      if (plugin.settings != null) {
        // Assuming ExplorerPluginSettings implements MachineSettings
        defaultSettings[plugin.id] = plugin.settings as MachineSettings;
      }
    }
    return defaultSettings;
  }

  void updatePluginSettings(MachineSettings newSettings) {
    final updatedSettings = Map<Type, MachineSettings>.from(
      state.pluginSettings,
    )..[newSettings.runtimeType] = newSettings;
    state = state.copyWith(pluginSettings: updatedSettings);
    _saveSettings();
  }

  // CHANGED: Signature uses MachineSettings
  void updateExplorerPluginSettings(
    String pluginId,
    MachineSettings newSettings,
  ) {
    final updatedSettings = Map<String, MachineSettings>.from(
      state.explorerPluginSettings,
    )..[pluginId] = newSettings;
    state = state.copyWith(explorerPluginSettings: updatedSettings);
    _saveSettings();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final settingsMap = state.pluginSettings.map(
      (type, settings) => MapEntry(type.toString(), settings.toJson()),
    );
    await prefs.setString('app_settings', jsonEncode(settingsMap));

    final explorerSettingsMap = state.explorerPluginSettings.map(
      (id, settings) => MapEntry(id, settings.toJson()),
    );
    await prefs.setString('explorer_settings', jsonEncode(explorerSettingsMap));
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final settingsJson = prefs.getString('app_settings');

    if (settingsJson != null) {
      final decoded = jsonDecode(settingsJson) as Map<String, dynamic>;
      final newSettings = Map<Type, MachineSettings>.from(state.pluginSettings);

      for (final entry in decoded.entries) {
        final typeString = entry.key;
        final settingsInstance = newSettings.values.firstWhereOrNull(
          (s) => s.runtimeType.toString() == typeString,
        );

        if (settingsInstance != null) {
          settingsInstance.fromJson(entry.value);
          newSettings[settingsInstance.runtimeType] = settingsInstance;
        }
      }
      state = state.copyWith(pluginSettings: newSettings);
    }

    final explorerSettingsJson = prefs.getString('explorer_settings');
    if (explorerSettingsJson != null) {
      final decoded = jsonDecode(explorerSettingsJson) as Map<String, dynamic>;
      // CHANGED: Map<String, MachineSettings>
      final newExplorerSettings = Map<String, MachineSettings>.from(
        state.explorerPluginSettings,
      );

      for (final entry in decoded.entries) {
        final pluginId = entry.key;
        if (newExplorerSettings.containsKey(pluginId)) {
          newExplorerSettings[pluginId]!.fromJson(entry.value);
        }
      }
      state = state.copyWith(explorerPluginSettings: newExplorerSettings);
    }
  }
}