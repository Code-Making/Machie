// lib/project/services/project_service.dart
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/file_handler/file_handler.dart';
import '../../data/file_handler/local_file_handler.dart';
import '../../data/repositories/persistent_project_repository.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/simple_project_repository.dart';
import '../project_models.dart';

// ... (OpenProjectResult and provider are unchanged) ...
final projectServiceProvider = Provider<ProjectService>((ref) {
  return ProjectService(ref);
});

class OpenProjectResult {
  final Project project;
  final ProjectMetadata metadata;
  final bool isNew;

  OpenProjectResult({
    required this.project,
    required this.metadata,
    required this.isNew,
  });
}

class ProjectService {
  final Ref _ref;

  ProjectService(this._ref);

  // ... (openFromFolder is unchanged) ...
  Future<OpenProjectResult> openFromFolder({
    required DocumentFile folder,
    required String projectTypeId,
    required List<ProjectMetadata> knownProjects,
  }) async {
    ProjectMetadata? meta = knownProjects.firstWhereOrNull(
      (p) => p.rootUri == folder.uri && p.projectTypeId == projectTypeId,
    );

    final bool isNew = meta == null;
    meta ??= _createNewProjectMetadata(
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
    final fileHandler = LocalFileHandlerFactory.create();
    final ProjectRepository repo;

    if (metadata.projectTypeId == 'local_persistent') {
      final projectDataPath = await _ensureProjectDataFolder(
        fileHandler,
        metadata.rootUri,
      );
      // REFACTOR: Pass the ref to the repository constructor
      repo = PersistentProjectRepository(fileHandler, projectDataPath, _ref);
    } else if (metadata.projectTypeId == 'simple_local') {
      // REFACTOR: Pass the ref to the repository constructor
      repo = SimpleProjectRepository(fileHandler, projectStateJson, _ref);
    } else {
      throw UnimplementedError(
        'No repository for project type ${metadata.projectTypeId}',
      );
    }

    _ref.read(projectRepositoryProvider.notifier).state = repo;
    return await repo.loadProject(metadata);
  }

  // ... (saveProject is unchanged) ...
  Future<void> saveProject(Project project) async {
    final repo = _ref.read(projectRepositoryProvider);
    await repo?.saveProject(project);
  }
  
  Future<void> closeProject(Project project) async {
    await saveProject(project);

    // REFACTOR: Clear the hierarchy cache on project close.
    _ref.read(projectRepositoryProvider)?.hierarchyCache.clear();

    for (final tab in project.session.tabs) {
      tab.plugin.deactivateTab(tab, _ref);
      tab.plugin.disposeTab(tab);
      tab.dispose();
    }
    _ref.read(projectRepositoryProvider.notifier).state = null;
  }
  // ... (_createNewProjectMetadata and _ensureProjectDataFolder are unchanged) ...

  ProjectMetadata _createNewProjectMetadata({
    required String rootUri,
    required String name,
    required String projectTypeId,
  }) {
    return ProjectMetadata(
      id: const Uuid().v4(),
      name: name,
      rootUri: rootUri,
      projectTypeId: projectTypeId,
      lastOpenedDateTime: DateTime.now(),
    );
  }

  Future<String> _ensureProjectDataFolder(
    FileHandler handler,
    String projectRootUri,
  ) async {
    final files = await handler.listDirectory(
      projectRootUri,
      includeHidden: true,
    );
    final machineDir = files.firstWhereOrNull(
      (f) => f.name == '.machine' && f.isDirectory,
    );
    final dir = machineDir ??
        await handler.createDocumentFile(
          projectRootUri,
          '.machine',
          isDirectory: true,
        );
    return dir.uri;
  }
}