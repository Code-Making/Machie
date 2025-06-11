// lib/project/project_manager.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'project_factory.dart'; // NEW
import 'project_models.dart';

final projectManagerProvider = Provider<ProjectManager>((ref) {
  return ProjectManager(ref);
});

// This service handles the business logic of opening, closing, and saving projects.
class ProjectManager {
  final Ref _ref;

  ProjectManager(this._ref);

  Future<Project> openProject(ProjectMetadata metadata) async {
    // MODIFIED: Use the factory to delegate project creation.
    final factories = _ref.read(projectFactoryRegistryProvider);
    final factory = factories[metadata.projectType];
    if (factory == null) {
      throw UnimplementedError('No factory for project type ${metadata.projectType}');
    }
    return factory.open(metadata, _ref);
  }

  Future<void> saveProject(Project project) async {
    // MODIFIED: Delegate saving to the project itself.
    await project.save();
  }

  // NEW: Add a corresponding close method for consistency.
  Future<void> closeProject(Project project) async {
    // MODIFIED: Delegate closing to the project itself.
    await project.close();
  }

  Future<ProjectMetadata> createNewProjectMetadata(
    String rootUri,
    String name,
  ) async {
    return ProjectMetadata(
      id: const Uuid().v4(),
      name: name,
      rootUri: rootUri,
      projectType: ProjectType.local,
      lastOpenedDateTime: DateTime.now(),
    );
  }

  // DELETED: _ensureProjectDataFolder and _createLocalProjectFromJson are now in LocalProjectFactory.
}