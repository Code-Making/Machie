// =========================================
// FILE: lib/project/services/project_service.dart
// =========================================

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
import '../../editor/tab_state_manager.dart';
import 'package:machine/data/dto/project_dto.dart'; // ADDED

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

  // REFACTORED: openProject now returns the DTO. The service layer's caller
  // will be responsible for rehydrating it.
  Future<ProjectDto> openProjectDto(
    ProjectMetadata metadata, {
    Map<String, dynamic>? projectStateJson,
  }) async {
    // ... (logic to create the correct repository is the same) ...
    
    // The repository now returns a DTO.
    return await repo.loadProjectDto();
  }

  // REFACTORED: saveProject now orchestrates the conversion to a DTO.
  Future<void> saveProject(Project project) async {
    final repo = _ref.read(projectRepositoryProvider);
    final liveMetadata = _ref.read(tabMetadataProvider);
    
    // 1. Convert live domain object to DTO.
    final projectDto = project.toDto(liveMetadata);
    
    // 2. Pass DTO to the repository.
    await repo?.saveProjectDto(projectDto);
  }

  Future<void> closeProject(Project project) async {
    await saveProject(project);

    for (final tab in project.session.tabs) {
      tab.plugin.deactivateTab(tab, _ref);
      tab.plugin.disposeTab(tab);
      tab.dispose();
    }
    _ref.read(projectRepositoryProvider.notifier).state = null;
    _ref.read(tabMetadataProvider.notifier).state = {};
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