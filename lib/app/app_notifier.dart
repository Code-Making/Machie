// lib/app/app_notifier.dart
import 'dart:typed_data'; // NEW IMPORT

import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/persistence_service.dart';
import '../data/file_handler/file_handler.dart';
import '../editor/plugins/plugin_registry.dart';
import '../project/project_manager.dart';
import '../editor/editor_tab_models.dart';
import '../editor/tab_state_notifier.dart';
import '../utils/clipboard.dart';
import 'app_state.dart';
import '../explorer/common/save_as_dialog.dart'; // NEW IMPORT

import '../logs/logs_provider.dart';
import '../utils/toast.dart';

final appNotifierProvider = AsyncNotifierProvider<AppNotifier, AppState>(
  AppNotifier.new,
);

final navigatorKeyProvider = Provider((ref) => GlobalKey<NavigatorState>());
final rootScaffoldMessengerKeyProvider = Provider(
  (ref) => GlobalKey<ScaffoldMessengerState>(),
);

// ... (currentProjectDirectoryContentsProvider is unchanged) ...
final currentProjectDirectoryContentsProvider = FutureProvider.autoDispose
    .family<List<DocumentFile>, String>((ref, uri) async {
      final handler =
          ref.watch(appNotifierProvider).value?.currentProject?.fileHandler;
      if (handler == null) return [];

      final projectRoot =
          ref.watch(appNotifierProvider).value?.currentProject?.rootUri;
      if (projectRoot != null && !uri.startsWith(projectRoot)) return [];

      return handler.listDirectory(uri);
    });

class AppNotifier extends AsyncNotifier<AppState> {
  late PersistenceService _persistenceService;
  late ProjectManager _projectManager;

  @override
  Future<AppState> build() async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    _persistenceService = PersistenceService(prefs);
    _projectManager = ref.watch(projectManagerProvider);
    final talker = ref.read(talkerProvider); // Get Talker instance
    final initialState = await _persistenceService.loadAppState();

    if (initialState.lastOpenedProjectId != null) {
      final meta = initialState.knownProjects.firstWhereOrNull(
        (p) => p.id == initialState.lastOpenedProjectId,
      );
      if (meta != null) {
        try {
          final project = await _projectManager.openProject(
            meta,
            projectStateJson: initialState.currentProjectState,
          );
          return initialState.copyWith(currentProject: project);
        } catch (e, st) {
          talker.handle(e, st, 'Failed to auto-open last project');
        }
      }
    }
    return initialState;
  }

  // --- Toolbar Override Methods ---
  void setAppBarOverride(Widget? widget) {
    _updateStateSync((s) => s.copyWith(appBarOverride: widget));
  }

  void setBottomToolbarOverride(Widget? widget) {
    _updateStateSync((s) => s.copyWith(bottomToolbarOverride: widget));
  }

  void clearAppBarOverride() {
    _updateStateSync((s) => s.copyWith(clearAppBarOverride: true));
  }

  void clearBottomToolbarOverride() {
    _updateStateSync((s) => s.copyWith(clearBottomToolbarOverride: true));
  }
  // --- End Toolbar Override Methods ---

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

  void updateProject(Project newProject) {
    _updateStateSync((s) => s.copyWith(currentProject: newProject));
  }

  Future<void> openProjectFromFolder({
    required DocumentFile folder,
    required String projectTypeId,
  }) async {
    await _updateState((s) async {
      final result = await _projectManager.openFromFolder(
        folder: folder,
        projectTypeId: projectTypeId,
        knownProjects: s.knownProjects,
      );

      return s.copyWith(
        currentProject: result.project,
        lastOpenedProjectId: result.project.id,
        knownProjects:
            result.isNew
                ? [...s.knownProjects, result.metadata]
                : s.knownProjects,
      );
    });
    await saveAppState();
  }

  Future<void> openKnownProject(String projectId) async {
    await _updateState((s) async {
      final meta = s.knownProjects.firstWhere((p) => p.id == projectId);
      final project = await _projectManager.openProject(
        meta,
        projectStateJson: null,
      );
      return s.copyWith(
        currentProject: project,
        lastOpenedProjectId: project.id,
        clearCurrentProject: true,
      );
    });
    await saveAppState();
  }

  Future<void> closeProject() async {
    final projectToClose = state.value?.currentProject;
    if (projectToClose == null) return;
    await _projectManager.closeProject(projectToClose, ref: ref);
    await _updateState((s) async => s.copyWith(clearCurrentProject: true));
  }

  Future<void> removeKnownProject(String projectId) async {
    await _updateState((previousState) async {
      if (previousState.currentProject?.id == projectId) {
        await closeProject();
        previousState = state.value!;
      }
      return previousState.copyWith(
        knownProjects:
            previousState.knownProjects
                .where((p) => p.id != projectId)
                .toList(),
      );
    });
    await saveAppState();
  }

  Future<void> performFileOperation(
    Future<void> Function(FileHandler) operation,
  ) async {
    final project = state.value?.currentProject;
    if (project == null) return;

    await operation(project.fileHandler);

    ref.invalidate(currentProjectDirectoryContentsProvider);
  }

  void clearClipboard() {
    ref.read(clipboardProvider.notifier).state = null;
  }

  void markCurrentTabDirty() {
    final currentUri =
        state.value?.currentProject?.session.currentTab?.file.uri;
    if (currentUri != null) {
      ref.read(tabStateProvider.notifier).markDirty(currentUri);
    }
  }

  Future<OpenFileResult> openFile(
    DocumentFile file, {
    EditorPlugin? explicitPlugin,
  }) async {
    EditorPlugin? chosenPlugin = explicitPlugin;

    if (chosenPlugin == null) {
      final compatiblePlugins =
          ref
              .read(activePluginsProvider)
              .where((p) => p.supportsFile(file))
              .toList();

      if (compatiblePlugins.isEmpty) {
        return OpenFileError("No plugin available to open '${file.name}'.");
      } else if (compatiblePlugins.length > 1) {
        return OpenFileShowChooser(compatiblePlugins);
      } else {
        chosenPlugin = compatiblePlugins.first;
      }
    }

    await _updateState((s) async {
      final newProject = await s.currentProject!.openFile(
        file,
        plugin: chosenPlugin,
        ref: ref,
      );
      return s.copyWith(currentProject: newProject);
    });

    ref.read(tabStateProvider.notifier).initTab(file.uri);

    return OpenFileSuccess();
  }

  void switchTab(int index) {
    _updateStateSync((s) {
      if (s.currentProject == null) return s;
      final newProject = s.currentProject!.switchTab(index, ref: ref);
      return s.copyWith(currentProject: newProject);
    });
  }

  void reorderTabs(int oldIndex, int newIndex) {
    _updateStateSync((s) {
      if (s.currentProject == null) return s;
      final newProject = s.currentProject!.reorderTabs(oldIndex, newIndex);
      return s.copyWith(currentProject: newProject);
    });
  }

  Future<void> saveCurrentTab({required String content}) async {
    final project = state.value?.currentProject;
    if (project == null) return;

    final tabToSave = project.session.currentTab;
    if (tabToSave == null) return;

    await project.fileHandler.writeFile(tabToSave.file, content);

    ref.read(tabStateProvider.notifier).markClean(tabToSave.file.uri);
  }

  Future<void> saveCurrentTabAs({
    Future<Uint8List?> Function()? byteDataProvider,
    Future<String?> Function()? stringDataProvider,
  }) async {
    final project = state.value?.currentProject;
    final context = ref.read(navigatorKeyProvider).currentContext;
    if (project == null || context == null) return;

    final currentTab = project.session.currentTab;
    if (currentTab == null) return;

    final result = await showDialog<SaveAsDialogResult>(
      context: context,
      builder: (_) => SaveAsDialog(initialFileName: currentTab.file.name),
    );

    if (result == null) return;

    DocumentFile newFile;

    if (byteDataProvider != null) {
      final bytes = await byteDataProvider();
      if (bytes == null) return;
      // This is not yet supported by createDocumentFile, so we'll stub it for now
      // A proper implementation would add `initialBytesContent` to createDocumentFile.
      // For now, we write an empty file then overwrite it.
      newFile = await project.fileHandler.createDocumentFile(
        result.parentUri,
        result.fileName,
        overwrite: true,
      );
      newFile = await project.fileHandler.writeFileAsBytes(newFile, bytes);
    } else if (stringDataProvider != null) {
      final content = await stringDataProvider();
      if (content == null) return;
      newFile = await project.fileHandler.createDocumentFile(
        result.parentUri,
        result.fileName,
        initialContent: content,
        overwrite: true,
      );
    } else {
      return; // No data provider
    }

    ref.invalidate(currentProjectDirectoryContentsProvider(result.parentUri));

    MachineToast.info("Saved as ${newFile.name}");
  }

  // NEW METHOD for saving raw bytes
  Future<void> saveCurrentTabAsBytes(Uint8List bytes) async {
    final project = state.value?.currentProject;
    if (project == null) return;

    final tabToSave = project.session.currentTab;
    if (tabToSave == null) return;

    await project.fileHandler.writeFileAsBytes(tabToSave.file, bytes);

    ref.read(tabStateProvider.notifier).markClean(tabToSave.file.uri);
  }

  void closeTab(int index) {
    final project = state.value?.currentProject;
    if (project == null) return;

    final closedTab = project.session.tabs[index];

    _updateStateSync((s) {
      final newProject = s.currentProject!.closeTab(index, ref: ref);
      return s.copyWith(currentProject: newProject);
    });

    ref.read(tabStateProvider.notifier).removeTab(closedTab.file.uri);
  }

  void updateCurrentTab(EditorTab newTab) {
    _updateStateSync((s) {
      if (s.currentProject == null) return s;
      final newProject = s.currentProject!.updateTab(
        s.currentProject!.session.currentTabIndex,
        newTab,
      );
      return s.copyWith(currentProject: newProject);
    });
  }

  Future<void> saveAppState() async {
    final appState = state.value;
    if (appState == null) return;

    if (appState.currentProject != null) {
      await _projectManager.saveProject(appState.currentProject!);
    }

    await _persistenceService.saveAppState(appState);
  }
}

