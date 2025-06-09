// lib/session/session_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    // Check if tab is already open
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

  Project closeTabInProject(Project project, int index) {
    if (project is! LocalProject || index < 0 || index >= project.session.tabs.length) {
      return project;
    }

    final closedTab = project.session.tabs[index];
    final oldTab = project.session.currentTab;
    final newTabs = List<EditorTab>.from(project.session.tabs)..removeAt(index);
    final newIndex = (project.session.currentTabIndex == index)
      ? (index - 1).clamp(0, newTabs.length - 1)
      : project.session.currentTabIndex;

    final newProject = project.copyWith(
      session: project.session.copyWith(tabs: newTabs, currentTabIndex: newIndex)
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
    if (project is! LocalProject) return project;
    
    final newTabs = List<EditorTab>.from(project.session.tabs);
    newTabs[tabIndex] = newTab;

    return project.copyWith(session: project.session.copyWith(tabs: newTabs));
  }

  void _handlePluginLifecycle(EditorTab? oldTab, EditorTab? newTab) {
    if (oldTab != null) oldTab.plugin.deactivateTab(oldTab, _ref);
    if (newTab != null) newTab.plugin.activateTab(newTab, _ref);
  }
}