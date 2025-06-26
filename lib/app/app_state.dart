// =========================================
// UPDATED: lib/app/app_state.dart
// =========================================

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../project/project_models.dart';
import '../data/dto/app_state_dto.dart'; // ADDED
import '../editor/tab_state_manager.dart'; // ADDED

@immutable
class AppState {
  final List<ProjectMetadata> knownProjects;
  final String? lastOpenedProjectId;
  final Project? currentProject;
  
  // These are ephemeral and not part of the core data state.
  final Widget? appBarOverride;
  final Widget? bottomToolbarOverride;
  final bool isFullScreen;

  // REMOVED: currentProjectState is no longer part of the live model.

  const AppState({
    this.knownProjects = const [],
    this.lastOpenedProjectId,
    this.currentProject,
    this.appBarOverride,
    this.bottomToolbarOverride,
    this.isFullScreen = false,
  });

  factory AppState.initial() => const AppState();
  
  // ADDED: Method to create a DTO from the live state.
  AppStateDto toDto(Map<String, TabMetadata> liveTabMetadata) {
    ProjectDto? simpleProjectDto;
    if (currentProject?.projectTypeId == 'simple_local') {
      simpleProjectDto = currentProject!.toDto(liveTabMetadata);
    }
    
    return AppStateDto(
      knownProjects: knownProjects,
      lastOpenedProjectId: lastOpenedProjectId,
      currentSimpleProjectDto: simpleProjectDto,
    );
  }

  // REMOVED: toJson and fromJson are gone.

  // copyWith is simplified.
  AppState copyWith({
    List<ProjectMetadata>? knownProjects,
    String? lastOpenedProjectId,
    Project? currentProject,
    bool clearCurrentProject = false,
    Widget? appBarOverride,
    Widget? bottomToolbarOverride,
    bool clearAppBarOverride = false,
    bool clearBottomToolbarOverride = false,
    bool? isFullScreen,
  }) {
    return AppState(
      knownProjects: knownProjects ?? List.from(this.knownProjects),
      lastOpenedProjectId: lastOpenedProjectId ?? this.lastOpenedProjectId,
      currentProject: clearCurrentProject ? null : (currentProject ?? this.currentProject),
      appBarOverride: clearAppBarOverride ? null : appBarOverride ?? this.appBarOverride,
      bottomToolbarOverride: clearBottomToolbarOverride ? null : bottomToolbarOverride ?? this.bottomToolbarOverride,
      isFullScreen: isFullScreen ?? this.isFullScreen,
    );
  }
  
  // ... (equality and hashCode updated to remove currentProjectState) ...
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    final listEquals = const DeepCollectionEquality().equals;

    return other is AppState &&
        listEquals(other.knownProjects, knownProjects) &&
        other.lastOpenedProjectId == lastOpenedProjectId &&
        other.currentProject == currentProject &&
        other.appBarOverride == appBarOverride &&
        other.bottomToolbarOverride == bottomToolbarOverride &&
        other.isFullScreen == isFullScreen;
  }

  @override
  int get hashCode => Object.hash(
    const DeepCollectionEquality().hash(knownProjects),
    lastOpenedProjectId,
    currentProject,
    appBarOverride,
    bottomToolbarOverride,
    isFullScreen,
  );
}