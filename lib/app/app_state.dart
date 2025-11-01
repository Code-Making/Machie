// =========================================
// UPDATED: lib/app/app_state.dart
// =========================================

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../project/project_models.dart';
import '../data/dto/app_state_dto.dart'; // ADDED
import '../data/dto/project_dto.dart'; // ADDED
import '../editor/tab_state_manager.dart'; // ADDED
import '../editor/services/file_content_provider.dart';

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

  // REFACTORED: This method now requires the full map of simple project states
  // to correctly build the DTO.
  AppStateDto toDto(
    Map<String, TabMetadata> liveTabMetadata,
    FileContentProviderRegistry registry,
    Map<String, ProjectDto> allSimpleProjectStates,
  ) {
    return AppStateDto(
      knownProjects: knownProjects,
      lastOpenedProjectId: lastOpenedProjectId,
      simpleProjectStates: allSimpleProjectStates,
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
