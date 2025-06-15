// lib/plugins/plugin_registry.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'plugin_models.dart';
import 'code_editor/code_editor_plugin.dart';
import 'glitch_editor/glitch_editor_plugin.dart'; // NEW IMPORT

final pluginRegistryProvider = Provider<Set<EditorPlugin>>(
  (_) => {
      CodeEditorPlugin(),
      GlitchEditorPlugin(), // NEW: Register the GlitchEditorPlugin
  },
);

final activePluginsProvider =
    StateNotifierProvider<PluginManager, Set<EditorPlugin>>((ref) {
      return PluginManager(ref.read(pluginRegistryProvider));
    });

class PluginManager extends StateNotifier<Set<EditorPlugin>> {
  PluginManager(super.plugins);
  void registerPlugin(EditorPlugin plugin) => state = {...state, plugin};
  void unregisterPlugin(EditorPlugin plugin) =>
      state = state.where((p) => p != plugin).toSet();
}