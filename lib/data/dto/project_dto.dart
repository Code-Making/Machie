// =========================================
// NEW FILE: lib/data/dto/project_dto.dart
// =========================================

import 'package:flutter/foundation.dart';

// DTO for EditorTab metadata
@immutable
class TabMetadataDto {
  final String fileUri;
  final bool isDirty;

  const TabMetadataDto({required this.fileUri, required this.isDirty});

  factory TabMetadataDto.fromJson(Map<String, dynamic> json) {
    return TabMetadataDto(
      fileUri: json['fileUri'],
      isDirty: json['isDirty'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'fileUri': fileUri,
    'isDirty': isDirty,
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
    return EditorTabDto(
      id: json['id'],
      pluginType: json['pluginType'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'pluginType': pluginType,
  };
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
      tabMetadata: metadataJson.map((k, v) => MapEntry(k, TabMetadataDto.fromJson(v))),
    );
  }

  Map<String, dynamic> toJson() => {
    'tabs': tabs.map((t) => t.toJson()).toList(),
    'currentTabIndex': currentTabIndex,
    'tabMetadata': tabMetadata.map((k, v) => MapEntry(k, v.toJson())),
  };
}

// DTO for the Project itself
@immutable
class ProjectDto {
  final TabSessionStateDto session;
  // We can add workspace DTOs here later if needed.
  // final ExplorerWorkspaceStateDto workspace;

  const ProjectDto({required this.session});

  factory ProjectDto.fromJson(Map<String, dynamic> json) {
    return ProjectDto(
      session: TabSessionStateDto.fromJson(json['session'] ?? {}),
      // workspace: ...
    );
  }

  Map<String, dynamic> toJson() => {
    'session': session.toJson(),
    // 'workspace': workspace.toJson(),
  };
}