// lib/app/app_notifier.dart
import 'package:flutter/material.dart'; // NEW IMPORT
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/persistence_service.dart';
import '../data/file_handler/file_handler.dart';
import '../plugins/plugin_models.dart'; // NEW IMPORT
import '../plugins/plugin_registry.dart'; // NEW IMPORT
import '../plugins/recipe_tex/recipe_tex_plugin.dart'; // NEW IMPORT for our custom exception
import '../project/project_manager.dart';
import '../project/project_models.dart';
import '../session/session_models.dart';
import '../session/tab_state.dart'; // NEW IMPORT
import '../utils/logs.dart'; // NEW IMPORT for logging
import '../utils/clipboard.dart';
import 'app_state.dart';

final appNotifierProvider = AsyncNotifierProvider<AppNotifier, AppState>(
  AppNotifier.new,
);

final navigatorKeyProvider = Provider((ref) => GlobalKey<NavigatorState>());
final rootScaffoldMessengerKeyProvider = Provider((ref) => GlobalKey<ScaffoldMessengerState>());

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
    
    // MODIFIED: Rehydration logic
    if (initialState.lastOpenedProjectId != null) {
      final meta = initialState.knownProjects.firstWhereOrNull(
        (p) => p.id == initialState.lastOpenedProjectId,
      );
      if (meta != null) {
        try {
          // Pass the saved state from AppState to the project manager.
          final project = await _projectManager.openProject(
            meta,
            projectStateJson: initialState.currentProjectState,
          );
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

    // MODIFIED: This method is now a pure controller.
  Future<void> openProjectFromFolder({
    required DocumentFile folder,
    required String projectTypeId,
  }) async {
    await _updateState((s) async {
      // 1. Delegate the complex business logic to the ProjectManager.
      //    Pass it the data it needs (the current list of known projects).
      final result = await _projectManager.openFromFolder(
        folder: folder,
        projectTypeId: projectTypeId,
        knownProjects: s.knownProjects,
      );

      // 2. Use the result to update the state. The controller's only job
      //    is to orchestrate this state update.
      return s.copyWith(
        currentProject: result.project,
        lastOpenedProjectId: result.project.id,
        // If the project was new, add its metadata to the list.
        knownProjects:
            result.isNew ? [...s.knownProjects, result.metadata] : s.knownProjects,
      );
    });
    // 3. Persist the new state.
    await saveAppState();
  }

  Future<void> openKnownProject(String projectId) async {
    await _updateState((s) async {
      final meta = s.knownProjects.firstWhere((p) => p.id == projectId);
      // We pass projectStateJson as null because we're opening a known project,
      // not rehydrating from a previous session state stored in AppState.
      // The project will load its own state from disk if it's persistent.
      final project = await _projectManager.openProject(meta, projectStateJson: null);
      return s.copyWith(
        currentProject: project,
        lastOpenedProjectId: project.id,
        // When opening a known project, its state is *not* loaded from AppState,
        // so we clear it to prevent stale data from being used later.
        clearCurrentProject: true, // This clears both project and projectState
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



Future<OpenFileResult> openFile(DocumentFile file, {EditorPlugin? explicitPlugin}) async {
    EditorPlugin? chosenPlugin = explicitPlugin;

    if (chosenPlugin == null) {
      final compatiblePlugins = ref
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
    
    // We now simply call the project's openFile method.
    // The error handling for parsing is now deferred to the AsyncNotifier of the plugin.
    final newTab = await selectedPlugin.createTab(file, "");

    // NEW: Initialize the tab's dirty state.
    ref.read(tabStateProvider.notifier).initTab(newTab.file.uri);

    
    return OpenFileSuccess();
  }
  

  // NEW: Helper method to show a snackbar (requires a BuildContext).
  // We can get this from a NavigatorKey or pass it from the UI.
  // For simplicity, let's assume a global key for now.
  // A better solution would involve a dedicated "messenger" service.
  void _showErrorSnackbar(String message) {
    // This is a simplified approach. In a real app, use a service that
    // doesn't depend on BuildContext.
    final scaffoldMessenger = ref.read(rootScaffoldMessengerKeyProvider).currentState;
    scaffoldMessenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  // NEW: Helper method to show the "Open With..." dialog.
  Future<EditorPlugin?> _showOpenWithDialog(List<EditorPlugin> plugins) async {
    // This also requires a context.
    final context = ref.read(navigatorKeyProvider).currentContext;
    if (context == null) return null;

    return await showDialog<EditorPlugin>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open with...'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: plugins.map((p) => ListTile(
            leading: p.icon,
            title: Text(p.name),
            onTap: () => Navigator.of(ctx).pop(p),
          )).toList(),
        ),
      ),
    );
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

  // MODIFIED: The new save method.
  Future<void> saveCurrentTab({required String content}) async {
    final project = state.value?.currentProject;
    if (project == null) return;
    
    final tabToSave = project.session.currentTab;
    if (tabToSave == null) return;

    // Perform the file write.
    await project.fileHandler.writeFile(tabToSave.file, content);
    
    // NEW: Mark the tab as clean in our dedicated state manager.
    ref.read(tabStateProvider.notifier).markClean(tabToSave.file.uri);
  }

  void closeTab(int index) {
    ref.read(tabStateProvider.notifier).removeTab(closedTab.file.uri);
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
    
    // For persistent projects, explicitly call save().
    if (appState.currentProject != null) {
      await _projectManager.saveProject(appState.currentProject!);
    }
    
    // This will now correctly serialize the currentProject's state into AppState.
    await _persistenceService.saveAppState(appState);
  }
}

@immutable
sealed class OpenFileResult {}

class OpenFileSuccess extends OpenFileResult {}

class OpenFileShowChooser extends OpenFileResult {
  final List<EditorPlugin> plugins;
  OpenFileShowChooser(this.plugins);
}

class OpenFileError extends OpenFileResult {
  final String message;
  OpenFileError(this.message);
}