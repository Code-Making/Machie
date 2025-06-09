// lib/app/app_state.dart
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../project/project_models.dart';

// Represents the entire global, persistable state of the application.
@immutable
class AppState {
  final List<ProjectMetadata> knownProjects;
  final String? lastOpenedProjectId;
  // Non-persistent state, loaded dynamically.
  final Project? currentProject;

  const AppState({
    this.knownProjects = const [],
    this.lastOpenedProjectId,
    this.currentProject,
  });

  factory AppState.initial() => const AppState();

  AppState copyWith({
    List<ProjectMetadata>? knownProjects,
    String? lastOpenedProjectId,
    Project? currentProject,
    bool clearCurrentProject = false,
  }) {
    return AppState(
      knownProjects: knownProjects ?? List.from(this.knownProjects),
      lastOpenedProjectId: lastOpenedProjectId ?? this.lastOpenedProjectId,
      currentProject: clearCurrentProject ? null : (currentProject ?? this.currentProject),
    );
  }

  // --- Serialization for PersistenceService ---
  Map<String, dynamic> toJson() => {
        'knownProjects': knownProjects.map((p) => p.toJson()).toList(),
        'lastOpenedProjectId': lastOpenedProjectId,
      };

  factory AppState.fromJson(Map<String, dynamic> json) => AppState(
        knownProjects: (json['knownProjects'] as List)
            .map((p) => ProjectMetadata.fromJson(p as Map<String, dynamic>))
            .toList(),
        lastOpenedProjectId: json['lastOpenedProjectId'],
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    final listEquals = const DeepCollectionEquality().equals;
  
    return other is AppState &&
      listEquals(other.knownProjects, knownProjects) &&
      other.lastOpenedProjectId == lastOpenedProjectId &&
      other.currentProject == currentProject;
  }

  @override
  int get hashCode => Object.hash(
    const DeepCollectionEquality().hash(knownProjects),
    lastOpenedProjectId,
    currentProject
  );
}