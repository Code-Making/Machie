// lib/project/project_models.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../editors/plugins/plugin_models.dart';
import '../editors/editor_tab_models.dart';
import '../data/file_handler/file_handler.dart';
import '../explorer/explorer_workspace_service.dart';

// --- Models ---

class ProjectMetadata {
  final String id;
  final String name;
  final String rootUri;
  final String projectTypeId; // MODIFIED: from ProjectType to String
  final DateTime lastOpenedDateTime;

  ProjectMetadata({
    required this.id,
    required this.name,
    required this.rootUri,
    required this.projectTypeId, // MODIFIED
    required this.lastOpenedDateTime,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'rootUri': rootUri,
    'projectTypeId': projectTypeId, // MODIFIED
    'lastOpenedDateTime': lastOpenedDateTime.toIso8601String(),
  };

  factory ProjectMetadata.fromJson(Map<String, dynamic> json) =>
      ProjectMetadata(
        id: json['id'],
        name: json['name'],
        rootUri: json['rootUri'],
        projectTypeId: json['projectTypeId'], // MODIFIED
        lastOpenedDateTime: DateTime.parse(json['lastOpenedDateTime']),
      );
}

abstract class Project {
  ProjectMetadata metadata;
  FileHandler fileHandler;
  TabSessionState session;

  Project({
    required this.metadata,
    required this.fileHandler,
    required this.session,
  });

  String get id => metadata.id;
  String get name => metadata.name;
  String get rootUri => metadata.rootUri;
  String get projectTypeId =>
      metadata.projectTypeId; // NEW: Expose the type ID.

  Map<String, dynamic> toJson();

  Future<void> save();
  Future<void> close({required Ref ref});

  Future<Map<String, dynamic>?> loadPluginState(
    String pluginId, {
    required ExplorerWorkspaceService workspaceService,
  });
  Future<void> savePluginState(
    String pluginId,
    Map<String, dynamic> stateJson, {
    required ExplorerWorkspaceService workspaceService,
  });
  Future<void> saveActiveExplorer(
    String pluginId, {
    required ExplorerWorkspaceService workspaceService,
  });
  Future<String?> loadActiveExplorer({
    required ExplorerWorkspaceService workspaceService,
  });

  Future<Project> openFile(
    DocumentFile file, {
    EditorPlugin? plugin,
    required Ref ref,
  });
  Project switchTab(int index, {required Ref ref});
  Project reorderTabs(int oldIndex, int newIndex);
  Project closeTab(int index, {required Ref ref});
  Project updateTab(int tabIndex, EditorTab newTab);
}