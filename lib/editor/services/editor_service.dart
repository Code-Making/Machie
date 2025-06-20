// lib/editor/services/editor_service.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';

import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project_repository.dart';
import '../../editor/editor_tab_models.dart';
import '../../editor/plugins/plugin_registry.dart';
import '../../editor/tab_state_notifier.dart';
import '../../project/project_models.dart';
import '../../logs/logs_provider.dart';

final editorServiceProvider = Provider<EditorService>((ref) {
  return EditorService(ref);
});

class EditorService {
  final Ref _ref;
  EditorService(this._ref);

  ProjectRepository get _repo {
    final repo = _ref.read(projectRepositoryProvider);
    if (repo == null) {
      throw StateError('ProjectRepository is not available.');
    }
    return repo;
  }

  void _handlePluginLifecycle(EditorTab? oldTab, EditorTab? newTab) {
    if (oldTab != null) oldTab.plugin.deactivateTab(oldTab, _ref);
    if (newTab != null) newTab.plugin.activateTab(newTab, _ref);
  }

  // REFACTOR: Tab rehydration logic now lives here.
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
          final tab = await plugin.createTabFromSerialization(tabJson, _repo.fileHandler);
          tabs.add(tab);
          _ref.read(tabStateProvider.notifier).initTab(tab.file.uri);
        } catch (e) {
          _ref.read(talkerProvider).error('Could not restore tab: $e');
        }
      }
    }
    return project.copyWith(
      session: project.session.copyWith(tabs: tabs),
    );
  }

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
    _ref.read(tabStateProvider.notifier).initTab(file.uri);

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
      _ref.read(tabStateProvider.notifier).markClean(tabToSave.file.uri);
      return true;
    } catch (e) {
      _ref.read(talkerProvider).error("Failed to save tab: $e");
      return false;
    }
  }

  // ... other methods (switchTab, closeTab, etc.) are unchanged ...
  Project switchTab(Project project, int index) {
    final oldTab = project.session.currentTab;
    final newSession = project.session.copyWith(currentTabIndex: index);
    final newProject = project.copyWith(session: newSession);
    final newTab = newProject.session.currentTab;

    _handlePluginLifecycle(oldTab, newTab);
    return newProject;
  }

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

    closedTab.plugin.deactivateTab(closedTab, _ref);
    closedTab.plugin.disposeTab(closedTab);
    closedTab.dispose();
    _ref.read(tabStateProvider.notifier).removeTab(closedTab.file.uri);

    final newTab = newProject.session.currentTab;
    if (oldTab != newTab) {
      newTab?.plugin.activateTab(newTab, _ref);
    }
    return newProject;
  }

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

  Project updateTab(Project project, int tabIndex, EditorTab newTab) {
    if (tabIndex < 0 || tabIndex >= project.session.tabs.length) return project;
    final newTabs = List<EditorTab>.from(project.session.tabs);
    newTabs[tabIndex] = newTab;
    return project.copyWith(
      session: project.session.copyWith(tabs: newTabs),
    );
  }
}