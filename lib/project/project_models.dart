// lib/project/project_models.dart
import '../session/session_models.dart';
import '../data/file_handler/file_handler.dart';

// --- Enums ---
enum ProjectType { local } // Ready for future types like 'remoteSsh'

enum FileExplorerViewMode { sortByNameAsc, sortByNameDesc, sortByDateModified }

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

  factory ProjectMetadata.fromJson(Map<String, dynamic> json) =>
      ProjectMetadata(
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
