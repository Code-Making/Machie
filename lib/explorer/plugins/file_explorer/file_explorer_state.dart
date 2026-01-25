// FILE: lib/explorer/plugins/file_explorer/file_explorer_state.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../explorer_plugin_models.dart';

enum FileExplorerViewMode { sortByNameAsc, sortByNameDesc, sortByDateModified }

// CONFIGURATION: Persisted globally in AppSettings.json
class FileExplorerSettings implements ExplorerPluginSettings {
  final FileExplorerViewMode viewMode;
  // REMOVED: expandedFolders (This is state, not a setting)

  FileExplorerSettings({this.viewMode = FileExplorerViewMode.sortByNameAsc});

  FileExplorerSettings copyWith({FileExplorerViewMode? viewMode}) {
    return FileExplorerSettings(viewMode: viewMode ?? this.viewMode);
  }

  factory FileExplorerSettings.fromJson(Map<String, dynamic> json) {
    return FileExplorerSettings(
      viewMode: FileExplorerViewMode.values.firstWhere(
        (e) => e.name == json['viewMode'],
        orElse: () => FileExplorerViewMode.sortByNameAsc,
      ),
    );
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    // Handled by factory/constructor in this architecture
  }

  @override
  Map<String, dynamic> toJson() => {'viewMode': viewMode.name};

  @override
  FileExplorerSettings clone() {
    return FileExplorerSettings(viewMode: viewMode);
  }
}

// STATE: Kept in memory (or persisted separately via ProjectDto later)
class FileExplorerExpansionNotifier extends StateNotifier<Set<String>> {
  FileExplorerExpansionNotifier() : super({});

  void toggle(String uri, bool isExpanded) {
    if (isExpanded) {
      state = {...state, uri};
    } else {
      state = {...state}..remove(uri);
    }
  }

  void collapseAll() {
    state = {};
  }
}

// A dedicated provider for expansion state.
// Lightweight, in-memory, does NOT trigger disk writes.
final fileExplorerExpandedFoldersProvider = StateNotifierProvider.autoDispose<
  FileExplorerExpansionNotifier,
  Set<String>
>((ref) {
  return FileExplorerExpansionNotifier();
});
