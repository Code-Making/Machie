// lib/session/session_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';

import '../plugins/plugin_architecture.dart';
import '../plugins/plugin_registry.dart';
import '../project/file_handler/file_handler.dart';
import '../project/project_models.dart';
import 'session_models.dart';

final sessionServiceProvider = Provider<SessionService>((ref) {
  return SessionService(ref);
});

/// A service containing business logic for an active project session.
/// It operates on state objects and returns new, updated states.
class SessionService {
  final Ref _ref;
  SessionService(this._ref);

  Future<Project> openFileInProject(Project project, DocumentFile file, {EditorPlugin? plugin}) async {
    if (project is! LocalProject) return project;

    final existingIndex = project.session.tabs.indexWhere((t) => t.file.uri == file.uri);
    if (existingIndex != -1) {
      return switchTabInProject(project, existingIndex);
    }

    final plugins = _ref.read(activePluginsProvider);
    final selectedPlugin = plugin ?? plugins.firstWhere((p) => p.supportsFile(file));
    final content = await project.fileHandler.readFile(file.uri);
    final newTab = await selectedPlugin.createTab(file, content);

    final oldTab = project.session.currentTab;
    final newSession = project.session.copyWith(
      tabs: [...project.session.tabs, newTab],
      currentTabIndex: project.session.tabs.length,
    );
    _handlePluginLifecycle(oldTab, newTab);

    return project.copyWith(session: newSession);
  }

  Project switchTabInProject(Project project, int index) {
    if (project is! LocalProject) return project;
    
    final oldTab = project.session.currentTab;
    final newSession = project.session.copyWith(currentTabIndex: index);
    final newProject = project.copyWith(session: newSession);
    final newTab = newProject.session.currentTab;

    _handlePluginLifecycle(oldTab, newTab);
    return newProject;
  }
  
  Project reorderTabsInProject(Project project, int oldIndex, int newIndex) {
    if (project is! LocalProject) return project;
    
    final currentOpenTab = project.session.currentTab;
    final newTabs = List<EditorTab>.from(project.session.tabs);
    final movedTab = newTabs.removeAt(oldIndex);
    
    if (oldIndex < newIndex) newIndex--;
    newTabs.insert(newIndex, movedTab);

    final newCurrentIndex = currentOpenTab != null ? newTabs.indexOf(currentOpenTab) : 0;

    return project.copyWith(
      session: project.session.copyWith(tabs: newTabs, currentTabIndex: newCurrentIndex)
    );
  }

  Future<Project> saveTabInProject(Project project, int tabIndex) async {
    if (project is! LocalProject || tabIndex < 0 || tabIndex >= project.session.tabs.length) return project;
    
    final tabToSave = project.session.tabs[tabIndex];
    final newFile = await project.fileHandler.writeFile(tabToSave.file, tabToSave.contentString);
    final newTab = tabToSave.copyWith(file: newFile, isDirty: false);
    
    return updateTabInProject(project, tabIndex, newTab);
  }

  // CORRECTED: This logic now correctly handles the last tab being closed.
  Project closeTabInProject(Project project, int index) {
    if (project is! LocalProject || index < 0 || index >= project.session.tabs.length) {
      return project;
    }

    final closedTab = project.session.tabs[index];
    final oldTab = project.session.currentTab;
    final newTabs = List<EditorTab>.from(project.session.tabs)..removeAt(index);

    int newCurrentIndex;
    if (newTabs.isEmpty) {
      newCurrentIndex = 0; // No tabs left, reset index.
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
      session: project.session.copyWith(tabs: newTabs, currentTabIndex: newCurrentIndex)
    );
    
    closedTab.plugin.deactivateTab(closedTab, _ref);
    closedTab.dispose();

    final newTab = newProject.session.currentTab;
    if (oldTab != newTab) {
      newTab?.plugin.activateTab(newTab, _ref);
    }
    
    return newProject;
  }

  Project markCurrentTabDirty(Project project) {
    if (project is! LocalProject) return project;
    final currentTab = project.session.currentTab;
    if (currentTab == null || currentTab.isDirty) return project;

    final newTab = currentTab.copyWith(isDirty: true);
    return updateTabInProject(project, project.session.currentTabIndex, newTab);
  }
  
  Project updateTabInProject(Project project, int tabIndex, EditorTab newTab) {
    if (project is! LocalProject || tabIndex < 0 || tabIndex >= project.session.tabs.length) return project;
    
    final newTabs = List<EditorTab>.from(project.session.tabs);
    newTabs[tabIndex] = newTab;

    return project.copyWith(session: project.session.copyWith(tabs: newTabs));
  }
  
  // NEW: Add folder expansion logic
  Project toggleFolderExpansionInProject(Project project, String folderUri) {
    if (project is! LocalProject) return project;

    final newExpanded = Set<String>.from(project.expandedFolders);
    if (newExpanded.contains(folderUri)) {
      newExpanded.remove(folderUri);
    } else {
      newExpanded.add(folderUri);
    }
    
    return project.copyWith(expandedFolders: newExpanded);
  }

  void _handlePluginLifecycle(EditorTab? oldTab, EditorTab? newTab) {
    if (oldTab != null) oldTab.plugin.deactivateTab(oldTab, _ref);
    if (newTab != null) newTab.plugin.activateTab(newTab, _ref);
  }
}