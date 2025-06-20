// lib/project/project_manager.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';

import 'project_factory.dart';
import 'project_models.dart';

import '../data/file_handler/file_handler.dart';

export'project_models.dart';

final projectManagerProvider = Provider<ProjectManager>((ref) {
  return ProjectManager(ref);
});

class OpenProjectResult {
  final Project project;

  /// The metadata, which might be new or existing.
  final ProjectMetadata metadata;

  /// A flag indicating if this project was newly added to the known projects list.
  final bool isNew;

  OpenProjectResult({
    required this.project,
    required this.metadata,
    required this.isNew,
  });
}

class ProjectManager {
  final Ref _ref;
  ProjectManager(this._ref);

  // NEW: This method now contains the core business logic.
  Future<OpenProjectResult> openFromFolder({
    required DocumentFile folder,
    required String projectTypeId,
    // It needs the current list of known projects to do its job.
    required List<ProjectMetadata> knownProjects,
  }) async {
    // Logic from AppNotifier is now here.
    ProjectMetadata? meta = knownProjects.firstWhereOrNull(
      (p) => p.rootUri == folder.uri && p.projectTypeId == projectTypeId,
    );

    final bool isNew = meta == null;
    meta ??= await createNewProjectMetadata(
      rootUri: folder.uri,
      name: folder.name,
      projectTypeId: projectTypeId,
    );

    final project = await openProject(meta);

    return OpenProjectResult(project: project, metadata: meta, isNew: isNew);
  }

  Future<Project> openProject(
    ProjectMetadata metadata, {
    Map<String, dynamic>? projectStateJson,
  }) async {
    final factories = _ref.read(projectFactoryRegistryProvider);
    final factory = factories[metadata.projectTypeId];
    if (factory == null) {
      throw UnimplementedError(
        'No factory for project type ${metadata.projectTypeId}',
      );
    }
    return factory.open(metadata, _ref, projectStateJson: projectStateJson);
  }

  Future<void> saveProject(Project project) async {
    await project.save();
  }

  Future<void> closeProject(Project project, {required Ref ref}) async {
    await project.close(ref: ref);
  }

  // MODIFIED: Now requires a projectTypeId.
  Future<ProjectMetadata> createNewProjectMetadata({
    required String rootUri,
    required String name,
    required String projectTypeId,
  }) async {
    return ProjectMetadata(
      id: const Uuid().v4(),
      name: name,
      rootUri: rootUri,
      projectTypeId: projectTypeId,
      lastOpenedDateTime: DateTime.now(),
    );
  }
}
