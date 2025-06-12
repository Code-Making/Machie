// lib/project/workspace_state.dart
import 'package:flutter/foundation.dart';
import 'project_models.dart';

@immutable
class WorkspaceState {
  final Set<String> expandedFolders;
  final FileExplorerViewMode fileExplorerViewMode;

  const WorkspaceState({
    this.expandedFolders = const {},
    this.fileExplorerViewMode = FileExplorerViewMode.sortByNameAsc,
  });

  WorkspaceState copyWith({
    Set<String>? expandedFolders,
    FileExplorerViewMode? fileExplorerViewMode,
  }) {
    return WorkspaceState(
      expandedFolders: expandedFolders ?? this.expandedFolders,
      fileExplorerViewMode: fileExplorerViewMode ?? this.fileExplorerViewMode,
    );
  }

  factory WorkspaceState.fromJson(Map<String, dynamic> json) {
    return WorkspaceState(
      expandedFolders: Set<String>.from(json['expandedFolders'] ?? []),
      fileExplorerViewMode: FileExplorerViewMode.values.firstWhere(
        (e) => e.name == json['fileExplorerViewMode'],
        orElse: () => FileExplorerViewMode.sortByNameAsc,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'expandedFolders': expandedFolders.toList(),
        'fileExplorerViewMode': fileExplorerViewMode.name,
      };
}