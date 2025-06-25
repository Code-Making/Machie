// =========================================
// FILE: lib/project/project_models.dart
// =========================================

import 'package:flutter/foundation.dart';
import '../editor/editor_tab_models.dart';
import '../explorer/explorer_workspace_state.dart';
import '../data/file_handler/file_handler.dart';

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

  // ... (getters and copyWith are unchanged) ...
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

  Map<String, dynamic> toJson() => {
    'session': session.toJson(),
    'workspace': workspace.toJson(),
  };

  // REFACTORED: This now constructs the project by deserializing the session
  // into a temporary object. The EditorService will replace it.
  factory Project.fromJson(Map<String, dynamic> json) {
    // Manually deserialize session data here.
    final sessionJson = json['session'] as Map<String, dynamic>? ?? {};
    final tabsJson = sessionJson['tabs'] as List<dynamic>? ?? [];
    final metadataJson = sessionJson['tabMetadata'] as Map<String, dynamic>? ?? {};

    // Create a temporary "persisted" session state.
    final persistedSession = TabSessionState(
      tabs: tabsJson.map((t) => PersistedEditorTab(t as Map<String, dynamic>)).toList(),
      currentTabIndex: sessionJson['currentTabIndex'] ?? 0,
      tabMetadata: metadataJson.map((k, v) => MapEntry(k, TabMetadata.fromJson(v))),
    );

    return Project(
      metadata: ProjectMetadata(
        id: '', name: '', rootUri: '', projectTypeId: '',
        lastOpenedDateTime: DateTime.fromMillisecondsSinceEpoch(0),
      ),
      session: persistedSession,
      workspace: ExplorerWorkspaceState.fromJson(
        json['workspace'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}

// Helper class to temporarily hold persisted tab data without full logic.
class PersistedEditorTab extends EditorTab {
  final Map<String, dynamic> _json;
  PersistedEditorTab(this._json) : super(plugin: NoOpPlugin(), id: _json['id']);
  
  @override
  Map<String, dynamic> toJson() => _json;
  
  @override
  void dispose() {}
}

class NoOpPlugin implements EditorPlugin {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}