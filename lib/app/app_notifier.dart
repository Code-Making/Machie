// lib/app/app_notifier.dart
import 'dart:typed_data';
import 'dart:ui' as ui; // REFACTOR: Add missing import

import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/persistence_service.dart';
import '../data/file_handler/file_handler.dart';
import '../editor/plugins/plugin_registry.dart';
import '../project/services/project_service.dart';
import '../editor/services/editor_service.dart';
import '../editor/editor_tab_models.dart';
import '../editor/tab_state_notifier.dart';
import '../utils/clipboard.dart';
import 'app_state.dart';
import '../explorer/common/save_as_dialog.dart';

// REFACTOR: Add missing imports
import '../explorer/common/file_explorer_dialogs.dart';
import '../editor/plugins/glitch_editor/glitch_editor_models.dart';
import '../editor/plugins/glitch_editor/glitch_editor_plugin.dart';

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

final currentProjectDirectoryContentsProvider =
    FutureProvider.autoDispose.family<List<DocumentFile>, String>((ref, uri) async {
  final handler = ref.watch(projectRepositoryProvider)?.fileHandler;
  if (handler == null) return [];

  final projectRoot =
      ref.watch(appNotifierProvider).value?.currentProject?.rootUri;
  if (projectRoot != null && !uri.startsWith(projectRoot)) return [];

  return handler.listDirectory(uri);
});

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
          final rehydratedProject = await _rehydrateTabs(project);
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

  // --- Toolbar Override Methods ---
  void setAppBarOverride(Widget? widget) =>
      _updateStateSync((s) => s.copyWith(appBarOverride: widget));
  void setBottomToolbarOverride(Widget? widget) =>
      _updateStateSync((s) => s.copyWith(bottomToolbarOverride: widget));
  void clearAppBarOverride() =>
      _updateStateSync((s) => s.copyWith(clearAppBarOverride: true));
  void clearBottomToolbarOverride() =>
      _updateStateSync((s) => s.copyWith(clearBottomToolbarOverride: true));

  // --- State Update Helpers ---
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

  // --- Project Management ---
  Future<void> openProjectFromFolder({
    required DocumentFile folder,
    required String projectTypeId,
  }) async {
    await _updateState((s) async {
      final result = await _projectService.openFromFolder(
        folder: folder,
        projectTypeId: projectTypeId,
        knownProjects: s.knownProjects,
      );

      return s.copyWith(
        currentProject: result.project,
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
      final rehydratedProject = await _rehydrateTabs(project);
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

  // --- File Operations ---
  Future<void> performFileOperation(
    Future<dynamic> Function(ProjectRepository) operation,
  ) async {
    final repo = ref.read(projectRepositoryProvider);
    if (repo == null) return;
    await operation(repo);
    ref.invalidate(currentProjectDirectoryContentsProvider);
  }

  void clearClipboard() => ref.read(clipboardProvider.notifier).state = null;

  // --- Tab Management ---
  void markCurrentTabDirty() {
    final currentUri = state.value?.currentProject?.session.currentTab?.file.uri;
    if (currentUri != null) {
      ref.read(tabStateProvider.notifier).markDirty(currentUri);
    }
  }

  Future<void> openFileInEditor(
    DocumentFile file, {
    EditorPlugin? explicitPlugin,
  }) async {
    final project = state.value?.currentProject;
    if (project == null) return;

    final result = await _editorService.openFile(
      project,
      file,
      explicitPlugin: explicitPlugin,
    );

    switch (result) {
      case OpenFileSuccess(
          project: final newProject,
          wasAlreadyOpen: final wasAlreadyOpen
        ):
        _updateStateSync((s) => s.copyWith(currentProject: newProject));
        if (wasAlreadyOpen) return;
        final context = ref.read(navigatorKeyProvider).currentContext;
        if (context != null && Navigator.of(context).canPop()) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }

      case OpenFileShowChooser(plugins: final plugins):
        final context = ref.read(navigatorKeyProvider).currentContext;
        if (context == null) return;
        final chosenPlugin = await showOpenWithDialog(context, plugins);
        if (chosenPlugin != null) {
          await openFileInEditor(file, explicitPlugin: chosenPlugin);
        }

      case OpenFileError(message: final msg):
        MachineToast.error(msg);
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
    
    // After saving bytes, we also need to update the originalImage in the plugin
    // to prevent "dirty" state from re-appearing on reset.
    final tab = project.session.currentTab;
    if (tab is GlitchEditorTab) {
      final plugin = tab.plugin as GlitchEditorPlugin;
      final image = plugin.getImageForTab(tab);
      if (image == null) return;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
       if (byteData == null) return;
       // This is a bit of a hack. The Glitch plugin should manage its own state.
       // A better solution would be a method like `plugin.markAsSaved(newBytes)`
       // For now, this is a quick fix.
       await _editorService.saveCurrentTab(project, bytes: byteData.buffer.asUint8List());
    }
  }

  Future<void> saveCurrentTabAs({
    Future<Uint8List?> Function()? byteDataProvider,
    Future<String?> Function()? stringDataProvider,
  }) async {
    final repo = ref.read(projectRepositoryProvider);
    final context = ref.read(navigatorKeyProvider).currentContext;
    final currentTab = state.value?.currentProject?.session.currentTab;

    if (repo == null || context == null || currentTab == null) return;

    final result = await showDialog<SaveAsDialogResult>(
      context: context,
      builder: (_) => SaveAsDialog(initialFileName: currentTab.file.name),
    );
    if (result == null) return;

    final DocumentFile newFile;
    if (byteDataProvider != null) {
      final bytes = await byteDataProvider();
      if (bytes == null) return;
      newFile = await repo.createDocumentFile(
        result.parentUri,
        result.fileName,
        initialBytes: bytes,
        overwrite: true,
      );
    } else if (stringDataProvider != null) {
      final content = await stringDataProvider();
      if (content == null) return;
      newFile = await repo.createDocumentFile(
        result.parentUri,
        result.fileName,
        initialContent: content,
        overwrite: true,
      );
    } else {
      return;
    }

    ref.invalidate(currentProjectDirectoryContentsProvider(result.parentUri));
    MachineToast.info("Saved as ${newFile.name}");
  }

  void closeTab(int index) {
    final project = state.value?.currentProject;
    if (project == null) return;
    final newProject = _editorService.closeTab(project, index);
    _updateStateSync((s) => s.copyWith(currentProject: newProject));
  }

  void updateCurrentTab(EditorTab newTab) {
    final project = state.value?.currentProject;
    if (project == null) return;
    final newProject = _editorService.updateTab(
      project,
      project.session.currentTabIndex,
      newTab,
    );
    _updateStateSync((s) => s.copyWith(currentProject: newProject));
  }
  
  // REFACTOR: This method is now only responsible for persisting the state.
  Future<void> saveAppState() async {
    final appState = state.value;
    if (appState == null) return;

    if (appState.currentProject != null) {
      // The service knows which repository to use and how to save.
      await _projectService.saveProject(appState.currentProject!);
    }

    // The app state repository handles SharedPreferences.
    await _appStateRepository.saveAppState(appState);
  }

  // --- Helpers ---
  Future<Project> _rehydrateTabs(Project project) async {
    final repo = ref.read(projectRepositoryProvider);
    if (repo == null) return project;
    // REFACTOR: The raw JSON for tabs is now in the project's session object.
    final projectStateJson = project.toJson();
    final sessionJson = projectStateJson['session'] as Map<String, dynamic>? ?? {};
    final tabsJson = sessionJson['tabs'] as List<dynamic>? ?? [];

    final plugins = ref.read(activePluginsProvider);
    final List<EditorTab> tabs = [];

    for (final tabJson in tabsJson) {
      final pluginType = tabJson['pluginType'] as String?;
      if (pluginType == null) continue;

      final plugin =
          plugins.firstWhereOrNull((p) => p.runtimeType.toString() == pluginType);
      if (plugin != null) {
        try {
          final tab = await plugin.createTabFromSerialization(tabJson, repo.fileHandler);
          tabs.add(tab);
          ref.read(tabStateProvider.notifier).initTab(tab.file.uri);
        } catch (e) {
          ref.read(talkerProvider).error('Could not restore tab: $e');
        }
      }
    }
    return project.copyWith(
      session: project.session.copyWith(tabs: tabs),
    );
  }
}