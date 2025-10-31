// =========================================
// lib/project/services/project_service.dart
// =========================================

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:uuid/uuid.dart';

import '../../data/cache/hot_state_cache_service.dart';
import '../../data/dto/project_dto.dart';
import '../../data/file_handler/file_handler.dart';
import '../../data/file_handler/local_file_handler.dart';
import '../../data/repositories/persistent_project_repository.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/simple_project_repository.dart';
import '../../editor/tab_state_manager.dart';
import '../project_models.dart';
import '../../editor/services/file_content_provider.dart';

final projectServiceProvider = Provider<ProjectService>((ref) {
  return ProjectService(ref);
});

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

class ProjectPermissionDeniedException implements Exception {
  final ProjectMetadata metadata;
  final String deniedUri;

  ProjectPermissionDeniedException({
    required this.metadata,
    required this.deniedUri,
  });

  @override
  String toString() =>
      'Permission was denied for project "${metadata.name}" at URI: $deniedUri';
}

class ProjectService {
  final Ref _ref;
  ProjectService(this._ref);

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

  Future<ProjectDto> openProjectDto(
    ProjectMetadata metadata, {
    Map<String, dynamic>? projectStateJson,
  }) async {
    final fileHandler = LocalFileHandlerFactory.create();
    final ProjectRepository repo;

    if (!await fileHandler.hasPermission(metadata.rootUri)) {
      // If we don't have permission, we immediately throw our custom exception.
      // This bypasses the silent failure of `listDirectory` and triggers
      // the recovery flow in the AppNotifier.
      throw ProjectPermissionDeniedException(
        metadata: metadata,
        deniedUri: metadata.rootUri,
      );
    }

    if (metadata.projectTypeId == 'local_persistent') {
      // We still need to handle a potential permission error here,
      // as creating the .machine folder is a file operation.
      try {
        final projectDataPath = await _ensureProjectDataFolder(
          fileHandler,
          metadata.rootUri,
        );
        repo = PersistentProjectRepository(fileHandler, projectDataPath);
      } on PermissionDeniedException catch (e) {
        // Re-throw with more context if this specific operation fails.
        throw ProjectPermissionDeniedException(
          metadata: metadata,
          deniedUri: e.uri,
        );
      }
    } else {
      // 'simple_local'
      repo = SimpleProjectRepository(fileHandler, projectStateJson);
    }

    _ref.read(projectRepositoryProvider.notifier).state = repo;

    try {
      // Attempt to load the project state.
      return await repo.loadProjectDto();
    } on PermissionDeniedException catch (e) {
      // If loading fails due to permissions, catch the low-level exception
      // and re-throw our new, high-level exception with all the context.
      throw ProjectPermissionDeniedException(
        metadata: metadata,
        deniedUri: e.uri,
      );
    }
  }

  Future<void> saveProject(Project project) async {
    final repo = _ref.read(projectRepositoryProvider);
    if (repo == null) return;

    final liveMetadata = _ref.read(tabMetadataProvider);
    // THE FIX: The registry is now read from the ref and passed to toDto.
    final registry = _ref.read(fileContentProviderRegistryProvider);
    final projectDto = project.toDto(liveMetadata, registry);

    await repo.saveProjectDto(projectDto);
  }

  Future<void> closeProject(Project project) async {
    await saveProject(project);

    for (final tab in project.session.tabs) {
      tab.plugin.deactivateTab(tab, _ref);
      tab.plugin.disposeTab(tab);
      tab.dispose();
    }

    // if (await FlutterForegroundTask.isRunningService) {
    //   FlutterForegroundTask.sendDataToTask({
    //     'command': 'clear_project',
    //     'projectId': project.id,
    //   });
    // }

    // await _ref.read(hotStateCacheServiceProvider).clearProjectCache(project.id);

    _ref.read(projectRepositoryProvider.notifier).state = null;
    _ref.read(tabMetadataProvider.notifier).clear();

    // FIX: Removed the call to _stopCacheService(). It is now handled globally.
  }

  Future<bool> reGrantPermissionForProject(ProjectMetadata metadata) async {
    // This service knows that "local" projects use a LocalFileHandler.
    // Future project types (e.g., 'git_project') could have different logic here.
    if (metadata.projectTypeId == 'local_persistent' ||
        metadata.projectTypeId == 'simple_local') {
      final handler = LocalFileHandlerFactory.create();
      return await handler.reRequestPermission(metadata.rootUri);
    }

    // For unknown or unsupported project types, we cannot re-grant.
    return false;
  }

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
