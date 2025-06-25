// =========================================
// FILE: lib/app/app_notifier.dart
// =========================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/dto/project_dto.dart';
import '../data/persistence_service.dart';
import '../data/file_handler/file_handler.dart';
import '../editor/plugins/plugin_registry.dart';
import '../project/services/project_service.dart';
import '../editor/services/editor_service.dart';
import '../utils/clipboard.dart';
import 'app_state.dart';
import '../explorer/common/file_explorer_dialogs.dart';
import '../logs/logs_provider.dart';
import '../utils/toast.dart';
import '../data/repositories/project_repository.dart';
import '../project/project_models.dart';
import '../editor/tab_state_manager.dart';
import '../editor/editor_tab_models.dart';
import 'package:machine/data/dto/project_dto.dart'; // ADDED

final appNotifierProvider = AsyncNotifierProvider<AppNotifier, AppState>(
  AppNotifier.new,
);

final navigatorKeyProvider = Provider((ref) => GlobalKey<NavigatorState>());
final rootScaffoldMessengerKeyProvider = Provider(
  (ref) => GlobalKey<ScaffoldMessengerState>(),
);

class AppNotifier extends AsyncNotifier<AppState> {
  late AppStateRepository _appStateRepository;
  late ProjectService _projectService;
  late EditorService _editorService;

  @override
  Future<AppState> build() async {
    // Initialize dependencies
    final talker = ref.read(talkerProvider);
    _appStateRepository = AppStateRepository(await ref.watch(sharedPreferencesProvider.future), talker);
    _projectService = ref.watch(projectServiceProvider);
    _editorService = ref.watch(editorServiceProvider);

    // Subscribe to file system events to keep UI in sync
    ref.listen<AsyncValue<FileOperationEvent>>(fileOperationStreamProvider, (
      previous,
      next,
    ) {
      next.whenData((event) {
        _handleFileOperationEvent(event);
      });
    });

    // Load the last known state of the app
    final initialState = await _appStateRepository.loadAppState();
    
    // Attempt to re-open the last project
    if (initialState.lastOpenedProjectId != null) {
      final meta = initialState.knownProjects.firstWhereOrNull(
        (p) => p.id == initialState.lastOpenedProjectId,
      );
      if (meta != null) {
        try {
          // 1. Load the raw DTO from the appropriate repository.
          final projectDto = await _projectService.openProjectDto(
            meta,
            // Pass the entire persisted state for simple projects.
            projectStateJson: initialState.currentProjectState,
          );
          
          // 2. Pass the DTO to the EditorService to get a fully rehydrated, live Project object.
          final finalProject = await _editorService.rehydrateProjectFromDto(projectDto, meta);
          
          // 3. Return the final, ready-to-use application state.
          return initialState.copyWith(
            currentProject: finalProject,
            clearCurrentProjectState: true, // No longer need the raw JSON
          );
        } catch (e, st) {
          talker.handle(e, st, 'Failed to auto-open last project');
        }
      }
    }
    
    // Fallback to the initial loaded state if re-opening fails.
    return initialState;
  }

  /// Handles events published by the ProjectRepository to keep the UI in sync.
  void _handleFileOperationEvent(FileOperationEvent event) {
    final project = state.value?.currentProject;
    if (project == null) return;
    
    switch (event) {
      case FileCreateEvent():
        // No action needed here, the explorer will update itself via its own listeners.
        break;
        
      case FileRenameEvent(oldFile: final oldFile, newFile: final newFile):
        // Delegate to the service. The service updates the metadata.
        // The UI (AppBar, TabBar) will react to the metadata provider change.
        _editorService.updateTabForRenamedFile(oldFile.uri, newFile);
        break;
        
      case FileDeleteEvent(deletedFile: final deletedFile):
        // To find the tab to close, we must check the metadata provider.
        final metadataMap = ref.read(tabMetadataProvider);
        final tabIdToDelete = metadataMap.entries.firstWhereOrNull(
          (entry) => entry.value.file.uri == deletedFile.uri,
        )?.key;
        
        if (tabIdToDelete != null) {
          final tabIndex = project.session.tabs.indexWhere((t) => t.id == tabIdToDelete);
          if (tabIndex != -1) {
            // The service will return a new project object with the tab removed.
            final newProject = _editorService.closeTab(project, tabIndex);
            updateCurrentProject(newProject);
          }
        }
        break;
    }
  }

  /// Opens a project from a folder chosen by the user.
  Future<void> openProjectFromFolder({
    required DocumentFile folder,
    required String projectTypeId,
  }) async {
    await _updateState((s) async {
      if (s.currentProject != null) {
        await _projectService.closeProject(s.currentProject!);
      }
      
      final result = await _projectService.openFromFolder(
        folder: folder,
        projectTypeId: projectTypeId,
        knownProjects: s.knownProjects,
      );
      
      final finalProject = await _editorService.rehydrateProjectFromDto(result.projectDto, result.metadata);
      
      return s.copyWith(
        currentProject: finalProject,
        lastOpenedProjectId: finalProject.id,
        knownProjects:
            result.isNew
                ? [...s.knownProjects, result.metadata]
                : s.knownProjects,
      );
    });
    await saveAppState();
  }

  /// Opens a project from the list of previously known projects.
  Future<void> openKnownProject(String projectId) async {
    await _updateState((s) async {
      if (s.currentProject?.id == projectId) return s;
      if (s.currentProject != null) {
        await _projectService.closeProject(s.currentProject!);
      }
      final meta = s.knownProjects.firstWhere((p) => p.id == projectId);
      
      final projectDto = await _projectService.openProjectDto(
        meta,
        projectStateJson: s.currentProjectState // Will be null for persistent projects, which is correct
      );
      
      final finalProject = await _editorService.rehydrateProjectFromDto(projectDto, meta);
      
      return s.copyWith(
        currentProject: finalProject,
        lastOpenedProjectId: finalProject.id,
      );
    });
    await saveAppState();
  }

  /// Closes the currently active project.
  Future<void> closeProject() async {
    final projectToClose = state.value?.currentProject;
    if (projectToClose == null) return;
    await _projectService.closeProject(projectToClose);
    _updateStateSync((s) => s.copyWith(clearCurrentProject: true));
  }

  /// Removes a project from the "known projects" list.
  Future<void> removeKnownProject(String projectId) async {
    await _updateState((s) async {
      if (s.currentProject?.id == projectId) {
        await closeProject();
        s = state.value!; // Refresh state after closing
      }
      return s.copyWith(
        knownProjects: s.knownProjects.where((p) => p.id != projectId).toList(),
      );
    });
    await saveAppState();
  }

  /// Opens a file in a new editor tab.
  Future<bool> openFileInEditor(
    DocumentFile file, {
    EditorPlugin? explicitPlugin,
  }) async {
    final project = state.value?.currentProject;
    if (project == null) return false;

    final result = await _editorService.openFile(
      project,
      file,
      explicitPlugin: explicitPlugin,
    );

    switch (result) {
      case OpenFileSuccess(project: final newProject):
        updateCurrentProject(newProject);
        return true;

      case OpenFileShowChooser(plugins: final plugins):
        final context = ref.read(navigatorKeyProvider).currentContext;
        if (context == null) return false;
        final chosenPlugin = await showOpenWithDialog(context, plugins);
        if (chosenPlugin != null) {
          return await openFileInEditor(file, explicitPlugin: chosenPlugin);
        }
        return false;

      case OpenFileError(message: final msg):
        MachineToast.error(msg);
        return false;
    }
  }

  // --- UI State and Tab Management ---
  
  void switchTab(int index) {
    final project = state.value?.currentProject;
    if (project == null) return;
    final newProject = _editorService.switchTab(project, index);
    updateCurrentProject(newProject);
  }

  void reorderTabs(int oldIndex, int newIndex) {
    final project = state.value?.currentProject;
    if (project == null) return;
    final newProject = _editorService.reorderTabs(project, oldIndex, newIndex);
    updateCurrentProject(newProject);
  }

  void closeTab(int index) {
    final project = state.value?.currentProject;
    if (project == null) return;
    final newProject = _editorService.closeTab(project, index);
    updateCurrentProject(newProject);
  }

  void toggleFullScreen() {
    _updateStateSync((s) => s.copyWith(isFullScreen: !s.isFullScreen));
  }
  
  void updateCurrentProject(Project newProject) {
    _updateStateSync((s) => s.copyWith(currentProject: newProject));
  }
  
  // --- State Persistence & Helpers ---
  
  Future<void> saveAppState() async {
    final appState = state.value;
    if (appState == null) return;

    // 1. If a persistent project is open, save it to its own directory.
    // This call is now "fire and forget" from AppNotifier's perspective.
    if (appState.currentProject != null) {
      await _projectService.saveProject(appState.currentProject!);
    }
    
    // 2. Get the live tab metadata from the provider.
    final liveTabMetadata = ref.read(tabMetadataProvider);
    
    // 3. Convert the entire AppState into its persistable JSON form.
    // The AppState.toJson() method will correctly handle including the
    // simple project's state if necessary.
    final appStateJson = appState.toJson(liveTabMetadata);
    
    // 4. Pass the pure JSON to the repository for saving.
    await _appStateRepository.saveAppState(appStateJson);
  }

  void setBottomToolbarOverride(Widget? widget) =>
      _updateStateSync((s) => s.copyWith(bottomToolbarOverride: widget));

  void clearBottomToolbarOverride() =>
      _updateStateSync((s) => s.copyWith(clearBottomToolbarOverride: true));

  void clearClipboard() => ref.read(clipboardProvider.notifier).state = null;

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
}