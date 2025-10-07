// =========================================
// lib/app/app_notifier.dart
// =========================================

import 'dart:async';
import 'package:collection/collection.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_state.dart';

import '../data/persistence_service.dart';
import '../data/file_handler/file_handler.dart';
import '../data/repositories/project_repository.dart';
import '../editor/plugins/plugin_registry.dart';
import '../editor/services/editor_service.dart';
import '../editor/tab_state_manager.dart';
import '../explorer/services/explorer_service.dart';
import '../explorer/common/file_explorer_dialogs.dart';
import '../logs/logs_provider.dart';
import '../project/project_models.dart';
import '../project/services/project_service.dart';
import '../utils/clipboard.dart';
import '../utils/toast.dart';

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
  late ExplorerService _explorerService;
  late Talker _talker;
  @override
  Future<AppState> build() async {
    // Initialize dependencies
    _talker = ref.read(talkerProvider);
    _appStateRepository = AppStateRepository(
      await ref.watch(sharedPreferencesProvider.future),
      _talker,
    );
    _projectService = ref.watch(projectServiceProvider);
    _editorService = ref.watch(editorServiceProvider);
    _explorerService = ref.watch(explorerServiceProvider);

    // Subscribe to file system events to keep UI in sync
    ref.listen<AsyncValue<FileOperationEvent>>(fileOperationStreamProvider, (
      previous,
      next,
    ) {
      next.whenData((event) {
        _handleFileOperationEvent(event);
      });
    });

    // 1. Load the raw DTO for the entire app state.
    final appStateDto = await _appStateRepository.loadAppStateDto();
    _talker.info("AppState loaded");
    _talker.info("Checking last opened project");
    // 2. Attempt to re-open the last project based on the DTO.
    if (appStateDto.lastOpenedProjectId != null) {
      final meta = appStateDto.knownProjects.firstWhereOrNull(
        (p) => p.id == appStateDto.lastOpenedProjectId,
      );
      if (meta != null) {
        _talker.info("Found Project to load");
        try {
          final projectDto = await _projectService.openProjectDto(
            meta,
            projectStateJson: appStateDto.currentSimpleProjectDto?.toJson(),
          );

          final liveSession = await _editorService.rehydrateTabSession(
            projectDto,
            meta,
          );
          final liveWorkspace = _explorerService.rehydrateWorkspace(
            projectDto.workspace,
          );

          final finalProject = Project(
            metadata: meta,
            session: liveSession,
            workspace: liveWorkspace,
          );
          _talker.info("Project should be loaded");
          return AppState(
            knownProjects: appStateDto.knownProjects,
            lastOpenedProjectId: appStateDto.lastOpenedProjectId,
            currentProject: finalProject,
          );
        } catch (e, st) {
          ref
              .read(talkerProvider)
              .handle(e, st, 'Failed to auto-open last project');
        }
      }
    }

    // 3. Fallback: If no project was reopened, construct a default live AppState.
    return AppState(
      knownProjects: appStateDto.knownProjects,
      lastOpenedProjectId: appStateDto.lastOpenedProjectId,
    );
  }

  /// Handles events published by the ProjectRepository to keep the UI in sync.
  void _handleFileOperationEvent(FileOperationEvent event) {
    final project = state.value?.currentProject;
    if (project == null) return;

    switch (event) {
      case FileCreateEvent():
        break;

      case FileRenameEvent(oldFile: final oldFile, newFile: final newFile):
        _editorService.updateTabForRenamedFile(oldFile.uri, newFile);
        break;

      case FileDeleteEvent(deletedFile: final deletedFile):
        final metadataMap = ref.read(tabMetadataProvider);
        final tabIdToDelete =
            metadataMap.entries
                .firstWhereOrNull(
                  (entry) => entry.value.file.uri == deletedFile.uri,
                )
                ?.key;

        if (tabIdToDelete != null) {
          final tabIndex = project.session.tabs.indexWhere(
            (t) => t.id == tabIdToDelete,
          );
          if (tabIndex != -1) {
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
        await closeProject();
      }

      final result = await _projectService.openFromFolder(
        folder: folder,
        projectTypeId: projectTypeId,
        knownProjects: s.knownProjects,
      );

      final liveSession = await _editorService.rehydrateTabSession(
        result.projectDto,
        result.metadata,
      );
      final liveWorkspace = _explorerService.rehydrateWorkspace(
        result.projectDto.workspace,
      );

      final finalProject = Project(
        metadata: result.metadata,
        session: liveSession,
        workspace: liveWorkspace,
      );

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
        await closeProject();
        // After closing, the state may have updated, so we need to get the latest version.
        s = state.value!;
      }
      final meta = s.knownProjects.firstWhere((p) => p.id == projectId);

      final appStateDto = await _appStateRepository.loadAppStateDto();
      final projectDto = await _projectService.openProjectDto(
        meta,
        projectStateJson:
            (appStateDto.lastOpenedProjectId == projectId)
                ? appStateDto.currentSimpleProjectDto?.toJson()
                : null,
      );

      final liveSession = await _editorService.rehydrateTabSession(
        projectDto,
        meta,
      );
      final liveWorkspace = _explorerService.rehydrateWorkspace(
        projectDto.workspace,
      );

      final finalProject = Project(
        metadata: meta,
        session: liveSession,
        workspace: liveWorkspace,
      );

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

    // REMOVED: The call to clear projectHierarchyProvider is no longer needed.
    // The new ProjectHierarchyService listens for project changes and clears itself.

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
        if (context == null || !context.mounted) return false;
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
    saveAppState();
  }

  void updateCurrentProject(Project newProject) {
    _updateStateSync((s) => s.copyWith(currentProject: newProject));
  }

  // --- State Persistence & Helpers ---

  Future<void> saveAppState() async {
    final project = state.value?.currentProject;
    if (project != null) {
      await ref.read(editorServiceProvider).flushAllHotTabs();
    }
    await saveNonHotState();
  }

  Future<void> saveNonHotState() async {
    final appState = state.value;
    if (appState == null) return;

    final currentProject = appState.currentProject;

    if (currentProject?.projectTypeId == 'local_persistent') {
      await _projectService.saveProject(currentProject!);
    }

    final liveTabMetadata = ref.read(tabMetadataProvider);
    final appStateDto = appState.toDto(liveTabMetadata);
    await _appStateRepository.saveAppStateDto(appStateDto);
  }

  void setAppBarOverride(Widget? widget) =>
      _updateStateSync((s) => s.copyWith(appBarOverride: widget));

  void clearAppBarOverride() =>
      _updateStateSync((s) => s.copyWith(clearAppBarOverride: true));

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
