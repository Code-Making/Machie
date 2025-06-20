// lib/app/app_state.dart
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../project/project_models.dart';

@immutable
class AppState {
  final List<ProjectMetadata> knownProjects;
  final String? lastOpenedProjectId;
  // REFACTOR: This now holds the pure Project domain model.
  final Project? currentProject;
  // REFACTOR: This state is now used only for initial hydration of a SimpleProject.
  final Map<String, dynamic>? currentProjectState;
  // TODO : check these for corrext architecture, might cause unwanted redraws
  // NEW: Toolbar override properties
  final Widget? appBarOverride;
  final Widget? bottomToolbarOverride;

  const AppState({
    this.knownProjects = const [],
    this.lastOpenedProjectId,
    this.currentProject,
    this.currentProjectState,
    this.appBarOverride,
    this.bottomToolbarOverride,
  });

  factory AppState.initial() => const AppState();

  AppState copyWith({
    List<ProjectMetadata>? knownProjects,
    String? lastOpenedProjectId,
    Project? currentProject,
    bool clearCurrentProject = false,
    Map<String, dynamic>? currentProjectState,
    bool clearCurrentProjectState = false,
    // NEW: Add overrides to copyWith
    Widget? appBarOverride,
    Widget? bottomToolbarOverride,
    bool clearAppBarOverride = false,
    bool clearBottomToolbarOverride = false,
  }) {
    return AppState(
      knownProjects: knownProjects ?? List.from(this.knownProjects),
      lastOpenedProjectId: lastOpenedProjectId ?? this.lastOpenedProjectId,
      currentProject:
          clearCurrentProject ? null : (currentProject ?? this.currentProject),
      currentProjectState: clearCurrentProjectState
          ? null
          : (currentProjectState ?? this.currentProjectState),
      // NEW: Handle override updates
      appBarOverride:
          clearAppBarOverride ? null : appBarOverride ?? this.appBarOverride,
      bottomToolbarOverride:
          clearBottomToolbarOverride
              ? null
              : bottomToolbarOverride ?? this.bottomToolbarOverride,
    );
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {
      'knownProjects': knownProjects.map((p) => p.toJson()).toList(),
      'lastOpenedProjectId': lastOpenedProjectId,
    };
    // REFACTOR: If the current project is a simple one, save its state here.
    if (currentProject?.projectTypeId == 'simple_local') {
      json['currentProjectState'] = currentProject!.toJson();
    }
    return json;
  }

  factory AppState.fromJson(Map<String, dynamic> json) {
    return AppState(
      knownProjects: (json['knownProjects'] as List)
          .map((p) => ProjectMetadata.fromJson(p as Map<String, dynamic>))
          .toList(),
      lastOpenedProjectId: json['lastOpenedProjectId'],
      currentProjectState: json['currentProjectState'] != null
          ? Map<String, dynamic>.from(json['currentProjectState'])
          : null,
    );
  }

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
        other.appBarOverride == appBarOverride && // NEW
        other.bottomToolbarOverride == bottomToolbarOverride; // NEW
  }

  @override
  int get hashCode => Object.hash(
        const DeepCollectionEquality().hash(knownProjects),
        lastOpenedProjectId,
        currentProject,
        const DeepCollectionEquality().hash(currentProjectState),
        appBarOverride, // NEW
        bottomToolbarOverride, // NEW
      );
}