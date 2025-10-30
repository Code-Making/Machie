// =========================================
// UPDATED: lib/editor/plugins/plugin_registry.dart
// =========================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'plugin_models.dart';
import 'code_editor/code_editor_plugin.dart';
import 'glitch_editor/glitch_editor_plugin.dart';
import 'recipe_tex/recipe_tex_plugin.dart';
import 'llm_editor/llm_editor_plugin.dart';
import 'refactor_editor/refactor_editor_plugin.dart'; // <-- 1. IMPORT THE NEW PLUGIN
export 'plugin_models.dart';

final pluginRegistryProvider = Provider<Set<EditorPlugin>>(
  (_) => {
    CodeEditorPlugin(),
    GlitchEditorPlugin(),
    RecipeTexPlugin(),
    LlmEditorPlugin(),
    RefactorEditorPlugin(),
  },
);

final activePluginsProvider =
    StateNotifierProvider<PluginManager, List<EditorPlugin>>((ref) {
      final initialPlugins = ref.read(pluginRegistryProvider);
      return PluginManager(initialPlugins);
    });

class PluginManager extends StateNotifier<List<EditorPlugin>> {
  PluginManager(Set<EditorPlugin> plugins)
    : super(_sortPlugins(plugins.toList()));

  static List<EditorPlugin> _sortPlugins(List<EditorPlugin> plugins) {
    // Sorts plugins in descending order of priority.
    plugins.sort((a, b) => b.priority.compareTo(a.priority));
    return plugins;
  }

  void registerPlugin(EditorPlugin plugin) {
    state = _sortPlugins([...state, plugin]);
  }

  void unregisterPlugin(EditorPlugin plugin) {
    state = _sortPlugins(state.where((p) => p != plugin).toList());
  }
}
