// =========================================
// FILE: lib/project/project_models.dart
// =========================================

import 'package:flutter/foundation.dart';
import '../editor/editor_tab_models.dart';
import '../editor/plugins/plugin_models.dart'; // ADDED for EditorPlugin
import '../explorer/explorer_workspace_state.dart';
import '../data/file_handler/file_handler.dart';
import '../editor/tab_state_manager.dart';

// REFACTORED: These are now top-level definitions, outside any other class.

/// A placeholder class used only during the initial deserialization of a Project.
/// It holds the raw JSON of a tab without trying to build a full plugin,
/// allowing the EditorService to handle the full rehydration.
class PersistedEditorTab extends EditorTab {
  final Map<String, dynamic> _json;
  PersistedEditorTab(this._json) : super(plugin: NoOpPlugin(), id: _json['id']);
  
  @override
  Map<String, dynamic> toJson() => _json;
  
  @override
  void dispose() {}
}

/// A no-operation plugin implementation used exclusively by [PersistedEditorTab]
/// to satisfy the constructor requirements without needing a real plugin instance
/// during the raw deserialization phase.
class NoOpPlugin implements EditorPlugin {
  // By using `noSuchMethod`, we don't need to implement every single method
  // of the EditorPlugin interface, as this class will never be used to
  // actually perform any operations.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}


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

  Map<String, dynamic> toJson() => {
    'session': session.toJson(),
    'workspace': workspace.toJson(),
  };

  factory Project.fromJson(Map<String, dynamic> json) {
    final sessionJson = json['session'] as Map<String, dynamic>? ?? {};
    final tabsJson = sessionJson['tabs'] as List<dynamic>? ?? [];
    final metadataJson = sessionJson['tabMetadata'] as Map<String, dynamic>? ?? {};

    // Use the top-level helper class to create temporary tab objects.
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