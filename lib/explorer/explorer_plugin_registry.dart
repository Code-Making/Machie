// lib/explorer/explorer_plugin_registry.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'explorer_plugin_models.dart';
import 'plugins/file_explorer/file_explorer_plugin.dart';
import 'plugins/search_explorer/search_explorer_plugin.dart';

export 'explorer_plugin_models.dart';

final explorerRegistryProvider = Provider<List<ExplorerPlugin>>((ref) {
  return [
    FileExplorerPlugin(),
    SearchExplorerPlugin(),
  ];
});

// REFACTOR: This is now a simple StateProvider. Its initial value is set by the
// ExplorerHostView when a project is loaded, based on the persisted state.
final activeExplorerProvider = StateProvider<ExplorerPlugin>((ref) {
  // Default to the first registered explorer. The UI will override this
  // with the persisted value upon initialization.
  return ref.watch(explorerRegistryProvider).first;
});