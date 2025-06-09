// lib/app/app_notifier.dart
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/persistence_service.dart';
import '../main.dart';
import '../project/file_handler/file_handler.dart';
import '../project/project_manager.dart';
import '../project/project_models.dart';
import '../session/session_service.dart';

final appNotifierProvider = AsyncNotifierProvider<AppNotifier, AppState>(AppNotifier.new);

class AppNotifier extends AsyncNotifier<AppState> {
  late PersistenceService _persistenceService;
  late ProjectManager _projectManager;
  late SessionService _sessionService;

  @override
  Future<AppState> build() async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    _persistenceService = PersistenceService(prefs);
    _projectManager = ref.watch(projectManagerProvider);
    _sessionService = ref.watch(sessionServiceProvider);

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
  
  void _updateStateSync(AppState Function(AppState) updater) {
    final previousState = state.value;
    if (previousState == null) return;
    state = AsyncData(updater(previousState));
  }

  // --- Project Lifecycle ---
  Future<void> openProjectFromFolder(DocumentFile folder) async {
    await _updateState((s) async {
      ProjectMetadata? meta = s.knownProjects.firstWhereOrNull((p) => p.rootUri == folder.uri);
      final isNew = meta == null;
      meta ??= await _projectManager.createNewProjectMetadata(folder.uri, folder.name);
      
      final project = await _projectManager.openProject(meta);
      return s.copyWith(
        currentProject: project,
        lastOpenedProjectId: project.id,
        knownProjects: isNew ? [...s.knownProjects, meta] : s.knownProjects,
      );
    });
    await saveAppState();
  }

  Future<void> openKnownProject(String projectId) async {
     await _updateState((s) async {
        final meta = s.knownProjects.firstWhere((p) => p.id == projectId);
        final project = await _projectManager.openProject(meta);
        return s.copyWith(currentProject: project, lastOpenedProjectId: project.id);
     });
     await saveAppState();
  }

  Future<void> closeProject() async {
    final projectToSave = state.value?.currentProject;
    if (projectToSave == null) return;
    await _projectManager.saveProject(projectToSave);
    await _updateState((s) async => s.copyWith(clearCurrentProject: true));
  }

  // --- Tab Lifecycle (Delegation) ---
  Future<void> openFile(DocumentFile file) async {
    await _updateState((s) async {
      final newProject = await _sessionService.openFileInProject(s.currentProject!, file);
      return s.copyWith(currentProject: newProject);
    });
  }
  
  void closeTab(int index) {
    _updateStateSync((s) {
      final newProject = _sessionService.closeTabInProject(s.currentProject!, index);
      return s.copyWith(currentProject: newProject);
    });
  }

  void markCurrentTabDirty() {
    _updateStateSync((s) {
      final newProject = _sessionService.markCurrentTabDirty(s.currentProject!);
      return s.copyWith(currentProject: newProject);
    });
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