// =========================================
// NEW FILE: lib/data/dto/app_state_dto.dart
// =========================================

import 'package:flutter/foundation.dart';
import '../../project/project_models.dart';
import 'project_dto.dart';

@immutable
class AppStateDto {
  final List<ProjectMetadata> knownProjects;
  final String? lastOpenedProjectId;

  // REFACTORED: Changed from a single object to a map.
  // This allows us to persist the session state for ALL simple projects.
  final Map<String, ProjectDto> simpleProjectStates;

  const AppStateDto({
    this.knownProjects = const [],
    this.lastOpenedProjectId,
    this.simpleProjectStates = const {},
  });
  
    // ADDED: A pure copyWith method is acceptable for DTOs.
  AppStateDto copyWith({
    List<ProjectMetadata>? knownProjects,
    String? lastOpenedProjectId,
    Map<String, ProjectDto>? simpleProjectStates,
  }) {
    return AppStateDto(
      knownProjects: knownProjects ?? this.knownProjects,
      lastOpenedProjectId: lastOpenedProjectId ?? this.lastOpenedProjectId,
      simpleProjectStates: simpleProjectStates ?? this.simpleProjectStates,
    );
  }

  factory AppStateDto.fromJson(Map<String, dynamic> json) {
    // Handle legacy data where 'currentProjectState' might still exist.
    final legacyState = json['currentProjectState'] != null
        ? ProjectDto.fromJson(
            json['currentProjectState'] as Map<String, dynamic>,
          )
        : null;
    
    final simpleStatesJson = json['simpleProjectStates'] as Map<String, dynamic>? ?? {};
    final Map<String, ProjectDto> simpleStates = simpleStatesJson.map(
      (key, value) => MapEntry(
        key,
        ProjectDto.fromJson(value as Map<String, dynamic>),
      ),
    );

    // If legacy data exists and the new map is empty, migrate it.
    if (legacyState != null && simpleStates.isEmpty && json['lastOpenedProjectId'] != null) {
      simpleStates[json['lastOpenedProjectId']] = legacyState;
    }
    
    return AppStateDto(
      knownProjects:
          (json['knownProjects'] as List? ?? [])
              .map((p) => ProjectMetadata.fromJson(p as Map<String, dynamic>))
              .toList(),
      lastOpenedProjectId: json['lastOpenedProjectId'],
      simpleProjectStates: simpleStates,
    );
  }

  Map<String, dynamic> toJson() => {
    'knownProjects': knownProjects.map((p) => p.toJson()).toList(),
    'lastOpenedProjectId': lastOpenedProjectId,
    'simpleProjectStates': simpleProjectStates.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    // We no longer write the old key.
  };
}
