// lib/project/project_models.dart
import '../session/session_models.dart';
import '../data/file_handler/file_handler.dart';

// --- Enums ---
enum ProjectType { local } // Ready for future types like 'remoteSsh'

enum FileExplorerViewMode {
  sortByNameAsc,
  sortByNameDesc,
  sortByDateModified,
}


// --- Models ---

// Lightweight reference to a project, stored in global app state.
class ProjectMetadata {
  final String id;
  final String name;
  final String rootUri;
  final ProjectType projectType;
  final DateTime lastOpenedDateTime;

  ProjectMetadata({
    required this.id,
    required this.name,
    required this.rootUri,
    this.projectType = ProjectType.local,
    required this.lastOpenedDateTime,
  });

  // Serialization for SharedPreferences
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'rootUri': rootUri,
        'projectType': projectType.name,
        'lastOpenedDateTime': lastOpenedDateTime.toIso8601String(),
      };

  factory ProjectMetadata.fromJson(Map<String, dynamic> json) => ProjectMetadata(
        id: json['id'],
        name: json['name'],
        rootUri: json['rootUri'],
        projectType: ProjectType.values.firstWhere(
          (e) => e.name == json['projectType'],
          orElse: () => ProjectType.local,
        ),
        lastOpenedDateTime: DateTime.parse(json['lastOpenedDateTime']),
      );
}

// Abstract base class for all project types.
abstract class Project {
  ProjectMetadata metadata;
  FileHandler fileHandler;
  SessionState session;

  Project({
    required this.metadata,
    required this.fileHandler,
    required this.session,
  });

  String get id => metadata.id;
  String get name => metadata.name;
  String get rootUri => metadata.rootUri;
}

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
      fileHandler: fileHandler, // File handler is immutable per project instance
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

