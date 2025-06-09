// lib/app/app_notifier.dart
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/persistence_service.dart';
import '../main.dart'; // For sharedPreferencesProvider
import '../plugins/plugin_architecture.dart';
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
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async => await updater(state.value!));
  }

  // --- Project Lifecycle ---
  Future<void> openProjectFromFolder(DocumentFile folder) async {
    await _updateState((previousState) async {
      ProjectMetadata metaToOpen = previousState.knownProjects.firstWhere(
            (p) => p.rootUri == folder.uri, orElse: () => null) ??
            await _projectManager.createNewProjectMetadata(folder.uri, folder.name);

      var knownProjects = previousState.knownProjects;
      if (!knownProjects.any((p) => p.id == metaToOpen.id)) {
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
    // Don't save global state here, let a more explicit action do it.
  }

  Future<void> removeKnownProject(String projectId) async {
     await _updateState((previousState) async {
        if (previousState.currentProject?.id == projectId) {
          // This will save the project being closed before clearing it.
          await closeProject(); 
          // Re-fetch state because closeProject updates it
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
    if (project == null) return;
    
    // Check if tab is already open
    final existingIndex = project.session.tabs.indexWhere((t) => t.file.uri == file.uri);
    if (existingIndex != -1) {
      await switchTab(existingIndex);
      return;
    }

    // Create new tab
    final plugins = ref.read(activePluginsProvider);
    final selectedPlugin = plugin ?? plugins.firstWhere((p) => p.supportsFile(file));
    final content = await project.fileHandler.readFile(file.uri);
    final newTab = await selectedPlugin.createTab(file, content);

    // Update state
    await _updateState((previousState) async {
      final oldProject = previousState.currentProject as LocalProject;
      final newSession = oldProject.session.copyWith(
        tabs: [...oldProject.session.tabs, newTab],
        currentTabIndex: oldProject.session.tabs.length,
      );
      return previousState.copyWith(currentProject: oldProject.copyWith(session: newSession));
    });
  }

  Future<void> switchTab(int index) async {
    await _updateState((previousState) async {
      final oldProject = previousState.currentProject as LocalProject;
      final newSession = oldProject.session.copyWith(currentTabIndex: index);
      return previousState.copyWith(currentProject: oldProject.copyWith(session: newSession));
    });
  }

  // ... Other methods like closeTab, markDirty would follow a similar pattern ...
  // void closeTab(int index) {
  //   _updateState((previousState) { ... deep copy logic ... });
  // }
  
  // --- Persistence ---
  Future<void> saveAppState() async {
    if (state.value == null) return;
    if (state.value!.currentProject != null) {
      await _projectManager.saveProject(state.value!.currentProject!);
    }
    await _persistenceService.saveAppState(state.value!);
  }
}