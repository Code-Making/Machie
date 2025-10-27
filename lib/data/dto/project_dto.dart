// =========================================
// NEW FILE: lib/data/dto/project_dto.dart
// =========================================

import 'package:flutter/foundation.dart';

// DTO for EditorTab metadata
@immutable
class TabMetadataDto {
  final String fileUri;
  final bool isDirty;
  // Store the name for reconstruction of virtual files.
  final String fileName; 
  // Explicitly store the type identifier for rehydration.
  final String fileType; 

  const TabMetadataDto({
    required this.fileUri,
    required this.isDirty,
    required this.fileName,
    required this.fileType,
  });

  factory TabMetadataDto.fromJson(Map<String, dynamic> json) {
    return TabMetadataDto(
      fileUri: json['fileUri'],
      isDirty: json['isDirty'] ?? false,
      fileName: json['fileName'] ?? '',
      // Default to a project file for backward compatibility with old data.
      fileType: json['fileType'] ?? 'project', 
    );
  }

  Map<String, dynamic> toJson() => {
        'fileUri': fileUri,
        'isDirty': isDirty,
        'fileName': fileName,
        'fileType': fileType,
      };
}

// DTO for an EditorTab instance
@immutable
class EditorTabDto {
  final String id;
  final String pluginType;
  // Any other persistable tab-specific data would go here.

  const EditorTabDto({required this.id, required this.pluginType});

  factory EditorTabDto.fromJson(Map<String, dynamic> json) {
    return EditorTabDto(id: json['id'], pluginType: json['pluginType']);
  }

  Map<String, dynamic> toJson() => {'id': id, 'pluginType': pluginType};
}

// DTO for the entire tab session
@immutable
class TabSessionStateDto {
  final List<EditorTabDto> tabs;
  final int currentTabIndex;
  final Map<String, TabMetadataDto> tabMetadata;

  const TabSessionStateDto({
    required this.tabs,
    required this.currentTabIndex,
    required this.tabMetadata,
  });

  factory TabSessionStateDto.fromJson(Map<String, dynamic> json) {
    final tabsJson = json['tabs'] as List<dynamic>? ?? [];
    final metadataJson = json['tabMetadata'] as Map<String, dynamic>? ?? {};

    return TabSessionStateDto(
      tabs: tabsJson.map((t) => EditorTabDto.fromJson(t)).toList(),
      currentTabIndex: json['currentTabIndex'] ?? 0,
      tabMetadata: metadataJson.map(
        (k, v) => MapEntry(k, TabMetadataDto.fromJson(v)),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'tabs': tabs.map((t) => t.toJson()).toList(),
    'currentTabIndex': currentTabIndex,
    'tabMetadata': tabMetadata.map((k, v) => MapEntry(k, v.toJson())),
  };
}

// NEW: DTO for the ExplorerWorkspaceState
@immutable
class ExplorerWorkspaceStateDto {
  final String activeExplorerPluginId;
  final Map<String, dynamic> pluginStates;

  const ExplorerWorkspaceStateDto({
    required this.activeExplorerPluginId,
    required this.pluginStates,
  });

  factory ExplorerWorkspaceStateDto.fromJson(Map<String, dynamic> json) {
    return ExplorerWorkspaceStateDto(
      activeExplorerPluginId:
          json['activeExplorerPluginId'] ?? 'com.machine.file_explorer',
      pluginStates: Map<String, dynamic>.from(json['pluginStates'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
    'activeExplorerPluginId': activeExplorerPluginId,
    'pluginStates': pluginStates,
  };
}

// UPDATED: ProjectDto now includes the workspace DTO.
@immutable
class ProjectDto {
  final TabSessionStateDto session;
  final ExplorerWorkspaceStateDto workspace;

  const ProjectDto({required this.session, required this.workspace});

  factory ProjectDto.fromJson(Map<String, dynamic> json) {
    return ProjectDto(
      session: TabSessionStateDto.fromJson(json['session'] ?? {}),
      workspace: ExplorerWorkspaceStateDto.fromJson(json['workspace'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
    'session': session.toJson(),
    'workspace': workspace.toJson(),
  };
}
