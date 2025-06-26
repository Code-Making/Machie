// =========================================
// FILE: lib/project/project_models.dart
// =========================================

import 'package:flutter/foundation.dart';
import '../editor/editor_tab_models.dart';
import '../editor/plugins/plugin_models.dart'; // ADDED for EditorPlugin
import '../explorer/explorer_workspace_state.dart';
import '../data/file_handler/file_handler.dart';
import '../editor/tab_state_manager.dart';
import 'package:machine/data/dto/project_dto.dart'; // ADDED


// ... (IncompleteDocumentFile and ProjectMetadata are unchanged) ...
class IncompleteDocumentFile implements DocumentFile {
  @override
  final String uri;
  IncompleteDocumentFile({required this.uri});

  @override
  String get name => '';
  @override
  bool get isDirectory => false;
  @override
  int get size => 0;
  @override
  DateTime get modifiedDate => DateTime.fromMillisecondsSinceEpoch(0);
  @override
  String get mimeType => 'application/octet-stream';
}

@immutable
class ProjectMetadata {
  final String id;
  final String name;
  final String rootUri;
  final String projectTypeId;
  final DateTime lastOpenedDateTime;

  const ProjectMetadata({
    required this.id,
    required this.name,
    required this.rootUri,
    required this.projectTypeId,
    required this.lastOpenedDateTime,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'rootUri': rootUri,
    'projectTypeId': projectTypeId,
    'lastOpenedDateTime': lastOpenedDateTime.toIso8601String(),
  };

  factory ProjectMetadata.fromJson(Map<String, dynamic> json) =>
      ProjectMetadata(
        id: json['id'],
        name: json['name'],
        rootUri: json['rootUri'],
        projectTypeId: json['projectTypeId'],
        lastOpenedDateTime: DateTime.parse(json['lastOpenedDateTime']),
      );
}

@immutable
class Project {
  final ProjectMetadata metadata;
  final TabSessionState session;
  final ExplorerWorkspaceState workspace;

  const Project({
    required this.metadata,
    required this.session,
    required this.workspace,
  });

  String get id => metadata.id;
  String get name => metadata.name;
  String get rootUri => metadata.rootUri;
  String get projectTypeId => metadata.projectTypeId;

  factory Project.fresh(ProjectMetadata metadata) {
    return Project(
      metadata: metadata,
      session: const TabSessionState(),
      workspace: const ExplorerWorkspaceState(
        activeExplorerPluginId: 'com.machine.file_explorer',
      ),
    );
  }

  Project copyWith({
    ProjectMetadata? metadata,
    TabSessionState? session,
    ExplorerWorkspaceState? workspace,
  }) {
    return Project(
      metadata: metadata ?? this.metadata,
      session: session ?? this.session,
      workspace: workspace ?? this.workspace,
    );
  }

  ProjectDto toDto(Map<String, TabMetadata> liveMetadata) {
    return ProjectDto(
      session: session.toDto(liveMetadata),
      workspace: workspace.toDto(),
    );
  }
}