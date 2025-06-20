// lib/explorer/plugins/file_explorer/file_explorer_state.dart
import '../../explorer_plugin_models.dart'; // REFACTOR: Import new base class

enum FileExplorerViewMode { sortByNameAsc, sortByNameDesc, sortByDateModified }

// REFACTOR: The model now implements the abstract settings class.
class FileExplorerSettings implements ExplorerPluginSettings {
  final FileExplorerViewMode viewMode;
  final Set<String> expandedFolders;

  FileExplorerSettings({ // REFACTOR: Make constructor const
    this.viewMode = FileExplorerViewMode.sortByNameAsc,
    this.expandedFolders = const {},
  });

  FileExplorerSettings copyWith({
    FileExplorerViewMode? viewMode,
    Set<String>? expandedFolders,
  }) {
    return FileExplorerSettings(
      viewMode: viewMode ?? this.viewMode,
      expandedFolders: expandedFolders ?? this.expandedFolders,
    );
  }

  // REFACTOR: `fromJson` is now a factory constructor.
  factory FileExplorerSettings.fromJson(Map<String, dynamic> json) {
    return FileExplorerSettings(
      viewMode: FileExplorerViewMode.values.firstWhere(
        (e) => e.name == json['viewMode'],
        orElse: () => FileExplorerViewMode.sortByNameAsc,
      ),
      expandedFolders: Set<String>.from(json['expandedFolders'] ?? []),
    );
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    // This is not the ideal way to handle immutability, but it fits the abstract
    // class contract. A better approach might use a copyWith factory in the abstract class.
    // For now, this is a no-op as we use the factory constructor.
  }

  @override
  Map<String, dynamic> toJson() => {
        'viewMode': viewMode.name,
        'expandedFolders': expandedFolders.toList(),
      };
}

// REFACTOR: The specific StateNotifier and Provider for file explorer state
// have been REMOVED. They are replaced by the generic activeExplorerStateProvider
// in explorer_plugin_registry.dart.