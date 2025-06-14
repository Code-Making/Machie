// lib/plugins/plugin_registry.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'plugin_models.dart'; // For EditorPlugin
import 'code_editor/code_editor_plugin.dart';
import 'recipe_tex/recipe_tex_plugin.dart'; // NEW IMPORT

// --------------------
// Plugin Registry Providers
// --------------------

/// Manages the set of all available EditorPlugins in the application.
/// Plugins register themselves here.
final pluginRegistryProvider = Provider<Set<EditorPlugin>>(
  (_) => {
      CodeEditorPlugin(),
      RecipeTexPlugin(), // NEW: Register the RecipeTexPlugin
  },
);

final activePluginsProvider =
    StateNotifierProvider<PluginManager, Set<EditorPlugin>>((ref) {
      return PluginManager(ref.read(pluginRegistryProvider));
    });

// --------------------
//   Plugin Registry
// --------------------

class PluginManager extends StateNotifier<Set<EditorPlugin>> {
  PluginManager(super.plugins);

  void registerPlugin(EditorPlugin plugin) => state = {...state, plugin};
  void unregisterPlugin(EditorPlugin plugin) =>
      state = state.where((p) => p != plugin).toSet();
}