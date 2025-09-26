// =========================================
// FILE: lib/project/services/project_service.dart
// =========================================

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/dto/project_dto.dart';
import '../../data/file_handler/file_handler.dart';
import '../../data/file_handler/local_file_handler.dart';
import '../../data/repositories/persistent_project_repository.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/simple_project_repository.dart';
import '../project_models.dart';
import '../../editor/tab_state_manager.dart';
// ADDED

final projectServiceProvider = Provider<ProjectService>((ref) {
  return ProjectService(ref);
});

/// A result object for the `openFromFolder` flow.
class OpenProjectResult {
  final ProjectDto projectDto;
  final ProjectMetadata metadata;
  final bool isNew;

  OpenProjectResult({
    required this.projectDto,
    required this.metadata,
    required this.isNew,
  });
}

class ProjectService {
  final Ref _ref;
  ProjectService(this._ref);

  /// Opens a project from a user-picked folder, creating new metadata if needed.
  /// This method returns the raw DTO, leaving rehydration to the caller.
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

    final projectDto = await openProjectDto(meta);
    return OpenProjectResult(
      projectDto: projectDto,
      metadata: meta,
      isNew: isNew,
    );
  }

  /// Selects the correct repository and asks it to load the persisted `ProjectDto`.
  /// This is the primary entry point for loading project data.
  Future<ProjectDto> openProjectDto(
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
      repo = PersistentProjectRepository(fileHandler, projectDataPath);
    } else if (metadata.projectTypeId == 'simple_local') {
      // For simple, non-persistent projects, the entire state is passed in.
      // The repository will construct a DTO from this JSON.
      repo = SimpleProjectRepository(fileHandler, projectStateJson);
    } else {
      throw UnimplementedError(
        'No repository for project type ${metadata.projectTypeId}',
      );
    }

    // Set the active repository for other parts of the app to use for file ops.
    _ref.read(projectRepositoryProvider.notifier).state = repo;

    // The repository's loadProjectDto method is the single source of truth for
    // loading the raw, persisted data.
    return await repo.loadProjectDto();
  }

  /// Saves the current live project state.
  /// It orchestrates the conversion from a domain model to a DTO before saving.
  Future<void> saveProject(Project project) async {
    final repo = _ref.read(projectRepositoryProvider);
    if (repo == null) return;

    final liveMetadata = _ref.read(tabMetadataProvider);
    final projectDto = project.toDto(liveMetadata);

    await repo.saveProjectDto(projectDto);
  }

  Future<void> closeProject(Project project) async {
    // Save the project's final state (list of tabs, etc.).
    await saveProject(project);

    // Deactivate and dispose all live tab widgets and controllers.
    for (final tab in project.session.tabs) {
      tab.plugin.deactivateTab(tab, _ref);
      tab.plugin.disposeTab(tab);
      tab.dispose();
    }

    // Clear the active project-specific providers.
    _ref.read(projectRepositoryProvider.notifier).state = null;
    _ref.read(tabMetadataProvider.notifier).clear();
  }

  /// Creates a new metadata object for a new project.
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

  /// Ensures the hidden `.machine` directory exists for persistent projects.
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
    final dir =
        machineDir ??
        await handler.createDocumentFile(
          projectRootUri,
          '.machine',
          isDirectory: true,
        );
    return dir.uri;
  }
}
