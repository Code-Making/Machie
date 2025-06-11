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
import 'simple_local_file_project.dart';

// --- Abstraction ---

abstract class ProjectFactory {
  String get projectTypeId;
  String get name; // NEW: User-friendly name for the UI
  String get description; // NEW: Description for the UI

  Future<Project> open(
    ProjectMetadata metadata,
    Ref ref, {
    Map<String, dynamic>? projectStateJson,
  });
}

// --- Registry ---

final projectFactoryRegistryProvider = Provider<Map<String, ProjectFactory>>((ref) {
  return {
    // MODIFIED: Use the factories' IDs as keys.
    LocalProjectFactory().projectTypeId: LocalProjectFactory(),
    SimpleLocalProjectFactory().projectTypeId: SimpleLocalProjectFactory(),
  };
});

// --- Concrete Implementations ---

// NEW Factory for SimpleLocalFileProject
class SimpleLocalProjectFactory implements ProjectFactory {
  @override
  String get projectTypeId => 'simple_local';

  @override
  String get name => 'Simple Project'; // NEW

  @override
  String get description =>
      'A temporary project. No files are created in the project folder. Session is discarded when another project is opened.'; // NEW

  @override
  Future<Project> open(
    ProjectMetadata metadata,
    Ref ref, {
    Map<String, dynamic>? projectStateJson,
  }) async {
    final handler = LocalFileHandlerFactory.create();
    SessionState session = const SessionState();

    if (projectStateJson != null) {
      // Rehydrate session from AppState
      final sessionJson = projectStateJson['session'] as Map<String, dynamic>? ?? {};
      final tabs = await _rehydrateTabs(sessionJson, handler, ref);
      session = SessionState(
        tabs: tabs,
        currentTabIndex: sessionJson['currentTabIndex'] ?? 0,
      );
    }

    return SimpleLocalFileProject(
      metadata: metadata,
      fileHandler: handler,
      session: session,
    );
  }
}

// MODIFIED LocalProjectFactory to align with new interface
class LocalProjectFactory implements ProjectFactory {
  @override
  String get projectTypeId => 'local_persistent';

  @override
  String get name => 'Persistent Project'; // NEW

  @override
  String get description =>
      'Saves session data and settings in a hidden ".machine" folder within your project directory.'; // NEW

  @override
  Future<Project> open(
    ProjectMetadata metadata,
    Ref ref, {
    Map<String, dynamic>? projectStateJson, // This will be ignored for this type
  }) async {
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
    final tabs = await _rehydrateTabs(sessionJson, handler, ref);
    return LocalProject(
      metadata: metadata,
      fileHandler: handler,
      session: SessionState(
        tabs: tabs,
        currentTabIndex: sessionJson['currentTabIndex'] ?? 0,
      ),
      projectDataPath: projectDataPath,
      // Pass the deserialized values here.
      expandedFolders: Set<String>.from(json['expandedFolders'] ?? []),
      fileExplorerViewMode: FileExplorerViewMode.values.firstWhere(
        (e) => e.name == json['fileExplorerViewMode'],
        orElse: () => FileExplorerViewMode.sortByNameAsc,
      ),
    );
  }
}

// --- Helper function (extracted and shared) ---
Future<List<EditorTab>> _rehydrateTabs(
  Map<String, dynamic> sessionJson,
  FileHandler handler,
  Ref ref,
) async {
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
  return tabs;
}