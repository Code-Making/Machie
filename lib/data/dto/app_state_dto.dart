import 'package:flutter/foundation.dart';

import '../../project/project_models.dart';
import 'project_dto.dart';

@immutable
class AppStateDto {
  final List<ProjectMetadata> knownProjects;
  final String? lastOpenedProjectId;

  final ProjectDto? currentProjectDto;

  const AppStateDto({
    this.knownProjects = const [],
    this.lastOpenedProjectId,
    this.currentProjectDto,
  });

  factory AppStateDto.fromJson(Map<String, dynamic> json) {
    final projectStateJson = json['currentProjectDto'] ?? json['currentProjectState'];
    
    return AppStateDto(
      knownProjects:
          (json['knownProjects'] as List? ?? [])
              .map((p) => ProjectMetadata.fromJson(p as Map<String, dynamic>))
              .toList(),
      lastOpenedProjectId: json['lastOpenedProjectId'],
      currentProjectDto:
          projectStateJson != null
              ? ProjectDto.fromJson(
                projectStateJson as Map<String, dynamic>,
              )
              : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'knownProjects': knownProjects.map((p) => p.toJson()).toList(),
    'lastOpenedProjectId': lastOpenedProjectId,
    'currentProjectDto': currentProjectDto?.toJson(),
  };
}
