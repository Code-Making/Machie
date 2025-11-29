import 'package:flutter/material.dart';

import '../data/repositories/project/project_repository.dart';
import 'project_models.dart';
import 'project_settings_models.dart';

/// Defines the contract for managing a specific type of project (e.g., local, SSH).
///
/// This abstraction encapsulates all the unique logic for a project type,
/// including its creation flow, repository instantiation, and permission recovery.
abstract class ProjectTypeHandler {
  /// A unique, stable string identifier for this project type (e.g., 'local').
  String get id;

  /// A user-facing name for display in the UI (e.g., "Local Folder Project").
  String get name;

  /// A user-facing description for the "New Project" screen.
  String get description;

  /// An icon to represent this project type in the UI.
  IconData get icon;
  
  /// Checks if the app currently has the necessary permissions to open
  /// a project described by the given metadata.
  Future<bool> hasPersistedPermission(ProjectMetadata metadata);
  
  /// A list of persistence type IDs that are compatible with this project type.
  /// This is used by the UI to filter and display the correct storage options.
  List<String> get supportedPersistenceTypeIds;

  ProjectSettings? get projectTypeSettings;

  Widget buildProjectTypeSettingsUI(
    ProjectSettings settings,
    void Function(ProjectSettings) onChanged,
  );

  /// Initiates the user-facing flow to create a new project of this type.
  ///
  /// This method is now simpler: it receives the `persistenceTypeId` chosen by
  /// the user in the UI and is only responsible for gathering the remaining
  /// project-type-specific information (like the root folder for a local project).
  ///
  /// Returns a fully-formed [ProjectMetadata] or `null` if the user cancels.
  Future<ProjectMetadata?> initiateNewProject(
    BuildContext context,
    String persistenceTypeId,
  );

  /// Creates a [ProjectRepository] instance for a project with the given metadata.
  /// (Signature is unchanged, but implementation will be updated).
  ProjectRepository createRepository(
    ProjectMetadata metadata, {
    Map<String, dynamic>? projectStateJson,
  });

  /// Handles the permission recovery flow for a project of this type.
  /// (Signature is unchanged).
  Future<bool> recoverPermission(
    ProjectMetadata metadata,
    BuildContext context,
  );
}