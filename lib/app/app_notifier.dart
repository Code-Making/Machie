// lib/app/app_notifier.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/persistence_service.dart';
import '../data/file_handler/file_handler.dart';
import '../editor/plugins/plugin_registry.dart';
import '../project/services/project_service.dart';
import '../editor/services/editor_service.dart';
import '../editor/editor_tab_models.dart';
import '../editor/tab_state_manager.dart';
import '../utils/clipboard.dart';
import 'app_state.dart';
import '../explorer/common/save_as_dialog.dart';

import '../explorer/common/file_explorer_dialogs.dart';

import '../logs/logs_provider.dart';
import '../utils/toast.dart';
import '../data/repositories/project_repository.dart';
import '../project/project_models.dart';

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
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    _appStateRepository = AppStateRepository(prefs);
    _projectService = ref.watch(projectServiceProvider);
    _editorService = ref.watch(editorServiceProvider);
    final talker = ref.read(talkerProvider);

    // Subscribe to file operation events.
    ref.listen<AsyncValue<FileOperationEvent>>(fileOperationStreamProvider, (previous, next) {
      next.whenData((event) {
        _handleFileOperationEvent(event);
      });
    });

    final initialState = await _appStateRepository.loadAppState();

    if (initialState.lastOpenedProjectId != null) {
      final meta = initialState.knownProjects.firstWhereOrNull(
        (p) => p.id == initialState.lastOpenedProjectId,
      );
      if (meta != null) {
        try {
          final project = await _projectService.openProject(
            meta,
            projectStateJson: initialState.currentProjectState,
          );
          final rehydratedProject = await _editorService.rehydrateTabs(project);
          return initialState.copyWith(
            currentProject: rehydratedProject,
            clearCurrentProjectState: true,
          );
        } catch (e, st) {
          talker.handle(e, st, 'Failed to auto-open last project');
        }
      }
    }
    return initialState;
  }

  /// Handles events published by the ProjectRepository to keep the UI in sync.
  void _handleFileOperationEvent(FileOperationEvent event) {
    final project = state.value?.currentProject;
    if (project == null) return;
    
    switch (event) {
      case FileCreateEvent():
        // No action needed here. The file hierarchy is already updated by the
        // repository, and the UI will react to that change automatically.
        break;
        
      case FileRenameEvent(oldFile: final oldFile, newFile: final newFile):
        final newProject = _editorService.updateTabFile(project, oldFile.uri, newFile);
        _updateStateSync((s) => s.copyWith(currentProject: newProject));
        break;
        
      case FileDeleteEvent(deletedFile: final deletedFile):
        final tabIndex = project.session.tabs.indexWhere((t) => t.file.uri == deletedFile.uri);
        if (tabIndex != -1) {
          final newProject = _editorService.closeTab(project, tabIndex);
          _updateStateSync((s) => s.copyWith(currentProject: newProject));
        }
        break;
    }
  }

  void setAppBarOverride(Widget? widget) =>
      _updateStateSync((s) => s.copyWith(appBarOverride: widget));
  void setBottomToolbarOverride(Widget? widget) =>
      _updateStateSync((s) => s.copyWith(bottomToolbarOverride: widget));
  void clearAppBarOverride() =>
      _updateStateSync((s) => s.copyWith(clearAppBarOverride: true));
  void clearBottomToolbarOverride() =>
      _updateStateSync((s) => s.copyWith(clearBottomToolbarOverride: true));

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
  
  void updateCurrentProject(Project newProject) {
    _updateStateSync((s) => s.copyWith(currentProject: newProject));
  }

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
      final rehydratedProject = await _editorService.rehydrateTabs(result.project);
      return s.copyWith(
        currentProject: rehydratedProject,
        lastOpenedProjectId: result.project.id,
        knownProjects:
            result.isNew ? [...s.knownProjects, result.metadata] : s.knownProjects,
      );
    });
    await saveAppState();
  }

  Future<void> openKnownProject(String projectId) async {
    await _updateState((s) async {
      if (s.currentProject?.id == projectId) return s;
      if (s.currentProject != null) {
        await _projectService.closeProject(s.currentProject!);
      }
      final meta = s.knownProjects.firstWhere((p) => p.id == projectId);
      final project = await _projectService.openProject(meta);
      final rehydratedProject = await _editorService.rehydrateTabs(project);
      return s.copyWith(
        currentProject: rehydratedProject,
        lastOpenedProjectId: project.id,
      );
    });
    await saveAppState();
  }

  Future<void> closeProject() async {
    final projectToClose = state.value?.currentProject;
    if (projectToClose == null) return;
    await _projectService.closeProject(projectToClose);
    _updateStateSync((s) => s.copyWith(clearCurrentProject: true));
  }

  Future<void> removeKnownProject(String projectId) async {
    await _updateState((s) async {
      if (s.currentProject?.id == projectId) {
        await closeProject();
        s = state.value!;
      }
      return s.copyWith(
        knownProjects: s.knownProjects.where((p) => p.id != projectId).toList(),
      );
    });
    await saveAppState();
  }

  void clearClipboard() => ref.read(clipboardProvider.notifier).state = null;

  void markCurrentTabDirty() {
    final currentUri = state.value?.currentProject?.session.currentTab?.file.uri;
    if (currentUri != null) {
      ref.read(tabStateManagerProvider.notifier).markDirty(currentUri);
    }
  }

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
        _updateStateSync((s) => s.copyWith(currentProject: newProject));
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

  void switchTab(int index) {
    final project = state.value?.currentProject;
    if (project == null) return;
    final newProject = _editorService.switchTab(project, index);
    _updateStateSync((s) => s.copyWith(currentProject: newProject));
  }

  void reorderTabs(int oldIndex, int newIndex) {
    final project = state.value?.currentProject;
    if (project == null) return;
    final newProject = _editorService.reorderTabs(project, oldIndex, newIndex);
    _updateStateSync((s) => s.copyWith(currentProject: newProject));
  }

  Future<void> saveCurrentTab({required String content}) async {
    final project = state.value?.currentProject;
    if (project == null) return;
    await _editorService.saveCurrentTab(project, content: content);
  }

  Future<void> saveCurrentTabAsBytes(Uint8List bytes) async {
    final project = state.value?.currentProject;
    if (project == null) return;
    await _editorService.saveCurrentTab(project, bytes: bytes);
  }

    // FIX: This logic is now fully encapsulated in EditorService.
  // The AppNotifier method is just a clean, simple delegation.
  Future<void> saveCurrentTabAs({
    Future<Uint8List?> Function()? byteDataProvider,
    Future<String?> Function()? stringDataProvider,
  }) async {
    await _editorService.saveCurrentTabAs(
      byteDataProvider: byteDataProvider,
      stringDataProvider: stringDataProvider,
    );
  }

  void closeTab(int index) {
    final project = state.value?.currentProject;
    if (project == null) return;
    final newProject = _editorService.closeTab(project, index);
    _updateStateSync((s) => s.copyWith(currentProject: newProject));
  }
  
  void toggleFullScreen() {
    _updateStateSync((s) => s.copyWith(isFullScreen: !s.isFullScreen));
  }

  Future<void> saveAppState() async {
    final appState = state.value;
    if (appState == null) return;

    if (appState.currentProject != null) {
      await _projectService.saveProject(appState.currentProject!);
    }
    await _appStateRepository.saveAppState(appState);
  }
}