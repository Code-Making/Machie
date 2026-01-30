import 'dart:async';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/content_provider/file_content_provider.dart';
import '../data/file_handler/file_handler.dart';
import '../data/repositories/app_state_repository.dart';
import '../data/repositories/project/project_repository.dart';
import '../data/shared_preferences.dart';
import '../editor/models/editor_tab_models.dart';
import '../editor/plugins/editor_plugin_registry.dart';
import '../editor/services/editor_service.dart';
import '../editor/tab_metadata_notifier.dart';
import '../explorer/services/explorer_service.dart';
import '../logs/logs_provider.dart';
import '../project/project_models.dart';
import '../project/services/project_service.dart';
import '../utils/clipboard.dart';
import '../utils/toast.dart';
import '../widgets/dialogs/file_explorer_dialogs.dart';
import 'app_state.dart';

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
    _talker = ref.read(talkerProvider);
    _appStateRepository = AppStateRepository(
      await ref.watch(sharedPreferencesProvider.future),
      _talker,
    );
    _projectService = ref.watch(projectServiceProvider);
    _editorService = ref.watch(editorServiceProvider);
    _explorerService = ref.watch(explorerServiceProvider);

    ref.listen<AsyncValue<FileOperationEvent>>(fileOperationStreamProvider, (
      previous,
      next,
    ) {
      next.whenData((event) {
        _handleFileOperationEvent(event);
      });
    });

    final appStateDto = await _appStateRepository.loadAppStateDto();
    _talker.info("AppState loaded");

    if (appStateDto.lastOpenedProjectId != null) {
      _talker.info("Attempting to rehydrate last opened project.");
      final meta = appStateDto.knownProjects.firstWhereOrNull(
        (p) => p.id == appStateDto.lastOpenedProjectId,
      );
      if (meta != null) {
        try {
          final project = await _openProjectWithRecovery(
            meta,
            projectStateJson: appStateDto.currentProjectDto?.toJson(),
          );

          if (project != null) {
            _talker.info("Project rehydrated successfully.");
            return AppState(
              knownProjects: appStateDto.knownProjects,
              lastOpenedProjectId: appStateDto.lastOpenedProjectId,
              currentProject: project,
            );
          }
        } catch (e, st) {
          ref
              .read(talkerProvider)
              .handle(e, st, 'Failed to auto-open last project');
        }
      }
    }

    return AppState(
      knownProjects: appStateDto.knownProjects,
      lastOpenedProjectId: appStateDto.lastOpenedProjectId,
    );
  }

  Future<Project?> _openProjectWithRecovery(
    ProjectMetadata meta, {
    Map<String, dynamic>? projectStateJson,
  }) async {
    try {
      final projectDto = await _projectService.openProjectDto(
        meta,
        projectStateJson: projectStateJson,
      );
      final liveSession = await _editorService.rehydrateTabSession(
        projectDto,
        meta,
      );
      final liveWorkspace = _explorerService.rehydrateWorkspace(
        projectDto.workspace,
      );
      final liveSettings = _projectService.rehydrateProjectSettings(
        projectDto.settings,
        meta,
      );
      return Project(
        metadata: meta,
        session: liveSession,
        workspace: liveWorkspace,
        settings: liveSettings,
      );
    } on ProjectPermissionDeniedException catch (e) {
      final context = ref.read(navigatorKeyProvider).currentContext;

      if (context == null || !context.mounted) {
        _talker.error(
          "Permission denied for project '${e.metadata.name}', but no UI context was available to ask for permission again. Aborting open.",
        );
        return null;
      }

      final bool wantsToGrant = await showConfirmDialog(
        context,
        title: 'Permission Required',
        content:
            'Access to the project folder "${e.metadata.name}" has been lost. Please re-grant access.',
      );

      if (!context.mounted) {
        _talker.error(
          "Permission denied for project '${e.metadata.name}', but no UI context was available to ask for permission again. Aborting open.",
        );
        return null;
      }

      if (wantsToGrant == true) {
        final bool permissionGranted = await _projectService
            .recoverPermissionForProject(e.metadata, context);

        if (permissionGranted) {
          _talker.info("Permission re-granted. Retrying project open...");
          return await _openProjectWithRecovery(
            meta,
            projectStateJson: projectStateJson,
          );
        } else {
          _talker.warning(
            "User attempted to re-grant permission for project ${e.metadata.name}, but failed.",
          );
          MachineToast.error("Permission not granted.");
        }
      } else {
        _talker.warning(
          "User cancelled permission recovery for project ${e.metadata.name}.",
        );
        MachineToast.error("Could not open project: Permission not granted.");
      }

      return null;
    }
  }

  void _handleFileOperationEvent(FileOperationEvent event) {
    final project = state.value?.currentProject;
    if (project == null) return;

    switch (event) {
      case FileCreateEvent():
        break;
      case FileModifyEvent(/*modifiedFile: final modifiedFile*/):
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

  Future<UnsavedChangesAction> _handleUnsavedChanges(
    List<EditorTab> tabsToCheck,
  ) async {
    final metadataMap = ref.read(tabMetadataProvider);

    final dirtyTabsMetadata =
        tabsToCheck
            .map((tab) => metadataMap[tab.id])
            .nonNulls
            .where(
              (metadata) =>
                  metadata.isDirty && metadata.file is! VirtualDocumentFile,
            )
            .toList();

    if (dirtyTabsMetadata.isEmpty) {
      return UnsavedChangesAction.discard;
    }

    final context = ref.read(navigatorKeyProvider).currentContext;
    if (context == null || !context.mounted) {
      _talker.warning(
        'Cannot prompt to save dirty tabs: No valid BuildContext.',
      );
      return UnsavedChangesAction.cancel;
    }

    return await showUnsavedChangesDialog(
          context,
          dirtyFiles: dirtyTabsMetadata,
        ) ??
        UnsavedChangesAction.cancel;
  }

  Future<void> openKnownProject(String projectId) async {
    await _updateState((s) async {
      if (s.currentProject?.id == projectId) return s;
      if (s.currentProject != null) {
        final bool didClose = await closeProject();
        if (!didClose) return s;
        s = state.value!;
      }
      final meta = s.knownProjects.firstWhere((p) => p.id == projectId);

      final finalProject = await _openProjectWithRecovery(
        meta,
        projectStateJson: null,
      );

      if (finalProject != null) {
        return s.copyWith(
          currentProject: finalProject,
          lastOpenedProjectId: finalProject.id,
        );
      } else {
        return s.copyWith(clearCurrentProject: true);
      }
    });
    await saveAppState();
  }

  Future<bool> closeProject() async {
    final projectToClose = state.value?.currentProject;
    if (projectToClose == null) return true;


    final allTabs = projectToClose.session.tabs;
    final action = await _handleUnsavedChanges(allTabs);

    switch (action) {
      case UnsavedChangesAction.save:
        await _editorService.saveTabs(projectToClose, allTabs);
        break;
      case UnsavedChangesAction.discard:
        break;
      case UnsavedChangesAction.cancel:
        return false;
    }

    await _projectService.closeProject(projectToClose);
    _updateStateSync((s) => s.copyWith(clearCurrentProject: true));

    return true;
  }

  Future<void> createNewProject(ProjectMetadata newMetadata) async {
    await _updateState((s) async {
      if (s.currentProject != null) {
        final bool didClose = await closeProject();
        if (!didClose) return s;
        s = state.value!;
      }

      final projectDto = await _projectService.openProjectDto(newMetadata);

      final liveSession = await _editorService.rehydrateTabSession(
        projectDto,
        newMetadata,
      );
      final liveWorkspace = _explorerService.rehydrateWorkspace(
        projectDto.workspace,
      );
      final liveSettings = _projectService.rehydrateProjectSettings(
        projectDto.settings,
        newMetadata,
      );

      final finalProject = Project(
        metadata: newMetadata,
        session: liveSession,
        workspace: liveWorkspace,
        settings: liveSettings,
      );

      final knownProjects =
          s.knownProjects.where((p) => p.id != newMetadata.id).toList();

      return s.copyWith(
        currentProject: finalProject,
        lastOpenedProjectId: finalProject.id,
        knownProjects: [...knownProjects, newMetadata],
      );
    });
    await saveAppState();
  }

  Future<void> removeKnownProject(String projectId) async {
    await _updateState((s) async {
      if (s.currentProject?.id == projectId) {
        final bool didClose = await closeProject();
        if (!didClose) return s;
        s = state.value!;
      }

      final projectToRemove = s.knownProjects.firstWhereOrNull(
        (p) => p.id == projectId,
      );

      if (projectToRemove != null &&
          projectToRemove.persistenceTypeId == 'simple_state') {
        final prefs = await ref.read(sharedPreferencesProvider.future);
        final storageKey = 'project_state_${projectToRemove.id}';
        await prefs.remove(storageKey);
        _talker.info(
          'Cleared long-term state for removed simple project: ${projectToRemove.name}',
        );
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
    Completer<EditorWidgetState>? onReadyCompleter,
  }) async {
    final project = state.value?.currentProject;
    if (project == null) return false;

    final result = await _editorService.openFile(
      project,
      file,
      explicitPlugin: explicitPlugin,
      onReadyCompleter: onReadyCompleter,
    );

    switch (result) {
      case OpenFileSuccess(project: final newProject):
        updateCurrentProject(newProject);
        WidgetsBinding.instance.scheduleFrame();
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

  void closeTab(int index) async {
    final project = state.value?.currentProject;
    if (project == null) return;

    final tabToClose = project.session.tabs[index];
    final action = await _handleUnsavedChanges([tabToClose]);

    switch (action) {
      case UnsavedChangesAction.save:
        await _editorService.saveTab(project, tabToClose);
        break;
      case UnsavedChangesAction.discard:
        break;
      case UnsavedChangesAction.cancel:
        return;
    }

    final currentProject = state.value?.currentProject;
    if (currentProject == null) return;

    final newIndex = currentProject.session.tabs.indexOf(tabToClose);
    if (newIndex != -1) {
      final newProject = _editorService.closeTab(currentProject, newIndex);
      updateCurrentProject(newProject);
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  void closeMultipleTabs(List<int> indicesToClose) async {
    final project = state.value?.currentProject;
    if (project == null || indicesToClose.isEmpty) return;

    final sortedIndices = indicesToClose..sort((a, b) => b.compareTo(a));

    var newProject = project;
    for (final index in sortedIndices) {
      newProject = _editorService.closeTab(newProject, index);
    }

    updateCurrentProject(newProject);
    WidgetsBinding.instance.scheduleFrame();
  }

  void toggleFullScreen() {
    _updateStateSync((s) => s.copyWith(isFullScreen: !s.isFullScreen));
    saveAppState();
  }

  void updateCurrentProject(Project newProject) {
    _updateStateSync((s) => s.copyWith(currentProject: newProject));
  }


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

    if (currentProject != null) {
      await _projectService.saveProject(currentProject);
    }

    final registry = ref.read(fileContentProviderRegistryProvider);
    final liveTabMetadata = ref.read(tabMetadataProvider);

    final appStateDto = appState.toDto(liveTabMetadata, registry);
    await _appStateRepository.saveAppStateDto(appStateDto);
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
