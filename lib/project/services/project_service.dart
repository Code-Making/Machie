// =========================================
// FINAL CORRECTED FILE (for real this time): lib/project/services/project_service.dart
// =========================================
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../data/dto/project_dto.dart';
import '../../data/file_handler/file_handler.dart';
import '../../data/file_handler/local_file_handler.dart';
import '../../data/repositories/persistent_project_repository.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/simple_project_repository.dart';
import '../project_models.dart';
import '../../editor/tab_state_manager.dart';
import 'hot_state_task_handler.dart';

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

    if (metadata.projectTypeId == 'local_persistent') {
      final projectDataPath = await _ensureProjectDataFolder(
        fileHandler,
        metadata.rootUri,
      );
      repo = PersistentProjectRepository(fileHandler, projectDataPath);
    } else if (metadata.projectTypeId == 'simple_local') {
      repo = SimpleProjectRepository(fileHandler, projectStateJson);
    } else {
      throw UnimplementedError(
        'No repository for project type ${metadata.projectTypeId}',
      );
    }

    _startCacheService();

    _ref.read(projectRepositoryProvider.notifier).state = repo;
    return await repo.loadProjectDto();
  }

  Future<void> saveProject(Project project) async {
    final repo = _ref.read(projectRepositoryProvider);
    if (repo == null) return;

    final liveMetadata = _ref.read(tabMetadataProvider);
    final projectDto = project.toDto(liveMetadata);

    await repo.saveProjectDto(projectDto);
  }

  Future<void> closeProject(Project project) async {
    await saveProject(project);

    for (final tab in project.session.tabs) {
      tab.plugin.deactivateTab(tab, _ref);
      tab.plugin.disposeTab(tab);
      tab.dispose();
    }
    
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask({
        'command': 'clear_project',
        'projectId': project.id,
      });
    }

    _ref.read(projectRepositoryProvider.notifier).state = null;
    _ref.read(tabMetadataProvider.notifier).clear();

    _stopCacheService();
  }

  void _startCacheService() async {
    if (await FlutterForegroundTask.isRunningService) {
      return;
    }

    // CORRECTED: Follow the documentation example exactly. By passing null,
    // the package will use the default app launcher icon, which is what we want.
    // This removes the dependency on the incorrect NotificationIcon constructor.
    FlutterForegroundTask.startService(
      notificationTitle: 'Machine Active',
      notificationText: 'Unsaved file cache is running.',
      notificationIcon: null,
      callback: startCallback,
    );
  }

  void _stopCacheService() async {
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.stopService();
    }
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
    final dir = machineDir ??
        await handler.createDocumentFile(
          projectRootUri,
          '.machine',
          isDirectory: true,
        );
    return dir.uri;
  }
}