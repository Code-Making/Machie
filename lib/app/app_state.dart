// lib/app/app_state.dart
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../project/project_models.dart';

@immutable
class AppState {
  final List<ProjectMetadata> knownProjects;
  final String? lastOpenedProjectId;
  final Project? currentProject;

  // NEW: State for the current project, to be saved in SharedPreferences.
  final Map<String, dynamic>? currentProjectState;

  const AppState({
    this.knownProjects = const [],
    this.lastOpenedProjectId,
    this.currentProject,
    this.currentProjectState, // NEW
  });

  factory AppState.initial() => const AppState();

  AppState copyWith({
    List<ProjectMetadata>? knownProjects,
    String? lastOpenedProjectId,
    Project? currentProject,
    bool clearCurrentProject = false,
    // MODIFIED: Add project state to copyWith
    Map<String, dynamic>? currentProjectState,
  }) {
    return AppState(
      knownProjects: knownProjects ?? List.from(this.knownProjects),
      lastOpenedProjectId: lastOpenedProjectId ?? this.lastOpenedProjectId,
      currentProject: clearCurrentProject ? null : (currentProject ?? this.currentProject),
      // If we clear the project, clear its state too.
      currentProjectState: clearCurrentProject
          ? null
          : (currentProjectState ?? this.currentProjectState),
    );
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {
      'knownProjects': knownProjects.map((p) => p.toJson()).toList(),
      'lastOpenedProjectId': lastOpenedProjectId,
    };
    // NEW: If there's a current project, serialize its state.
    if (currentProject != null) {
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
      // NEW: Store the raw JSON. The AppNotifier will use this to rehydrate the project.
      currentProjectState: json['currentProjectState'] != null
          ? Map<String, dynamic>.from(json['currentProjectState'])
          : null,
    );
  }

  // ... (operator== and hashCode updated)
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    final mapEquals = const DeepCollectionEquality().equals;
    final listEquals = const DeepCollectionEquality().equals;

    return other is AppState &&
        listEquals(other.knownProjects, knownProjects) &&
        other.lastOpenedProjectId == lastOpenedProjectId &&
        other.currentProject == currentProject &&
        mapEquals(other.currentProjectState, currentProjectState);
  }

  @override
  int get hashCode => Object.hash(
        const DeepCollectionEquality().hash(knownProjects),
        lastOpenedProjectId,
        currentProject,
        const DeepCollectionEquality().hash(currentProjectState),
      );
}