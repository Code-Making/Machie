// lib/editor/services/editor_service.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';

import '../../app/app_notifier.dart';
import '../../data/repositories/project_repository.dart';
import '../../editor/editor_tab_models.dart';
import '../../editor/plugins/plugin_registry.dart';
import '../../project/project_models.dart';
import '../../logs/logs_provider.dart';
import '../../data/file_handler/file_handler.dart' show DocumentFile;
import '../tab_state_manager.dart';
import '../../explorer/common/save_as_dialog.dart';
import '../../utils/toast.dart';


final editorServiceProvider = Provider<EditorService>((ref) {
  return EditorService(ref);
});

class EditorService {
  final Ref _ref;
  EditorService(this._ref);

  // --- Helpers to get current state ---
  Project? get _currentProject => _ref.read(appNotifierProvider).value?.currentProject;
  EditorTab? get _currentTab => _currentProject?.session.currentTab;

  // --- Facade methods for plugins to call ---

  void markCurrentTabDirty() {
    final uri = _currentTab?.file.uri;
    if (uri != null) {
      _ref.read(tabStateManagerProvider.notifier).markDirty(uri);
    }
  }

  void markCurrentTabClean() {
    final uri = _currentTab?.file.uri;
    if (uri != null) {
      _ref.read(tabStateManagerProvider.notifier).markClean(uri);
    }
  }

  // REFACTOR: This method now correctly returns the updated Project object.
  Project? updateCurrentTabModel(EditorTab newTabModel) {
    final project = _currentProject;
    if (project == null) return null;
    
    final newTabs = List<EditorTab>.from(project.session.tabs);
    newTabs[project.session.currentTabIndex] = newTabModel;
    
    final newProject = project.copyWith(
      session: project.session.copyWith(tabs: newTabs),
    );
    // The AppNotifier will now receive this new project state.
    return newProject;
  }

  void setBottomToolbarOverride(Widget? widget) {
    _ref.read(appNotifierProvider.notifier).setBottomToolbarOverride(widget);
  }

  void clearBottomToolbarOverride() {
    _ref.read(appNotifierProvider.notifier).clearBottomToolbarOverride();
  }

  /// Initiates the "Save As" flow for the current tab.
  Future<void> saveCurrentTabAs({
    Future<Uint8List?> Function()? byteDataProvider,
    Future<String?> Function()? stringDataProvider,
  }) async {
    final repo = _ref.read(projectRepositoryProvider);
    final context = _ref.read(navigatorKeyProvider).currentContext;
    final currentTab = _currentTab;

    if (repo == null || context == null || currentTab == null) return;

    final result = await showDialog<SaveAsDialogResult>(
      context: context,
      builder: (_) => SaveAsDialog(initialFileName: currentTab.file.name),
    );
    if (result == null) return;

    final DocumentFile newFile;
    if (byteDataProvider != null) {
      final bytes = await byteDataProvider();
      if (bytes == null) return;
      newFile = await repo.createDocumentFile(
        _ref,
        result.parentUri,
        result.fileName,
        initialBytes: bytes,
        overwrite: true,
      );
    } else if (stringDataProvider != null) {
      final content = await stringDataProvider();
      if (content == null) return;
      newFile = await repo.createDocumentFile(
        _ref,
        result.parentUri,
        result.fileName,
        initialContent: content,
        overwrite: true,
      );
    } else {
      return;
    }
    
    MachineToast.info("Saved as ${newFile.name}");
  }

  // --- Existing Service Methods ---
  
  ProjectRepository get _repo {
    final repo = _ref.read(projectRepositoryProvider);
    if (repo == null) {
      throw StateError('ProjectRepository is not available.');
    }
    return repo;
  }
  
  /// Handles activating/deactivating plugin logic when switching tabs.
  void _handlePluginLifecycle(EditorTab? oldTab, EditorTab? newTab) {
    if (oldTab != null) oldTab.plugin.deactivateTab(oldTab, _ref);
    if (newTab != null) newTab.plugin.activateTab(newTab, _ref);
  }

  /// Restores all tabs from a saved session when a project is opened.
  Future<Project> rehydrateTabs(Project project) async {
    final projectStateJson = project.toJson();
    final sessionJson = projectStateJson['session'] as Map<String, dynamic>? ?? {};
    final tabsJson = sessionJson['tabs'] as List<dynamic>? ?? [];
    final plugins = _ref.read(activePluginsProvider);
    final List<EditorTab> tabs = [];

    for (final tabJson in tabsJson) {
      final pluginType = tabJson['pluginType'] as String?;
      if (pluginType == null) continue;

      final plugin =
          plugins.firstWhereOrNull((p) => p.runtimeType.toString() == pluginType);
      if (plugin != null) {
        try {
          final file = await _repo.fileHandler.getFileMetadata(tabJson['fileUri']);
          if (file == null) continue;
          
          final dynamic data = plugin.dataRequirement == PluginDataRequirement.bytes
              ? await _repo.fileHandler.readFileAsBytes(file.uri)
              : await _repo.fileHandler.readFile(file.uri);
              
          final tab = await plugin.createTab(file, data);
          tabs.add(tab);
          
          final tabState = await plugin.createTabState(tab, data);
          if (tabState != null) {
            // Call the single, consolidated addState method.
            _ref.read(tabStateManagerProvider.notifier).addState(tab.file.uri, tabState);
          }
        } catch (e) {
          _ref.read(talkerProvider).error('Could not restore tab: $e');
        }
      }
    }
    return project.copyWith(
      session: project.session.copyWith(tabs: tabs),
    );
  }

  /// Opens a file in the editor, creating a new tab or switching to an existing one.
  Future<OpenFileResult> openFile(
    Project project,
    DocumentFile file, {
    EditorPlugin? explicitPlugin,
  }) async {
    final existingIndex =
        project.session.tabs.indexWhere((t) => t.file.uri == file.uri);
    if (existingIndex != -1) {
      return OpenFileSuccess(
        project: switchTab(project, existingIndex),
        wasAlreadyOpen: true,
      );
    }
    EditorPlugin? chosenPlugin = explicitPlugin;
    if (chosenPlugin == null) {
      final compatiblePlugins = _ref
          .read(activePluginsProvider)
          .where((p) => p.supportsFile(file))
          .toList();
      if (compatiblePlugins.isEmpty) {
        return OpenFileError("No plugin available to open '${file.name}'.");
      } else if (compatiblePlugins.length > 1) {
        return OpenFileShowChooser(compatiblePlugins);
      }
      chosenPlugin = compatiblePlugins.first;
    }

    final dynamic data;
    if (chosenPlugin.dataRequirement == PluginDataRequirement.bytes) {
      data = await _repo.readFileAsBytes(file.uri);
    } else {
      data = await _repo.readFile(file.uri);
    }

    final newTab = await chosenPlugin.createTab(file, data);

    // Call the single, consolidated addState method.
    final tabState = await chosenPlugin.createTabState(newTab, data);
    if (tabState != null) {
      _ref.read(tabStateManagerProvider.notifier).addState(newTab.file.uri, tabState);
    }

    final oldTab = project.session.currentTab;
    final newSession = project.session.copyWith(
      tabs: [...project.session.tabs, newTab],
      currentTabIndex: project.session.tabs.length,
    );

    _handlePluginLifecycle(oldTab, newTab);

    return OpenFileSuccess(
      project: project.copyWith(session: newSession),
      wasAlreadyOpen: false,
    );
  }
  
  /// Saves the content of the current tab to its file.
  Future<bool> saveCurrentTab(
    Project project, {
    String? content,
    Uint8List? bytes,
  }) async {
    final tabToSave = project.session.currentTab;
    if (tabToSave == null) return false;

    try {
      if (content != null) {
        await _repo.writeFile(tabToSave.file, content);
      } else if (bytes != null) {
        await _repo.writeFileAsBytes(tabToSave.file, bytes);
      } else {
        return false;
      }
      // Use the consolidated notifier to mark the tab as clean.
      _ref.read(tabStateManagerProvider.notifier).markClean(tabToSave.file.uri);
      return true;
    } catch (e) {
      _ref.read(talkerProvider).error("Failed to save tab: $e");
      return false;
    }
  }

  /// Switches the active tab to the one at the given index.
  Project switchTab(Project project, int index) {
    final oldTab = project.session.currentTab;
    final newSession = project.session.copyWith(currentTabIndex: index);
    final newProject = project.copyWith(session: newSession);
    final newTab = newProject.session.currentTab;

    _handlePluginLifecycle(oldTab, newTab);
    return newProject;
  }

  /// Closes the tab at the given index.
  Project closeTab(Project project, int index) {
    final closedTab = project.session.tabs[index];
    final oldTab = project.session.currentTab;
    final newTabs = List<EditorTab>.from(project.session.tabs)..removeAt(index);

    int newCurrentIndex;
    if (newTabs.isEmpty) {
      newCurrentIndex = 0;
    } else {
      final oldIndex = project.session.currentTabIndex;
      if (oldIndex > index) {
        newCurrentIndex = oldIndex - 1;
      } else if (oldIndex == index) {
        newCurrentIndex = (oldIndex - 1).clamp(0, newTabs.length - 1);
      } else {
        newCurrentIndex = oldIndex;
      }
    }

    final newProject = project.copyWith(
      session: project.session.copyWith(
        tabs: newTabs,
        currentTabIndex: newCurrentIndex,
      ),
    );

    // Use the consolidated notifier to remove the tab's state.
    final tabState = _ref.read(tabStateManagerProvider.notifier).removeState(closedTab.file.uri);
    if (tabState != null) {
      closedTab.plugin.disposeTabState(tabState);
    }

    closedTab.plugin.deactivateTab(closedTab, _ref);
    closedTab.plugin.disposeTab(closedTab);
    closedTab.dispose();

    final newTab = newProject.session.currentTab;
    if (oldTab != newTab) {
      newTab?.plugin.activateTab(newTab, _ref);
    }
    return newProject;
  }

  /// Reorders the tabs in the session.
  Project reorderTabs(Project project, int oldIndex, int newIndex) {
    final currentOpenTab = project.session.currentTab;
    final newTabs = List<EditorTab>.from(project.session.tabs);
    final movedTab = newTabs.removeAt(oldIndex);
    if (oldIndex < newIndex) newIndex--;
    newTabs.insert(newIndex, movedTab);
    final newCurrentIndex =
        currentOpenTab != null ? newTabs.indexOf(currentOpenTab) : 0;
    return project.copyWith(
      session: project.session.copyWith(
        tabs: newTabs,
        currentTabIndex: newCurrentIndex,
      ),
    );
  }

  /// Updates a tab's underlying file metadata, e.g., after a rename or move operation.
  Project updateTabFile(Project project, String oldUri, DocumentFile newFile) {
    final tabIndex = project.session.tabs.indexWhere((t) => t.file.uri == oldUri);
    if (tabIndex == -1) return project;

    final oldTab = project.session.tabs[tabIndex];
    
    // Create a new tab instance with the updated file using the abstract `copyWith`.
    final newTab = oldTab.copyWith(file: newFile);

    // Update the tab list in the project's session state.
    final newTabs = List<EditorTab>.from(project.session.tabs);
    newTabs[tabIndex] = newTab;

    // Use the consolidated state manager to re-key the tab's state,
    // preserving its "hot" state and dirty status.
    _ref.read(tabStateManagerProvider.notifier).rekeyState(oldUri, newFile.uri);
    
    return project.copyWith(
      session: project.session.copyWith(tabs: newTabs),
    );
  }
}

// Result types for the `openFile` method.
@immutable
sealed class OpenFileResult {}

class OpenFileSuccess extends OpenFileResult {
  final Project project;
  final bool wasAlreadyOpen;
  OpenFileSuccess({required this.project, required this.wasAlreadyOpen});
}

class OpenFileShowChooser extends OpenFileResult {
  final List<EditorPlugin> plugins;
  OpenFileShowChooser(this.plugins);
}

class OpenFileError extends OpenFileResult {
  final String message;
  OpenFileError(this.message);
}