// lib/project/local_file_system_project.dart
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/file_handler/file_handler.dart';
import '../../editors/plugins/plugin_models.dart';
import '../../editors/plugins/plugin_registry.dart';
import '../../editors/editor_tab_models.dart';
import '../project_models.dart';
import '../../explorer/explorer_workspace_service.dart'; // NEW IMPORT

class LocalProject extends Project {
  String projectDataPath;

  LocalProject({
    required super.metadata,
    required super.fileHandler,
    required super.session,
    required this.projectDataPath,
  });

  LocalProject copyWith({ProjectMetadata? metadata, TabSessionState? session}) {
    return LocalProject(
      metadata: metadata ?? this.metadata,
      fileHandler: fileHandler,
      session: session ?? this.session.copyWith(),
      projectDataPath: projectDataPath,
    );
  }

  @override
  Future<void> save() async {
    final content = jsonEncode(toJson());
    await fileHandler.createDocumentFile(
      projectDataPath,
      'project_data.json',
      initialContent: content,
      overwrite: true,
    );
  }

  @override
  Future<void> close({required Ref ref}) async {
    await save();
    for (final tab in session.tabs) {
      tab.plugin.deactivateTab(tab, ref);
      tab.plugin.disposeTab(tab); // MODIFIED: Added disposeTab call
      tab.dispose();
    }
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': metadata.id,
    'session': session.toJson(),
  };

  @override
  Future<Map<String, dynamic>?> loadPluginState(
    String pluginId, {
    required ExplorerWorkspaceService workspaceService,
  }) {
    return workspaceService.loadPluginState(
      fileHandler,
      projectDataPath,
      pluginId,
    );
  }

  @override
  Future<void> savePluginState(
    String pluginId,
    Map<String, dynamic> stateJson, {
    required ExplorerWorkspaceService workspaceService,
  }) {
    return workspaceService.savePluginState(
      fileHandler,
      projectDataPath,
      pluginId,
      stateJson,
    );
  }

  @override
  Future<void> saveActiveExplorer(
    String pluginId, {
    required ExplorerWorkspaceService workspaceService,
  }) {
    return workspaceService.saveActiveExplorer(
      fileHandler,
      projectDataPath,
      pluginId,
    );
  }

  @override
  Future<String?> loadActiveExplorer({
    required ExplorerWorkspaceService workspaceService,
  }) async {
    final state = await workspaceService.loadFullState(
      fileHandler,
      projectDataPath,
    );
    return state.activeExplorerPluginId;
  }

  // ALL SESSION LOGIC (openFile, closeTab, etc.) remains here as before.
  // ...
  void _handlePluginLifecycle(EditorTab? oldTab, EditorTab? newTab, Ref ref) {
    if (oldTab != null) oldTab.plugin.deactivateTab(oldTab, ref);
    if (newTab != null) newTab.plugin.activateTab(newTab, ref);
  }

  // MODIFIED: Made async and now reads file content.
  @override
  Future<Project> openFile(
    DocumentFile file, {
    EditorPlugin? plugin,
    required Ref ref,
  }) async {
    final existingIndex = session.tabs.indexWhere(
      (t) => t.file.uri == file.uri,
    );
    if (existingIndex != -1) {
      return switchTab(existingIndex, ref: ref);
    }

    final plugins = ref.read(activePluginsProvider);
    final selectedPlugin =
        plugin ?? plugins.firstWhere((p) => p.supportsFile(file));

    // Read data based on plugin requirement
    final dynamic data;
    if (selectedPlugin.dataRequirement == PluginDataRequirement.bytes) {
      data = await fileHandler.readFileAsBytes(file.uri);
    } else {
      data = await fileHandler.readFile(file.uri);
    }

    final newTab = await selectedPlugin.createTab(file, data);

    final oldTab = session.currentTab;
    final newSession = session.copyWith(
      tabs: [...session.tabs, newTab],
      currentTabIndex: session.tabs.length,
    );
    _handlePluginLifecycle(oldTab, newTab, ref);
    return copyWith(session: newSession);
  }

  @override
  Project switchTab(int index, {required Ref ref}) {
    final oldTab = session.currentTab;
    final newSession = session.copyWith(currentTabIndex: index);
    final newProject = copyWith(session: newSession);
    final newTab = newProject.session.currentTab;
    _handlePluginLifecycle(oldTab, newTab, ref);
    return newProject;
  }

  @override
  Project closeTab(int index, {required Ref ref}) {
    final closedTab = session.tabs[index];
    final oldTab = session.currentTab;
    final newTabs = List<EditorTab>.from(session.tabs)..removeAt(index);
    int newCurrentIndex;
    if (newTabs.isEmpty) {
      newCurrentIndex = 0;
    } else {
      final oldIndex = session.currentTabIndex;
      if (oldIndex > index) {
        newCurrentIndex = oldIndex - 1;
      } else if (oldIndex == index) {
        newCurrentIndex = (oldIndex - 1).clamp(0, newTabs.length - 1);
      } else {
        newCurrentIndex = oldIndex;
      }
    }
    final newProject = copyWith(
      session: session.copyWith(
        tabs: newTabs,
        currentTabIndex: newCurrentIndex,
      ),
    );
    closedTab.plugin.deactivateTab(closedTab, ref);
    closedTab.plugin.disposeTab(closedTab); // MODIFIED: Added disposeTab call
    closedTab.dispose();
    final newTab = newProject.session.currentTab;
    if (oldTab != newTab) {
      newTab?.plugin.activateTab(newTab, ref);
    }
    return newProject;
  }

  @override
  Project reorderTabs(int oldIndex, int newIndex) {
    final currentOpenTab = session.currentTab;
    final newTabs = List<EditorTab>.from(session.tabs);
    final movedTab = newTabs.removeAt(oldIndex);
    if (oldIndex < newIndex) newIndex--;
    newTabs.insert(newIndex, movedTab);
    final newCurrentIndex =
        currentOpenTab != null ? newTabs.indexOf(currentOpenTab) : 0;
    return copyWith(
      session: session.copyWith(
        tabs: newTabs,
        currentTabIndex: newCurrentIndex,
      ),
    );
  }

  @override
  Project updateTab(int tabIndex, EditorTab newTab) {
    if (tabIndex < 0 || tabIndex >= session.tabs.length) return this;
    final newTabs = List<EditorTab>.from(session.tabs);
    newTabs[tabIndex] = newTab;
    return copyWith(session: session.copyWith(tabs: newTabs));
  }
}
