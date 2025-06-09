// lib/app/app_notifier.dart

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/persistence_service.dart';
import '../main.dart'; // For sharedPreferencesProvider
import '../plugins/plugin_architecture.dart';
import '../plugins/plugin_registry.dart'; // For activePluginsProvider
import '../project/file_handler/file_handler.dart';
import '../project/project_manager.dart';
import '../project/project_models.dart';
import '../session/session_models.dart';
import 'app_state.dart';

final appNotifierProvider = AsyncNotifierProvider<AppNotifier, AppState>(AppNotifier.new);

// Manages the global AppState and orchestrates calls to services.
class AppNotifier extends AsyncNotifier<AppState> {
  late PersistenceService _persistenceService;
  late ProjectManager _projectManager;

  @override
  Future<AppState> build() async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    _persistenceService = PersistenceService(prefs);
    _projectManager = ref.watch(projectManagerProvider);

    final initialState = await _persistenceService.loadAppState();
    if (initialState.lastOpenedProjectId != null) {
      final meta = initialState.knownProjects.firstWhereOrNull((p) => p.id == initialState.lastOpenedProjectId);
      if (meta != null) {
        try {
          final project = await _projectManager.openProject(meta);
          return initialState.copyWith(currentProject: project);
        } catch (e) {
          print('Failed to auto-open last project: $e');
        }
      }
    }
    return initialState;
  }

  Future<void> _updateState(Future<AppState> Function(AppState) updater) async {
    final previousState = state.value;
    if (previousState == null) return;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async => await updater(previousState));
  }

  // --- Project Lifecycle ---
  Future<void> openProjectFromFolder(DocumentFile folder) async {
    await _updateState((previousState) async {
      ProjectMetadata? existingMeta = previousState.knownProjects.firstWhereOrNull((p) => p.rootUri == folder.uri);
      final ProjectMetadata metaToOpen = existingMeta ?? await _projectManager.createNewProjectMetadata(folder.uri, folder.name);

      var knownProjects = previousState.knownProjects;
      if (existingMeta == null) {
        knownProjects = [...knownProjects, metaToOpen];
      }

      final project = await _projectManager.openProject(metaToOpen);
      return previousState.copyWith(
        currentProject: project,
        lastOpenedProjectId: project.id,
        knownProjects: knownProjects,
      );
    });
    await saveAppState();
  }

  Future<void> openKnownProject(String projectId) async {
     await _updateState((previousState) async {
        final meta = previousState.knownProjects.firstWhere((p) => p.id == projectId);
        final project = await _projectManager.openProject(meta);
        return previousState.copyWith(currentProject: project, lastOpenedProjectId: project.id);
     });
     await saveAppState();
  }

  Future<void> closeProject() async {
    final projectToSave = state.value?.currentProject;
    if (projectToSave == null) return;
    await _projectManager.saveProject(projectToSave);

    await _updateState((previousState) async {
      return previousState.copyWith(clearCurrentProject: true);
    });
  }

  Future<void> removeKnownProject(String projectId) async {
     await _updateState((previousState) async {
        if (previousState.currentProject?.id == projectId) {
          await closeProject();
          previousState = state.value!;
        }
        return previousState.copyWith(
            knownProjects: previousState.knownProjects.where((p) => p.id != projectId).toList()
        );
     });
     await saveAppState();
  }

  // --- Tab Lifecycle ---
  Future<void> openFile(DocumentFile file, {EditorPlugin? plugin}) async {
    final project = state.value?.currentProject;
    if (project is! LocalProject) return;
    
    final existingIndex = project.session.tabs.indexWhere((t) => t.file.uri == file.uri);
    if (existingIndex != -1) {
      await switchTab(existingIndex);
      return;
    }

    final plugins = ref.read(activePluginsProvider);
    final selectedPlugin = plugin ?? plugins.firstWhere((p) => p.supportsFile(file));
    final content = await project.fileHandler.readFile(file.uri);
    final newTab = await selectedPlugin.createTab(file, content);

    final oldTab = project.session.currentTab;

    await _updateState((previousState) async {
      final oldProject = previousState.currentProject as LocalProject;
      final newSession = oldProject.session.copyWith(
        tabs: [...oldProject.session.tabs, newTab],
        currentTabIndex: oldProject.session.tabs.length,
      );
      return previousState.copyWith(currentProject: oldProject.copyWith(session: newSession));
    });

    _handlePluginLifecycle(oldTab, newTab);
  }
  
  // NEW: Generic method to update the state of the currently active tab.
  Future<void> updateCurrentTab(EditorTab newTab) async {
    await _updateState((previousState) async {
      final project = previousState.currentProject as LocalProject;
      final session = project.session;
      
      final newTabs = List<EditorTab>.from(session.tabs);
      newTabs[session.currentTabIndex] = newTab;

      final newSession = session.copyWith(tabs: newTabs);
      final newProject = project.copyWith(session: newSession);
      
      return previousState.copyWith(currentProject: newProject);
    });
  }

  Future<void> switchTab(int index) async {
    final project = state.value?.currentProject as LocalProject?;
    if (project == null) return;
    
    final oldTab = project.session.currentTab;
    await _updateState((previousState) async {
      final oldProject = previousState.currentProject as LocalProject;
      final newSession = oldProject.session.copyWith(currentTabIndex: index);
      return previousState.copyWith(currentProject: oldProject.copyWith(session: newSession));
    });
    final newTab = (state.value!.currentProject as LocalProject).session.currentTab;
    _handlePluginLifecycle(oldTab, newTab);
  }

  Future<void> closeTab(int index) async {
    final project = state.value?.currentProject as LocalProject?;
    if (project == null || index < 0 || index >= project.session.tabs.length) return;

    final closedTab = project.session.tabs[index];
    final oldTab = project.session.currentTab;

    await _updateState((previousState) async {
      final oldProject = previousState.currentProject as LocalProject;
      final newTabs = List<EditorTab>.from(oldProject.session.tabs)..removeAt(index);
      final newIndex = (oldProject.session.currentTabIndex == index)
        ? (index - 1).clamp(0, newTabs.length - 1)
        : oldProject.session.currentTabIndex;

      return previousState.copyWith(
        currentProject: oldProject.copyWith(
          session: oldProject.session.copyWith(tabs: newTabs, currentTabIndex: newIndex)
        )
      );
    });

    closedTab.plugin.deactivateTab(closedTab, ref);
    closedTab.dispose();

    final newTab = (state.value!.currentProject as LocalProject).session.currentTab;
    if (oldTab != newTab) {
      newTab?.plugin.activateTab(newTab, ref);
    }
  }
  
  Future<void> reorderTabs(int oldIndex, int newIndex) async {
     await _updateState((previousState) async {
        final project = previousState.currentProject as LocalProject;
        final newTabs = List<EditorTab>.from(project.session.tabs);
        final movedTab = newTabs.removeAt(oldIndex);
        if (oldIndex < newIndex) newIndex--;
        newTabs.insert(newIndex, movedTab);
        
        return previousState.copyWith(
          currentProject: project.copyWith(
            session: project.session.copyWith(tabs: newTabs)
          )
        );
     });
  }

  Future<void> saveCurrentTab() async {
    final project = state.value?.currentProject as LocalProject?;
    final currentTab = project?.session.currentTab;
    if (project == null || currentTab == null) return;
    
    final newFile = await project.fileHandler.writeFile(currentTab.file, currentTab.contentString);
    final newTab = currentTab.copyWith(file: newFile, isDirty: false);
    
    await _updateState((previousState) async {
      final oldProject = previousState.currentProject as LocalProject;
      final newTabs = oldProject.session.tabs.map((t) => t == currentTab ? newTab : t).toList();
      return previousState.copyWith(
        currentProject: oldProject.copyWith(
          session: oldProject.session.copyWith(tabs: newTabs)
        )
      );
    });
  }
  
  void markCurrentTabDirty() {
    final project = state.value?.currentProject as LocalProject?;
    final currentTab = project?.session.currentTab;
    if (project == null || currentTab == null || currentTab.isDirty) return;

    final newTab = currentTab.copyWith(isDirty: true);

    if (state.value != null) {
      final newTabs = state.value!.currentProject!.session.tabs.map((t) => t == currentTab ? newTab : t).toList();
      final newProject = (state.value!.currentProject as LocalProject).copyWith(
        session: state.value!.currentProject!.session.copyWith(tabs: newTabs),
      );
      state = AsyncData(state.value!.copyWith(currentProject: newProject));
    }
  }

  void _handlePluginLifecycle(EditorTab? oldTab, EditorTab? newTab) {
    if (oldTab != null) oldTab.plugin.deactivateTab(oldTab, ref);
    if (newTab != null) newTab.plugin.activateTab(newTab, ref);
  }
  
  // --- Persistence ---
  Future<void> saveAppState() async {
    final appState = state.value;
    if (appState == null) return;

    if (appState.currentProject != null) {
      await _projectManager.saveProject(appState.currentProject!);
    }
    await _persistenceService.saveAppState(appState);
  }
}