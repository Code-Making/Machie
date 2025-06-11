// lib/app/app_notifier.dart
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/persistence_service.dart';
import '../data/file_handler/file_handler.dart';
import '../project/local_file_system_project.dart';
import '../project/project_manager.dart';
import '../project/project_models.dart';
import '../session/session_models.dart';
import '../utils/clipboard.dart';
import 'app_state.dart';

final appNotifierProvider = AsyncNotifierProvider<AppNotifier, AppState>(
  AppNotifier.new,
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
    // ... (build method is unchanged) ...
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    _persistenceService = PersistenceService(prefs);
    _projectManager = ref.watch(projectManagerProvider);

    final initialState = await _persistenceService.loadAppState();
    if (initialState.lastOpenedProjectId != null) {
      final meta = initialState.knownProjects.firstWhereOrNull(
        (p) => p.id == initialState.lastOpenedProjectId,
      );
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

  // ... (updater methods are unchanged) ...
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

  // ... (openProjectFromFolder, openKnownProject are unchanged) ...
  Future<void> openProjectFromFolder(DocumentFile folder) async {
    await _updateState((s) async {
      ProjectMetadata? meta = s.knownProjects.firstWhereOrNull(
        (p) => p.rootUri == folder.uri,
      );
      final isNew = meta == null;
      meta ??= await _projectManager.createNewProjectMetadata(
        folder.uri,
        folder.name,
      );

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
      return s.copyWith(
        currentProject: project,
        lastOpenedProjectId: project.id,
      );
    });
    await saveAppState();
  }

  Future<void> closeProject() async {
    final projectToClose = state.value?.currentProject;
    if (projectToClose == null) return;
    // MODIFIED: Pass the notifier's ref down to the manager.
    await _projectManager.closeProject(projectToClose, ref: ref);
    await _updateState((s) async => s.copyWith(clearCurrentProject: true));
  }
  
  // ... (the rest of the file is unchanged) ...
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

  // NEW: Add a method to handle file system operations that require UI refresh.
  Future<void> performFileOperation(
    Future<void> Function(FileHandler) operation,
  ) async {
    final project = state.value?.currentProject;
    if (project == null) return;

    // Perform the operation (e.g., delete, rename).
    await operation(project.fileHandler);

    // Invalidate providers to force a refresh of the file tree.
    // This is a simple but effective way to ensure the UI updates.
    ref.invalidate(currentProjectDirectoryContentsProvider);
  }

  // NEW: Method to clear the clipboard.
  void clearClipboard() {
    ref.read(clipboardProvider.notifier).state = null;
  }

  // MODIFIED: Delegate folder expansion logic to the concrete project implementation
  void toggleFolderExpansion(String folderUri) {
    _updateStateSync((s) {
      final project = s.currentProject;
      // This is a feature of LocalProject, so we check the type.
      if (project is! LocalProject) return s;

      final newProject = project.toggleFolderExpansion(folderUri);
      return s.copyWith(currentProject: newProject);
    });
  }

  // --- Tab Lifecycle (Delegation to Project) ---
  Future<void> openFile(DocumentFile file) async {
    await _updateState((s) async {
      if (s.currentProject == null) return s;
      // MODIFIED: Call method directly on project
      final newProject = await s.currentProject!.openFile(file, ref: ref);
      return s.copyWith(currentProject: newProject);
    });
  }

  void switchTab(int index) {
    _updateStateSync((s) {
      if (s.currentProject == null) return s;
      // MODIFIED: Call method directly on project
      final newProject = s.currentProject!.switchTab(index, ref: ref);
      return s.copyWith(currentProject: newProject);
    });
  }

  void reorderTabs(int oldIndex, int newIndex) {
    _updateStateSync((s) {
      if (s.currentProject == null) return s;
      // MODIFIED: Call method directly on project
      final newProject = s.currentProject!.reorderTabs(oldIndex, newIndex);
      return s.copyWith(currentProject: newProject);
    });
  }

  Future<void> saveCurrentTab() async {
    final project = state.value?.currentProject;
    if (project == null) return;

    await _updateState((s) async {
      // MODIFIED: Call method directly on project
      final newProject = await s.currentProject!
          .saveTab(s.currentProject!.session.currentTabIndex);
      return s.copyWith(currentProject: newProject);
    });
  }

  void closeTab(int index) {
    _updateStateSync((s) {
      if (s.currentProject == null) return s;
      // MODIFIED: Call method directly on project
      final newProject = s.currentProject!.closeTab(index, ref: ref);
      return s.copyWith(currentProject: newProject);
    });
  }

  void markCurrentTabDirty() {
    _updateStateSync((s) {
      if (s.currentProject == null) return s;
      // MODIFIED: Call method directly on project
      final newProject = s.currentProject!.markCurrentTabDirty();
      return s.copyWith(currentProject: newProject);
    });
  }

  void updateCurrentTab(EditorTab newTab) {
    _updateStateSync((s) {
      if (s.currentProject == null) return s;
      // MODIFIED: Call method directly on project
      final newProject = s.currentProject!.updateTab(
        s.currentProject!.session.currentTabIndex,
        newTab,
      );
      return s.copyWith(currentProject: newProject);
    });
  }

  // --- Persistence ---
  Future<void> saveAppState() async {
    final appState = state.value;
    if (appState == null) return;
    if (appState.currentProject != null) {
      // MODIFIED: Use the decoupled ProjectManager
      await _projectManager.saveProject(appState.currentProject!);
    }
    await _persistenceService.saveAppState(appState);
  }
}