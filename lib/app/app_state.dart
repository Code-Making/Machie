// =========================================
// FILE: lib/app/app_state.dart
// =========================================

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../project/project_models.dart';
import '../editor/tab_state_manager.dart'; // ADDED for live metadata access

@immutable
class AppState {
  /// A list of metadata for all projects the user has opened.
  final List<ProjectMetadata> knownProjects;
  
  /// The ID of the last project that was open. Used to reopen on startup.
  final String? lastOpenedProjectId;
  
  /// The live, fully rehydrated domain model for the currently active project.
  /// This property is NOT persisted directly.
  final Project? currentProject;
  
  /// A raw JSON map representing the state of the last active "simple" project.
  /// This is only populated on save and used on rehydration for simple projects.
  final Map<String, dynamic>? currentProjectState;
  
  /// Overrides for the app's main UI components, for contextual toolbars.
  /// These are ephemeral and not persisted.
  final Widget? appBarOverride;
  final Widget? bottomToolbarOverride;

  /// Ephemeral state for fullscreen mode. Not persisted.
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

  /// Converts the AppState into a JSON map for persistence in SharedPreferences.
  /// Note that ephemeral state like `currentProject`, `isFullScreen`, and UI
  /// overrides are not saved.
  Map<String, dynamic> toJson(Map<String, TabMetadata> liveTabMetadata) {
    Map<String, dynamic> json = {
      'knownProjects': knownProjects.map((p) => p.toJson()).toList(),
      'lastOpenedProjectId': lastOpenedProjectId,
      // We start with a null state for the simple project.
      'currentProjectState': null,
    };
    
    // If the currently open project is a 'simple_local' project, we convert
    // its live state into a DTO and store that in the AppState JSON.
    // This is how non-persistent projects save their tab state.
    if (currentProject?.projectTypeId == 'simple_local') {
      json['currentProjectState'] = currentProject!.toDto(liveTabMetadata).toJson();
    }
    
    return json;
  }

  /// Creates an AppState instance from a JSON map loaded from SharedPreferences.
  factory AppState.fromJson(Map<String, dynamic> json) {
    return AppState(
      knownProjects:
          (json['knownProjects'] as List)
              .map((p) => ProjectMetadata.fromJson(p as Map<String, dynamic>))
              .toList(),
      lastOpenedProjectId: json['lastOpenedProjectId'],
      // We load the raw JSON for the simple project. The AppNotifier will
      // be responsible for passing this to the services for rehydration.
      currentProjectState:
          json['currentProjectState'] != null
              ? Map<String, dynamic>.from(json['currentProjectState'])
              : null,
    );
  }
  
  // Equality and hashCode are important for Riverpod to correctly detect
  // when the state has actually changed.
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