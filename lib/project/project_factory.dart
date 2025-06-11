// lib/project/project_factory.dart
import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/file_handler/file_handler.dart';
import '../data/file_handler/local_file_handler.dart';
import '../plugins/plugin_models.dart';
import '../plugins/plugin_registry.dart';
import '../session/session_models.dart';
import 'local_file_system_project.dart';
import 'project_models.dart';

// --- Abstraction ---

abstract class ProjectFactory {
  ProjectType get type;
  Future<Project> open(ProjectMetadata metadata, Ref ref);
}

// --- Registry ---

final projectFactoryRegistryProvider = Provider<Map<ProjectType, ProjectFactory>>((ref) {
  // Register all known project factories here. This makes the system pluggable.
  return {
    ProjectType.local: LocalProjectFactory(),
  };
});

// --- Concrete Implementation ---

class LocalProjectFactory implements ProjectFactory {
  @override
  ProjectType get type => ProjectType.local;

  @override
  Future<Project> open(ProjectMetadata metadata, Ref ref) async {
    final handler = LocalFileHandlerFactory.create();
    final projectDataDir = await _ensureProjectDataFolder(handler, metadata.rootUri);
    final files = await handler.listDirectory(projectDataDir.uri, includeHidden: true);
    final projectDataFile = files.firstWhereOrNull((f) => f.name == 'project_data.json');

    if (projectDataFile != null) {
      final content = await handler.readFile(projectDataFile.uri);
      final json = jsonDecode(content);
      return _createLocalProjectFromJson(metadata, handler, projectDataDir.uri, json, ref);
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

  Future<DocumentFile> _ensureProjectDataFolder(FileHandler handler, String projectRootUri) async {
    final files = await handler.listDirectory(projectRootUri, includeHidden: true);
    final machineDir = files.firstWhereOrNull((f) => f.name == '.machine' && f.isDirectory);
    return machineDir ?? await handler.createDocumentFile(projectRootUri, '.machine', isDirectory: true);
  }

  Future<Project> _createLocalProjectFromJson(
    ProjectMetadata metadata,
    FileHandler handler,
    String projectDataPath,
    Map<String, dynamic> json,
    Ref ref,
  ) async {
    final sessionJson = json['session'] as Map<String, dynamic>? ?? {};
    final tabsJson = sessionJson['tabs'] as List<dynamic>? ?? [];
    final plugins = ref.read(activePluginsProvider);

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