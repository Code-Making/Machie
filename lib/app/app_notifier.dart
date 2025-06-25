// =========================================
// FILE: lib/app/app_notifier.dart
// =========================================

// lib/app/app_notifier.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    final talker = ref.read(talkerProvider);
    _appStateRepository = AppStateRepository(prefs, talker);
    _projectService = ref.watch(projectServiceProvider);
    _editorService = ref.watch(editorServiceProvider);

    ref.listen<AsyncValue<FileOperationEvent>>(fileOperationStreamProvider, (
      previous,
      next,
    ) {
      next.whenData((event) {
        _handleFileOperationEvent(event);
      });
    });

    final initialState = await _appStateRepository.loadAppState();
    
    if (initialState.lastOpenedProjectId != null) {
      final meta = initialState.knownProjects.firstWhereOrNull((p) => p.id == initialState.lastOpenedProjectId);
      if (meta != null) {
        try {
          // 1. Load the raw DTO from the appropriate repository.
          final projectDto = await _projectService.openProjectDto(
            meta,
            projectStateJson: initialState.currentProjectState,
          );
          
          // 2. Pass the DTO to the EditorService to get a fully rehydrated, live Project object.
          final finalProject = await _editorService.rehydrateProjectFromDto(projectDto, meta);
          
          // 3. Set the final state.
          return initialState.copyWith(
            currentProject: finalProject,
            clearCurrentProjectState: true,
          );
        } catch (e, st) {
          talker.handle(e, st, 'Failed to auto-open last project');
        }
      }
    }
    return initialState;
  }

  // ... (The rest of the file is correct and does not need changes) ...
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
        final tabIdToDelete = metadataMap.entries.firstWhereOrNull(
          (entry) => entry.value.file.uri == deletedFile.uri,
        )?.key;
        
        if (tabIdToDelete != null) {
          final tabIndex = project.session.tabs.indexWhere((t) => t.id == tabIdToDelete);
          if (tabIndex != -1) {
            final newProject = _editorService.closeTab(project, tabIndex);
            _updateStateSync((s) => s.copyWith(currentProject: newProject));
          }
        }
        break;
    }
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
            
      final liveSession = await _editorService.rehydrateTabSession(result.project.session);
      final finalProject = result.project.copyWith(session: liveSession);
      
      return s.copyWith(
        currentProject: finalProject,
        lastOpenedProjectId: result.project.id,
      );
    });
    await saveAppState();
  }

  // And the same logic for opening a known project.
  Future<void> openKnownProject(String projectId) async {
    await _updateState((s) async {
      if (s.currentProject?.id == projectId) return s;
      if (s.currentProject != null) {
        await _projectService.closeProject(s.currentProject!);
      }
      final meta = s.knownProjects.firstWhere((p) => p.id == projectId);
      
      final project = await _projectService.openProject(
        meta,
        projectStateJson: s.currentProjectState
      );
      
      final liveSession = await _editorService.rehydrateTabSession(project.session);
      final finalProject = project.copyWith(session: liveSession);
      
      return s.copyWith(
        currentProject: finalProject,
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

  void closeTab(int index) {
    final project = state.value?.currentProject;
    if (project == null) return;
    final newProject = _editorService.closeTab(project, index);
    _updateStateSync((s) => s.copyWith(currentProject: newProject));
  }

  void toggleFullScreen() {
    _updateStateSync((s) => s.copyWith(isFullScreen: !s.isFullScreen));
  }
  
  // ... (boilerplate like saveAppState, clearClipboard, etc. are unchanged)
  void setBottomToolbarOverride(Widget? widget) =>
      _updateStateSync((s) => s.copyWith(bottomToolbarOverride: widget));
  void clearBottomToolbarOverride() =>
      _updateStateSync((s) => s.copyWith(clearBottomToolbarOverride: true));
  void clearClipboard() => ref.read(clipboardProvider.notifier).state = null;
  Future<void> saveAppState() async {
    final appState = state.value;
    if (appState == null) return;
    if (appState.currentProject != null) {
      await _projectService.saveProject(appState.currentProject!);
    }
    await _appStateRepository.saveAppState(appState);
  }
}