// lib/project/project_manager.dart
import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../plugins/plugin_models.dart';
import '../plugins/plugin_registry.dart';
import '../session/session_models.dart';
import '../data/file_handler/file_handler.dart';
import '../data/file_handler/local_file_handler.dart';
import 'project_models.dart';

final projectManagerProvider = Provider<ProjectManager>((ref) {
  return ProjectManager(ref);
});

// This service handles the business logic of opening, closing, and saving projects.
class ProjectManager {
  final Ref _ref;

  ProjectManager(this._ref);

  Future<Project> openProject(ProjectMetadata metadata) async {
    final FileHandler handler;
    switch (metadata.projectType) {
      case ProjectType.local:
        handler = LocalFileHandlerFactory.create();
        break;
    }

    final projectDataDir = await _ensureProjectDataFolder(handler, metadata.rootUri);
    final files = await handler.listDirectory(projectDataDir.uri, includeHidden: true);
    final projectDataFile = files.firstWhereOrNull((f) => f.name == 'project_data.json');

    if (projectDataFile != null) {
      final content = await handler.readFile(projectDataFile.uri);
      final json = jsonDecode(content);
      return await _createLocalProjectFromJson(metadata, handler, projectDataDir.uri, json);
    } else {
      return LocalProject(
        metadata: metadata,
        fileHandler: handler,
        session: const SessionState(),
        projectDataPath: projectDataDir.uri,
        expandedFolders: {metadata.rootUri},
      );
    }
  }

  Future<void> saveProject(Project project) async {
    if (project is! LocalProject) return; // Only local projects can be saved for now

    final content = jsonEncode(project.toJson());
    await project.fileHandler.createDocumentFile(
      project.projectDataPath,
      'project_data.json',
      initialContent: content,
      overwrite: true,
    );
  }

  Future<ProjectMetadata> createNewProjectMetadata(String rootUri, String name) async {
    return ProjectMetadata(
      id: const Uuid().v4(),
      name: name,
      rootUri: rootUri,
      projectType: ProjectType.local,
      lastOpenedDateTime: DateTime.now(),
    );
  }

  Future<DocumentFile> _ensureProjectDataFolder(FileHandler handler, String projectRootUri) async {
    final files = await handler.listDirectory(projectRootUri, includeHidden: true);
    final machineDir = files.firstWhereOrNull((f) => f.name == '.machine' && f.isDirectory);
    return machineDir ?? await handler.createDocumentFile(projectRootUri, '.machine', isDirectory: true);
  }

  Future<Project> _createLocalProjectFromJson(ProjectMetadata metadata, FileHandler handler, String projectDataPath, Map<String, dynamic> json) async {
    final sessionJson = json['session'] as Map<String, dynamic>? ?? {};
    final tabsJson = sessionJson['tabs'] as List<dynamic>? ?? [];
    final plugins = _ref.read(activePluginsProvider);

    final List<EditorTab> tabs = [];
    for (final tabJson in tabsJson) {
      final pluginType = tabJson['pluginType'] as String?;
      if (pluginType == null) continue;
      
      final plugin = plugins.firstWhereOrNull((p) => p.runtimeType.toString() == pluginType);
      if (plugin != null) {
        try {
          final tab = await plugin.createTabFromSerialization(tabJson, handler);
          tabs.add(tab);
        } catch (e) {
          print('Could not restore tab: $e');
        }
      }
    }

    return LocalProject(
      metadata: metadata,
      fileHandler: handler,
      session: SessionState(
        tabs: tabs,
        currentTabIndex: sessionJson['currentTabIndex'] ?? 0,
      ),
      projectDataPath: projectDataPath,
      expandedFolders: Set<String>.from(json['expandedFolders'] ?? []),
      fileExplorerViewMode: FileExplorerViewMode.values.firstWhere(
        (e) => e.name == json['fileExplorerViewMode'],
        orElse: () => FileExplorerViewMode.sortByNameAsc,
      ),
    );
  }
}