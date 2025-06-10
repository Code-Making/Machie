// lib/project/local_file_system_project.dart

import '../session/session_models.dart';
import 'project_models.dart';

// Concrete implementation for projects on the local device file system.
class LocalProject extends Project {
  String projectDataPath;
  Set<String> expandedFolders;
  FileExplorerViewMode fileExplorerViewMode;

  LocalProject({
    required super.metadata,
    required super.fileHandler,
    required super.session,
    required this.projectDataPath,
    this.expandedFolders = const {},
    this.fileExplorerViewMode = FileExplorerViewMode.sortByNameAsc,
  });

  LocalProject copyWith({
    ProjectMetadata? metadata,
    SessionState? session,
    Set<String>? expandedFolders,
    FileExplorerViewMode? fileExplorerViewMode,
  }) {
    return LocalProject(
      metadata: metadata ?? this.metadata,
      fileHandler:
          fileHandler, // File handler is immutable per project instance
      session: session ?? this.session.copyWith(),
      projectDataPath: projectDataPath,
      expandedFolders: expandedFolders ?? Set.from(this.expandedFolders),
      fileExplorerViewMode: fileExplorerViewMode ?? this.fileExplorerViewMode,
    );
  }

  // Serialization for .machine/project_data.json
  Map<String, dynamic> toJson() => {
    'id': metadata.id, // For verification
    'session': session.toJson(),
    'expandedFolders': expandedFolders.toList(),
    'fileExplorerViewMode': fileExplorerViewMode.name,
  };
}
