// lib/settings/settings_notifier.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../editor/plugins/plugin_registry.dart';
import 'settings_models.dart';

export 'settings_models.dart';

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((
  ref,
) {
  final plugins = ref.watch(activePluginsProvider);
  return SettingsNotifier(plugins: plugins);
});

class SettingsNotifier extends StateNotifier<AppSettings> {
  final Set<EditorPlugin> _plugins;

  SettingsNotifier({required Set<EditorPlugin> plugins})
      : _plugins = plugins,
        super(AppSettings(pluginSettings: _getDefaultSettings(plugins))) {
    loadSettings();
  }

  static Map<Type, PluginSettings> _getDefaultSettings(
    Set<EditorPlugin> plugins,
  ) {
    final defaultSettings = {
      // REFACTOR: Add GeneralSettings to the default map.
      GeneralSettings: GeneralSettings(),
    };
    for (final plugin in plugins) {
      if (plugin.settings != null) {
        defaultSettings[plugin.settings.runtimeType] = plugin.settings!;
      }
    }
    return defaultSettings;
  }

  void updatePluginSettings(PluginSettings newSettings) {
    final updatedSettings = Map<Type, PluginSettings>.from(state.pluginSettings)
      ..[newSettings.runtimeType] = newSettings;
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
      final newSettings = Map<Type, PluginSettings>.from(state.pluginSettings);

      // REFACTOR: Update loading logic to be more robust.
      for (final entry in decoded.entries) {
        final typeString = entry.key;
        final settingsInstance = newSettings.values.firstWhere(
          (s) => s.runtimeType.toString() == typeString,
          orElse: () => GeneralSettings(), // Fallback, though should not be needed
        );
        settingsInstance.fromJson(entry.value);
        newSettings[settingsInstance.runtimeType] = settingsInstance;
      }
      state = state.copyWith(pluginSettings: newSettings);
    }
  }
}