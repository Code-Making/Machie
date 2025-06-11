// lib/explorer/explorer_plugin_registry.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'explorer_plugin_models.dart';
import 'plugins/file_explorer/file_explorer_plugin.dart';

/// A registry of all available explorer plugins in the application.
/// To add a new explorer, simply add it to this list.
final explorerRegistryProvider = Provider<List<ExplorerPlugin>>((ref) {
  return [
    FileExplorerPlugin(),
    // Future plugins would be added here:
    // GitExplorerPlugin(),
    // SearchExplorerPlugin(),
  ];
});

/// A provider that holds the currently active explorer plugin.
/// The UI will watch this provider to decide which explorer to display.
final activeExplorerProvider = StateProvider<ExplorerPlugin>((ref) {
  // Default to the first registered explorer (which should be the file explorer).
  return ref.watch(explorerRegistryProvider).first;
});