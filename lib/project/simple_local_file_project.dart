// lib/project/simple_local_file_project.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/file_handler/file_handler.dart';
import '../plugins/plugin_models.dart';
import '../plugins/plugin_registry.dart';
import '../session/session_models.dart';
import 'project_models.dart';
import 'workspace_service.dart'; // NEW IMPORT

/// An implementation for projects that don't have persistent state on disk
/// (like a .machine folder). Their state is managed by AppState instead.
class SimpleLocalFileProject extends Project {
  // Simple projects don't have extra properties like expandedFolders.
  // That state is part of the session, which is what gets saved.

  SimpleLocalFileProject({
    required super.metadata,
    required super.fileHandler,
    required super.session,
  });

  SimpleLocalFileProject copyWith({
    ProjectMetadata? metadata,
    SessionState? session,
  }) {
    return SimpleLocalFileProject(
      metadata: metadata ?? this.metadata,
      fileHandler: fileHandler,
      session: session ?? this.session.copyWith(),
    );
  }

  // --- Lifecycle Implementations ---
  // These are no-ops because AppState persistence handles it.
  @override
  Future<void> save() async {}

  @override
  Future<void> close({required Ref ref}) async {
    for (final tab in session.tabs) {
      tab.plugin.deactivateTab(tab, ref);
      tab.plugin.disposeTab(tab); // MODIFIED: Added disposeTab call
      tab.dispose();
    }
  }

  // This project type does not persist workspace state, so these are no-ops.
  @override
  Future<Map<String, dynamic>?> loadPluginState(
    String pluginId, {
    required WorkspaceService workspaceService,
  }) async {
    return null;
  }

  @override
  Future<void> savePluginState(
    String pluginId,
    Map<String, dynamic> stateJson, {
    required WorkspaceService workspaceService,
  }) async {}

  @override
  Future<void> saveActiveExplorer(
    String pluginId, {
    required WorkspaceService workspaceService,
  }) async {}

  @override
  Future<String?> loadActiveExplorer({
    required WorkspaceService workspaceService,
  }) async {
    return null;
  }

  // --- Session Logic ---
  // This logic is identical to LocalProject. In a larger app, this could be
  // extracted into a mixin `LocalProjectSessionMixin on Project`. For now,
  // duplication is acceptable to keep it simple.

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
      if (oldIndex > index)
        newCurrentIndex = oldIndex - 1;
      else if (oldIndex == index)
        newCurrentIndex = (oldIndex - 1).clamp(0, newTabs.length - 1);
      else
        newCurrentIndex = oldIndex;
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

  // --- Other session methods ---
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

  @override
  Map<String, dynamic> toJson() => {
    'session': session.toJson(),
    // Simple project does not have other state like expandedFolders to save.
  };
}
