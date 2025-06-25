// =========================================
// FILE: lib/app/app_state.dart
// =========================================

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../project/project_models.dart';
import '../editor/tab_state_manager.dart';

@immutable
class AppState {
  // ... properties are the same ...
  final List<ProjectMetadata> knownProjects;
  final String? lastOpenedProjectId;
  final Project? currentProject;
  final Map<String, dynamic>? currentProjectState;
  final Widget? appBarOverride;
  final Widget? bottomToolbarOverride;
  final bool isFullScreen;
  
  const AppState({
    this.knownProjects = const [],
    this.lastOpenedProjectId,
    this.currentProject,
    this.currentProjectState,
    this.appBarOverride,
    this.bottomToolbarOverride,
    this.isFullScreen = false,
  });

  // ... copyWith and initial are the same ...
  factory AppState.initial() => const AppState();

  AppState copyWith({
    List<ProjectMetadata>? knownProjects,
    String? lastOpenedProjectId,
    Project? currentProject,
    bool clearCurrentProject = false,
    Map<String, dynamic>? currentProjectState,
    bool clearCurrentProjectState = false,
    Widget? appBarOverride,
    Widget? bottomToolbarOverride,
    bool clearAppBarOverride = false,
    bool clearBottomToolbarOverride = false,
    bool? isFullScreen,
  }) {
    return AppState(
      knownProjects: knownProjects ?? List.from(this.knownProjects),
      lastOpenedProjectId: lastOpenedProjectId ?? this.lastOpenedProjectId,
      currentProject:
          clearCurrentProject ? null : (currentProject ?? this.currentProject),
      currentProjectState:
          clearCurrentProjectState
              ? null
              : (currentProjectState ?? this.currentProjectState),
      appBarOverride:
          clearAppBarOverride ? null : appBarOverride ?? this.appBarOverride,
      bottomToolbarOverride:
          clearBottomToolbarOverride
              ? null
              : bottomToolbarOverride ?? this.bottomToolbarOverride,
      isFullScreen: isFullScreen ?? this.isFullScreen,
    );
  }


  // REFACTORED: The signature requires the live metadata to be passed in.
  // The AppNotifier will provide this at the time of saving.
  Map<String, dynamic> toJson(Map<String, TabMetadata> liveTabMetadata) {
    Map<String, dynamic> json = {
      'knownProjects': knownProjects.map((p) => p.toJson()).toList(),
      'lastOpenedProjectId': lastOpenedProjectId,
      'currentProjectState': null,
    };
    
    if (currentProject?.projectTypeId == 'simple_local') {
      json['currentProjectState'] = currentProject!.toDto(liveTabMetadata).toJson();
    }
    
    return json;
  }

  factory AppState.fromJson(Map<String, dynamic> json) {
    return AppState(
      knownProjects:
          (json['knownProjects'] as List)
              .map((p) => ProjectMetadata.fromJson(p as Map<String, dynamic>))
              .toList(),
      lastOpenedProjectId: json['lastOpenedProjectId'],
      currentProjectState:
          json['currentProjectState'] != null
              ? Map<String, dynamic>.from(json['currentProjectState'])
              : null,
    );
  }
  
  // ... (equality and hashCode are unchanged) ...
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    final mapEquals = const DeepCollectionEquality().equals;
    final listEquals = const DeepCollectionEquality().equals;

    return other is AppState &&
        listEquals(other.knownProjects, knownProjects) &&
        other.lastOpenedProjectId == lastOpenedProjectId &&
        other.currentProject == currentProject &&
        mapEquals(other.currentProjectState, currentProjectState) &&
        other.appBarOverride == appBarOverride &&
        other.bottomToolbarOverride == bottomToolbarOverride &&
        other.isFullScreen == isFullScreen;
  }

  @override
  int get hashCode => Object.hash(
    const DeepCollectionEquality().hash(knownProjects),
    lastOpenedProjectId,
    currentProject,
    const DeepCollectionEquality().hash(currentProjectState),
    appBarOverride,
    bottomToolbarOverride,
    isFullScreen,
  );
}