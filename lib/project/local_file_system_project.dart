// lib/project/local_file_system_project.dart
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/file_handler/file_handler.dart';
import '../plugins/plugin_models.dart';
import '../plugins/plugin_registry.dart';
import '../session/session_models.dart';
import 'project_models.dart';
import 'simple_local_file_project.dart';
import 'workspace_service.dart'; // NEW IMPORT

class LocalProject extends Project {
  String projectDataPath;

  LocalProject({
    required super.metadata,
    required super.fileHandler,
    required super.session,
    required this.projectDataPath,
  });

  LocalProject copyWith({
    ProjectMetadata? metadata,
    SessionState? session,
  }) {
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
      tab.dispose();
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': metadata.id,
        'session': session.toJson(),
      };
      
  @override
  Future<Map<String, dynamic>?> loadPluginState(String pluginId, {required WorkspaceService workspaceService}) {
    return workspaceService.loadPluginState(fileHandler, projectDataPath, pluginId);
  }

  @override
  Future<void> savePluginState(String pluginId, Map<String, dynamic> stateJson, {required WorkspaceService workspaceService}) {
    return workspaceService.savePluginState(fileHandler, projectDataPath, pluginId, stateJson);
  }

  @override
  Future<void> saveActiveExplorer(String pluginId, {required WorkspaceService workspaceService}) {
    return workspaceService.saveActiveExplorer(fileHandler, projectDataPath, pluginId);
  }

  @override
  Future<String?> loadActiveExplorer({required WorkspaceService workspaceService}) async {
    final state = await workspaceService.loadFullState(fileHandler, projectDataPath);
    return state.activeExplorerPluginId;
  }

  // ALL SESSION LOGIC (openFile, closeTab, etc.) remains here as before.
  // ...
  void _handlePluginLifecycle(EditorTab? oldTab, EditorTab? newTab, Ref ref) {
    if (oldTab != null) oldTab.plugin.deactivateTab(oldTab, ref);
    if (newTab != null) newTab.plugin.activateTab(newTab, ref);
  }

  // MODIFIED: This method now contains the core orchestration logic.
  @override
  Future<void> openFile(DocumentFile file, {EditorPlugin? explicitPlugin}) async {
    final project = state.value?.currentProject;
    if (project == null) return;
    
    EditorPlugin? chosenPlugin = explicitPlugin;

    if (chosenPlugin == null) {
      // Find all compatible plugins for this file type.
      final compatiblePlugins = ref.read(activePluginsProvider)
          .where((p) => p.supportsFile(file))
          .toList();

      if (compatiblePlugins.isEmpty) {
        _showErrorSnackbar("No plugin available to open '${file.name}'.");
        return;
      } else if (compatiblePlugins.length > 1) {
        // More than one plugin, ask the user to choose.
        chosenPlugin = await _showOpenWithDialog(compatiblePlugins);
        if (chosenPlugin == null) return; // User cancelled
      } else {
        // Only one compatible plugin found.
        chosenPlugin = compatiblePlugins.first;
      }
    }

    // Now, attempt to open the file with the chosen plugin.
    try {
      await _updateState((s) async {
        final newProject = await s.currentProject!.openFile(file, plugin: chosenPlugin, ref: ref);
        return s.copyWith(currentProject: newProject);
      });
    } on InvalidRecipeFormatException {
      _showErrorSnackbar("Could not open '${file.name}'. The file is not a valid recipe format.");
    } catch (e, st) {
      ref.read(logProvider.notifier).add("Failed to open file '${file.name}': $e\n$st");
      _showErrorSnackbar("Failed to open file: $e");
    }
  }

  // NEW: Helper method to show a snackbar (requires a BuildContext).
  // We can get this from a NavigatorKey or pass it from the UI.
  // For simplicity, let's assume a global key for now.
  // A better solution would involve a dedicated "messenger" service.
  void _showErrorSnackbar(String message) {
    // This is a simplified approach. In a real app, use a service that
    // doesn't depend on BuildContext.
    final scaffoldMessenger = ref.read(rootScaffoldMessengerKeyProvider).currentState;
    scaffoldMessenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  // NEW: Helper method to show the "Open With..." dialog.
  Future<EditorPlugin?> _showOpenWithDialog(List<EditorPlugin> plugins) async {
    // This also requires a context.
    final context = ref.read(navigatorKeyProvider).currentContext;
    if (context == null) return null;

    return await showDialog<EditorPlugin>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open with...'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: plugins.map((p) => ListTile(
            leading: p.icon,
            title: Text(p.name),
            onTap: () => Navigator.of(ctx).pop(p),
          )).toList(),
        ),
      ),
    );
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
      if (oldIndex > index) newCurrentIndex = oldIndex - 1;
      else if (oldIndex == index) newCurrentIndex = (oldIndex - 1).clamp(0, newTabs.length - 1);
      else newCurrentIndex = oldIndex;
    }
    final newProject = copyWith(
      session: session.copyWith(tabs: newTabs, currentTabIndex: newCurrentIndex),
    );
    closedTab.plugin.deactivateTab(closedTab, ref);
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
    final newCurrentIndex = currentOpenTab != null ? newTabs.indexOf(currentOpenTab) : 0;
    return copyWith(session: session.copyWith(tabs: newTabs, currentTabIndex: newCurrentIndex));
  }

  @override
  Future<Project> saveTab(int tabIndex) async {
    final tabToSave = session.tabs[tabIndex];
    final newFile = await fileHandler.writeFile(tabToSave.file, tabToSave.contentString);
    final newTab = tabToSave.copyWith(file: newFile, isDirty: false);
    return updateTab(tabIndex, newTab);
  }

  @override
  Project markCurrentTabDirty() {
    final currentTab = session.currentTab;
    if (currentTab == null || currentTab.isDirty) return this;
    final newTab = currentTab.copyWith(isDirty: true);
    return updateTab(session.currentTabIndex, newTab);
  }

  @override
  Project updateTab(int tabIndex, EditorTab newTab) {
    final newTabs = List<EditorTab>.from(session.tabs);
    newTabs[tabIndex] = newTab;
    return copyWith(session: session.copyWith(tabs: newTabs));
  }
}