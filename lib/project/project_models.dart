// lib/project/project_models.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../plugins/plugin_models.dart';
import '../session/session_models.dart';
import '../data/file_handler/file_handler.dart';

// --- Enums ---
enum ProjectType { local } // Ready for future types like 'remoteSsh'

enum FileExplorerViewMode { sortByNameAsc, sortByNameDesc, sortByDateModified }

// --- Models ---

// Lightweight reference to a project, stored in global app state.
class ProjectMetadata {
  // ... (no changes here) ...
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

  // NEW: Lifecycle methods defining the contract for all project types.
  Future<void> save();
  // MODIFIED: Signature now requires a Ref to pass down to plugins.
  Future<void> close({required Ref ref});

  // NEW: Session manipulation methods, returning a new immutable Project instance.
  // The responsibility for this logic is moved from SessionService to here.
  Future<Project> openFile(DocumentFile file, {EditorPlugin? plugin, required Ref ref});
  Project switchTab(int index, {required Ref ref});
  Project reorderTabs(int oldIndex, int newIndex);
  Future<Project> saveTab(int tabIndex);
  Project closeTab(int index, {required Ref ref});
  Project markCurrentTabDirty();
  Project updateTab(int tabIndex, EditorTab newTab);
}