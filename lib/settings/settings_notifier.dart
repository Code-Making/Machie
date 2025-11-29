// FILE: lib/settings/settings_notifier.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';

import '../editor/plugins/editor_plugin_registry.dart';
import '../explorer/explorer_plugin_registry.dart';
import 'settings_models.dart';

export 'settings_models.dart';
export '../project/project_settings_notifier.dart';

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((
  ref,
) {
  final plugins = ref.watch(activePluginsProvider);
  final explorerPlugins = ref.watch(explorerRegistryProvider);
  return SettingsNotifier(plugins: plugins, explorerPlugins: explorerPlugins);
});

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier({
    required List<EditorPlugin> plugins,
    required List<ExplorerPlugin> explorerPlugins,
  }) : super(
          AppSettings(
            pluginSettings: _getDefaultSettings(plugins),
            explorerPluginSettings:
                _getDefaultExplorerSettings(explorerPlugins),
          ),
        ) {
    loadSettings();
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
      String pluginId, MachineSettings newSettings) {
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
          state.explorerPluginSettings);

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