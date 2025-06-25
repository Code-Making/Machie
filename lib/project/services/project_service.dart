// =========================================
// FILE: lib/project/services/project_service.dart
// =========================================

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/file_handler/file_handler.dart';
import '../../data/file_handler/local_file_handler.dart';
import '../../data/repositories/persistent_project_repository.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/simple_project_repository.dart';
import '../project_models.dart';
import '../../editor/editor_tab_models.dart';
import '../../editor/tab_state_manager.dart';
import '../../editor/plugins/plugin_registry.dart';
import '../../logs/logs_provider.dart';

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

  // REFACTORED: This method is now correct and simplified.
  // It determines the metadata for the project, then calls the main
  // openProject method which handles loading AND rehydration.
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
    
    // Call the main, authoritative openProject method. It will return a
    // fully loaded and rehydrated project.
    final project = await openProject(meta);
    
    return OpenProjectResult(project: project, metadata: meta, isNew: isNew);
  }

  Future<Project> openProject(
    ProjectMetadata metadata, {
    Map<String, dynamic>? projectStateJson,
  }) async {
    final fileHandler = LocalFileHandlerFactory.create();
    
    // For local_persistent, we need to ensure the .machine folder exists to read from it.
    // This setup step is necessary before creating the repository.
    if (metadata.projectTypeId == 'local_persistent') {
      await _ensureProjectDataFolder(fileHandler, metadata.rootUri);
    }
    
    final repo = _createRepository(metadata, projectStateJson, fileHandler);
    _ref.read(projectRepositoryProvider.notifier).state = repo;
    
    final loadedProject = await repo.loadProject(metadata);

    final rehydratedSession = await _rehydrateSession(loadedProject.session, repo);
    
    return loadedProject.copyWith(session: rehydratedSession);
  }

  ProjectRepository _createRepository(ProjectMetadata metadata, Map<String, dynamic>? projectStateJson, FileHandler fileHandler) {
      if (metadata.projectTypeId == 'local_persistent') {
        final projectDataPath = metadata.rootUri + '/.machine'; // Simplification
        return PersistentProjectRepository(fileHandler, projectDataPath);
      } else if (metadata.projectTypeId == 'simple_local') {
        return SimpleProjectRepository(fileHandler, projectStateJson);
      } else {
        throw UnimplementedError('No repository for project type ${metadata.projectTypeId}');
      }
  }

  Future<TabSessionState> _rehydrateSession(TabSessionState persistedSession, ProjectRepository repo) async {
    // ... logic from previous step is correct ...
    final plugins = _ref.read(activePluginsProvider);
    final metadataNotifier = _ref.read(tabMetadataProvider.notifier);

    final persistedMetadataMap = persistedSession.tabMetadata;
    final persistedTabsJson = persistedSession.tabs.map((t) => t.toJson()).toList();

    final Map<String, Map<String, dynamic>> tabJsonMap = {
      for (var json in persistedTabsJson) json['id']: json
    };

    final List<EditorTab> rehydratedTabs = [];

    for (final tabJson in persistedTabsJson) {
      final tabId = tabJson['id'] as String?;
      final pluginType = tabJson['pluginType'] as String?;
      final persistedMetadata = persistedMetadataMap[tabId];

      if (tabId == null || pluginType == null || persistedMetadata == null) {
        _ref.read(talkerProvider).warning('Skipping rehydration for incomplete tab data: $tabJson');
        continue;
      }
      
      final plugin = plugins.firstWhereOrNull((p) => p.runtimeType.toString() == pluginType);
      if (plugin == null) continue;
      
      try {
        final file = await repo.fileHandler.getFileMetadata(persistedMetadata.file.uri);
        if (file == null) continue;
        
        final dynamic data = plugin.dataRequirement == PluginDataRequirement.bytes
            ? await repo.fileHandler.readFileAsBytes(file.uri)
            : await repo.fileHandler.readFile(file.uri);
        
        final newTab = await plugin.createTab(file, data, id: tabId);
        
        metadataNotifier.state[newTab.id] = TabMetadata(
          file: file,
          isDirty: persistedMetadata.isDirty,
        );
        
        rehydratedTabs.add(newTab);
        
      } catch (e, st) {
        _ref.read(talkerProvider).handle(e, st, 'Could not restore tab for ${persistedMetadata.file.uri}');
      }
    }
    
    return persistedSession.copyWith(tabs: rehydratedTabs, tabMetadata: {});
  }

  Future<void> saveProject(Project project) async {
    final repo = _ref.read(projectRepositoryProvider);
    final liveMetadata = _ref.read(tabMetadataProvider);
    final projectToSave = project.copyWith(
      session: project.session.copyWith(tabMetadata: liveMetadata),
    );
    await repo?.saveProject(projectToSave);
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