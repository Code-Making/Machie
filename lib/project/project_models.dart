// =========================================
// FILE: lib/project/project_models.dart
// =========================================

import 'package:flutter/foundation.dart';

import '../data/file_handler/file_handler.dart';
import '../editor/models/editor_tab_models.dart';
import '../data/content_provider/file_content_provider.dart';
import '../editor/tab_metadata_notifier.dart';
import '../explorer/explorer_workspace_state.dart';

import '../data/dto/project_dto.dart'; // ADDED
import 'project_settings_models.dart';

//TODO: Move this into documentFile definition file
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

/// A concrete implementation of [DocumentFile] for files stored in the app's
/// private internal storage directory. These files are not part of any user
/// project and persist globally for the application.
@immutable
class InternalAppFile implements DocumentFile {
  @override
  final String uri; // e.g., "internal://scratchpad.md"

  @override
  final String name;

  // These properties are often fixed or irrelevant for internal files.
  @override
  final bool isDirectory = false;
  @override
  final int size;
  @override
  final DateTime modifiedDate;
  @override
  final String mimeType;

  const InternalAppFile({
    required this.uri,
    required this.name,
    this.size = 0,
    required this.modifiedDate,
    this.mimeType = 'text/plain',
  });
}

@immutable
class ProjectMetadata {
  final String id;
  final String name;
  final String rootUri;
  final String projectTypeId;
  final String persistenceTypeId;
  final DateTime lastOpenedDateTime;

  const ProjectMetadata({
    required this.id,
    required this.name,
    required this.rootUri,
    required this.projectTypeId,
    required this.persistenceTypeId,
    required this.lastOpenedDateTime,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'rootUri': rootUri,
        'projectTypeId': projectTypeId,
        'persistenceTypeId': persistenceTypeId, // NEW
        'lastOpenedDateTime': lastOpenedDateTime.toIso8601String(),
      };

  factory ProjectMetadata.fromJson(Map<String, dynamic> json) {
    // Backward Compatibility Layer ---

    String projectTypeId = json['projectTypeId'];
    String? persistenceTypeId = json['persistenceTypeId'];

    // If persistenceTypeId is null, we are dealing with legacy data.
    if (persistenceTypeId == null) {
      switch (projectTypeId) {
        case 'local_persistent':
          projectTypeId = 'local';
          persistenceTypeId = 'local_folder';
          break;
        case 'simple_local':
          projectTypeId = 'local';
          persistenceTypeId = 'simple_state';
          break;
        default:
          projectTypeId = 'local';
          persistenceTypeId = 'simple_state';
          break;
      }
    }

    return ProjectMetadata(
      id: json['id'],
      name: json['name'],
      rootUri: json['rootUri'],
      projectTypeId: projectTypeId, // Use the (potentially migrated) projectTypeId
      persistenceTypeId: persistenceTypeId, // Use the (potentially migrated) persistenceTypeId
      lastOpenedDateTime: DateTime.parse(json['lastOpenedDateTime']),
    );
  }
}

@immutable
class Project {
  final ProjectMetadata metadata;
  final TabSessionState session;
  final ExplorerWorkspaceState workspace;
  final ProjectSettingsState? settings;

  const Project({
    required this.metadata,
    required this.session,
    required this.workspace,
    this.settings,
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
      settings: const ProjectSettingsState(),
    );
  }

  Project copyWith({
    ProjectMetadata? metadata,
    TabSessionState? session,
    ExplorerWorkspaceState? workspace,
    ProjectSettingsState? settings,
  }) {
    return Project(
      metadata: metadata ?? this.metadata,
      session: session ?? this.session,
      workspace: workspace ?? this.workspace,
      settings: settings ?? this.settings,
    );
  }

  /// type of each open file for persistence.
  ProjectDto toDto(
    Map<String, TabMetadata> liveMetadata,
    FileContentProviderRegistry registry,
  ) {
    return ProjectDto(
      session: session.toDto(liveMetadata, registry),
      workspace: workspace.toDto(),
      settings: settings?.toDto(),
    );
  }
}

// This now correctly extends the base DocumentFile, clearly separating it
// from files managed by the ProjectRepository.
@immutable
class VirtualDocumentFile implements DocumentFile {
  @override
  final String uri;

  @override
  final String name;

  @override
  final bool isDirectory;

  @override
  final int size;

  @override
  final DateTime modifiedDate;

  @override
  final String mimeType;

  VirtualDocumentFile({
    required this.uri,
    required this.name,
    this.isDirectory = false,
    this.size = 0,
    this.mimeType = 'text/plain',
  }) : modifiedDate = DateTime.now();
}
