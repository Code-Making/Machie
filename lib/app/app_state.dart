import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import '../data/content_provider/file_content_provider.dart';
import '../project/project_models.dart';

import '../data/dto/app_state_dto.dart';
import '../data/dto/project_dto.dart';
import '../editor/tab_metadata_notifier.dart';

@immutable
class AppState {
  final List<ProjectMetadata> knownProjects;
  final String? lastOpenedProjectId;
  final Project? currentProject;

  final Widget? bottomToolbarOverride;
  final bool isFullScreen;

  const AppState({
    this.knownProjects = const [],
    this.lastOpenedProjectId,
    this.currentProject,
    this.bottomToolbarOverride,
    this.isFullScreen = false,
  });

  factory AppState.initial() => const AppState();

  AppStateDto toDto(
    Map<String, TabMetadata> liveTabMetadata,
    FileContentProviderRegistry registry,
  ) {
    final ProjectDto? projectDto =
        currentProject?.toDto(liveTabMetadata, registry);
    
    return AppStateDto(
      knownProjects: knownProjects,
      lastOpenedProjectId: lastOpenedProjectId,
      currentProjectDto: projectDto,
    );
  }

  AppState copyWith({
    List<ProjectMetadata>? knownProjects,
    String? lastOpenedProjectId,
    Project? currentProject,
    bool clearCurrentProject = false,
    Widget? bottomToolbarOverride,
    bool clearBottomToolbarOverride = false,
    bool? isFullScreen,
  }) {
    return AppState(
      knownProjects: knownProjects ?? List.from(this.knownProjects),
      lastOpenedProjectId: lastOpenedProjectId ?? this.lastOpenedProjectId,
      currentProject:
          clearCurrentProject ? null : (currentProject ?? this.currentProject),
      bottomToolbarOverride:
          clearBottomToolbarOverride
              ? null
              : bottomToolbarOverride ?? this.bottomToolbarOverride,
      isFullScreen: isFullScreen ?? this.isFullScreen,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    final listEquals = const DeepCollectionEquality().equals;

    return other is AppState &&
        listEquals(other.knownProjects, knownProjects) &&
        other.lastOpenedProjectId == lastOpenedProjectId &&
        other.currentProject == currentProject &&
        other.bottomToolbarOverride == bottomToolbarOverride &&
        other.isFullScreen == isFullScreen;
  }

  @override
  int get hashCode => Object.hash(
    const DeepCollectionEquality().hash(knownProjects),
    lastOpenedProjectId,
    currentProject,
    bottomToolbarOverride,
    isFullScreen,
  );
}
