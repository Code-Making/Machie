// lib/settings/settings_notifier.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../editor/plugins/plugin_registry.dart';
import 'settings_models.dart';

import 'package:collection/collection.dart'; // Import for firstWhereOrNull

export 'settings_models.dart';

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((
  ref,
) {
  final plugins = ref.watch(activePluginsProvider);
  return SettingsNotifier(plugins: plugins);
});

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier({required List<EditorPlugin> plugins})
    : super(AppSettings(pluginSettings: _getDefaultSettings(plugins))) {
    loadSettings();
  }

  static Map<Type, MachineSettings> _getDefaultSettings(
    List<EditorPlugin> plugins,
  ) {
    // REFACTOR: Use the new base class for the map type.
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

  void updatePluginSettings(MachineSettings newSettings) {
    // REFACTOR: Use the new base class for the map type.
    final updatedSettings = Map<Type, MachineSettings>.from(
      state.pluginSettings,
    )..[newSettings.runtimeType] = newSettings;
    state = state.copyWith(pluginSettings: updatedSettings);
    _saveSettings();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final settingsMap = state.pluginSettings.map(
      (type, settings) => MapEntry(type.toString(), settings.toJson()),
    );
    await prefs.setString('app_settings', jsonEncode(settingsMap));
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final settingsJson = prefs.getString('app_settings');

    if (settingsJson != null) {
      final decoded = jsonDecode(settingsJson) as Map<String, dynamic>;
      // REFACTOR: Use the new base class for the map type.
      final newSettings = Map<Type, MachineSettings>.from(state.pluginSettings);

      for (final entry in decoded.entries) {
        final typeString = entry.key;
        // REFACTOR: Correctly look up the settings instance from the default map.
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
  }
}
