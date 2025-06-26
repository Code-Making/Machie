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
  /// This holds the entire state of a "simple" project, as it has no
  /// other persistence mechanism. For "persistent" projects, this will be null.
  final ProjectDto? currentSimpleProjectDto;

  const AppStateDto({
    this.knownProjects = const [],
    this.lastOpenedProjectId,
    this.currentSimpleProjectDto,
  });

  factory AppStateDto.fromJson(Map<String, dynamic> json) {
    return AppStateDto(
      knownProjects: (json['knownProjects'] as List? ?? [])
          .map((p) => ProjectMetadata.fromJson(p as Map<String, dynamic>))
          .toList(),
      lastOpenedProjectId: json['lastOpenedProjectId'],
      currentSimpleProjectDto: json['currentProjectState'] != null
          ? ProjectDto.fromJson(json['currentProjectState'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'knownProjects': knownProjects.map((p) => p.toJson()).toList(),
    'lastOpenedProjectId': lastOpenedProjectId,
    'currentProjectState': currentSimpleProjectDto?.toJson(),
  };
}