import 'dart:async';
import 'dart:convert'; // For utf8
import 'dart:typed_data';
import 'package:crypto/crypto.dart'; // For md5
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';

import '../../app/app_notifier.dart';
import '../../data/repositories/project_repository.dart';
import '../../editor/editor_tab_models.dart';
import '../../editor/plugins/plugin_registry.dart';
import '../../project/project_models.dart';
import '../../logs/logs_provider.dart';
import '../../data/file_handler/file_handler.dart' show DocumentFile;
import 'text_editing_capability.dart'; // <-- ADD THIS IMPORT
import '../tab_state_manager.dart';
import '../../explorer/common/save_as_dialog.dart';
import '../../explorer/common/file_explorer_dialogs.dart';
import '../../explorer/services/explorer_service.dart';
import '../../utils/toast.dart';
import '../../data/dto/project_dto.dart';
import '../../data/dto/tab_hot_state_dto.dart';
import '../../data/cache/hot_state_cache_service.dart';

final editorServiceProvider = Provider<EditorService>((ref) {
  return EditorService(ref);
});

class EditorService {
  final Ref _ref;
  EditorService(this._ref);

  Project? get _currentProject =>
      _ref.read(appNotifierProvider).value?.currentProject;
  EditorTab? get _currentTab => _currentProject?.session.currentTab;

  ProjectRepository get _repo {
    final repo = _ref.read(projectRepositoryProvider);
    if (repo == null) {
      throw StateError('ProjectRepository is not available.');
    }
    return repo;
  }

  Future<TabSessionState> rehydrateTabSession(
    ProjectDto dto,
    ProjectMetadata projectMetadata,
  ) async {
    final plugins = _ref.read(activePluginsProvider);
    final metadataNotifier = _ref.read(tabMetadataProvider.notifier);
    final hotStateCacheService = _ref.read(hotStateCacheServiceProvider);
    final talker = _ref.read(talkerProvider);

    final List<EditorTab> rehydratedTabs = [];
    talker.info("Rehydrating tabs");

    for (final tabDto in dto.session.tabs) {
      // ... setup logic for tabId, plugin, file, etc. ...
      final tabId = tabDto.id;
      final pluginId = tabDto.pluginType;
      final persistedMetadata = dto.session.tabMetadata[tabId];

      if (persistedMetadata == null) continue;

      final plugin = plugins.firstWhereOrNull((p) => p.id == pluginId);
      if (plugin == null) continue;

      try {
        final file = await _repo.fileHandler.getFileMetadata(
          persistedMetadata.fileUri,
        );
        if (file == null) continue;

        // ... logic for reading file content and checking for cache conflicts is unchanged ...
        String? fileContent;
        Uint8List? fileBytes;
        if (plugin.dataRequirement == PluginDataRequirement.bytes) {
          fileBytes = await _repo.readFileAsBytes(file.uri);
        } else {
          fileContent = await _repo.readFile(file.uri);
        }
        final currentDiskHash = (plugin.dataRequirement == PluginDataRequirement.bytes) ? md5.convert(fileBytes!).toString() : md5.convert(utf8.encode(fileContent!)).toString();
        TabHotStateDto? cachedDto = await hotStateCacheService.getTabState( projectMetadata.id, tabId, );
        if (cachedDto?.baseContentHash != null && cachedDto!.baseContentHash != currentDiskHash) {
          talker.warning( 'Cache conflict detected for ${file.name}. ' 'Cached Hash: ${cachedDto.baseContentHash}, ' 'Disk Hash: $currentDiskHash', );
          final context = _ref.read(navigatorKeyProvider).currentContext;
          if (context != null) {
            final resolution = await showCacheConflictDialog( context, fileName: file.name, );
            if (resolution == CacheConflictResolution.loadDisk) {
              talker.info('User chose to discard cache for ${file.name}.');
              await hotStateCacheService.clearTabState( projectMetadata.id, tabId, );
              cachedDto = null;
            }
          }
        }
        
        final initData = EditorInitData(
          stringData: fileContent,
          byteData: fileBytes,
          hotState: cachedDto,
          baseContentHash: currentDiskHash,
        );

        final newTab = await plugin.createTab(file, initData, id: tabId);
        
        // --- THIS IS THE FIX ---
        // 1. Initialize the metadata. The widget state will report if it's dirty later.
        metadataNotifier.initTab(newTab.id, file);

        // 2. REMOVED: Do NOT manually mark as dirty here.
        // if (cachedDto != null || persistedMetadata.isDirty) {
        //   metadataNotifier.markDirty(newTab.id);
        // }
        // -------------------------

        rehydratedTabs.add(newTab);
      } catch (e, st) {
        _ref.read(talkerProvider).handle(
              e,
              st,
              'Could not restore tab for ${persistedMetadata.fileUri}',
            );
      }
    }

    return TabSessionState(
      tabs: rehydratedTabs,
      currentTabIndex: dto.session.currentTabIndex,
    );
  }

  Future<({EditorTab tab, DocumentFile file})?> _createTabForFile(
    DocumentFile file, {
    EditorPlugin? explicitPlugin,
  }) async {
    final compatiblePlugins =
        _ref
            .read(activePluginsProvider)
            .where((p) => p.supportsFile(file))
            .toList();

    EditorPlugin? chosenPlugin = explicitPlugin;
    if (chosenPlugin == null) {
      if (compatiblePlugins.isEmpty) return null;
      chosenPlugin = compatiblePlugins.first;
    }

    try {
      String? fileContent;
      Uint8List? fileBytes;
      String? baseContentHash; // <-- ADDED

      if (chosenPlugin.dataRequirement != PluginDataRequirement.bytes) {
        fileContent = await _repo.readFile(file.uri);
        baseContentHash = md5.convert(utf8.encode(fileContent)).toString();
      } else {
        fileBytes = await _repo.readFileAsBytes(file.uri);
        baseContentHash = md5.convert(fileBytes).toString();
      }

      final initData = EditorInitData(
        stringData: fileContent,
        byteData: fileBytes,
        baseContentHash: baseContentHash, // <-- PASS THE HASH
      );

      final newTab = await chosenPlugin.createTab(file, initData);
      return (tab: newTab, file: file);
    } catch (e) {
      _ref
          .read(talkerProvider)
          .error("Could not read file data for tab: ${file.uri}, error: $e");
      return null;
    }
  }

  Future<void> updateAndCacheDirtyTab(Project project, EditorTab tab) async {
    final hotStateCacheService = _ref.read(hotStateCacheServiceProvider);
    final metadata = _ref.read(tabMetadataProvider)[tab.id];

    if (metadata != null && metadata.isDirty) {
      // MODIFIED: Call the method on the state object via the key.
      final hotStateDto = await tab.editorKey.currentState?.serializeHotState();
      
      if (hotStateDto != null) {
        hotStateCacheService.updateTabState(project.id, tab.id, hotStateDto);
      }
    }
  }

  Future<void> flushAllHotTabs() async {
    final hotStateCacheService = _ref.read(hotStateCacheServiceProvider);
    await hotStateCacheService.flush();
  }

  void markCurrentTabDirty() {
    final tabId = _currentTab?.id;
    if (tabId != null) {
      _ref.read(tabMetadataProvider.notifier).markDirty(tabId);
    }
  }

  void markCurrentTabClean() {
    final tabId = _currentTab?.id;
    if (tabId != null) {
      _ref.read(tabMetadataProvider.notifier).markClean(tabId);
    }
  }

  void updateCurrentTabModel(EditorTab newTabModel) {
    final project = _currentProject;
    if (project == null) return;
    final newTabs = List<EditorTab>.from(project.session.tabs);
    newTabs[project.session.currentTabIndex] = newTabModel;
    final newProject = project.copyWith(
      session: project.session.copyWith(tabs: newTabs),
    );
    _ref.read(appNotifierProvider.notifier).updateCurrentProject(newProject);
  }

  void setBottomToolbarOverride(Widget? widget) {
    _ref.read(appNotifierProvider.notifier).setBottomToolbarOverride(widget);
  }

  void clearBottomToolbarOverride() {
    _ref.read(appNotifierProvider.notifier).clearBottomToolbarOverride();
  }

  Future<void> saveCurrentTabAs({
    Future<Uint8List?> Function()? byteDataProvider,
    Future<String?> Function()? stringDataProvider,
  }) async {
    final repo = _ref.read(projectRepositoryProvider);
    final context = _ref.read(navigatorKeyProvider).currentContext;
    final currentTabId = _currentTab?.id;
    final currentMetadata =
        currentTabId != null
            ? _ref.read(tabMetadataProvider)[currentTabId]
            : null;

    if (repo == null || context == null || currentMetadata == null) return;

    final result = await showDialog<SaveAsDialogResult>(
      context: context,
      builder: (_) => SaveAsDialog(initialFileName: currentMetadata.file.name),
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

    // THIS IS THE FIX: The incorrect line was removed. The event stream
    // is now the single source of truth for hierarchy updates.
    _ref
        .read(fileOperationControllerProvider)
        .add(FileCreateEvent(createdFile: newFile));
    MachineToast.info("Saved as ${newFile.name}");
  }

  void _handlePluginLifecycle(EditorTab? oldTab, EditorTab? newTab) {
    if (oldTab != null) oldTab.plugin.deactivateTab(oldTab, _ref);
    if (newTab != null) newTab.plugin.activateTab(newTab, _ref);
  }
  
  /// Opens a file from a relative path within the current project.
  /// If the file does not exist, it prompts the user to create it.
  /// Returns `true` if a tab was successfully opened or created.
  Future<bool> openOrCreate(String relativePath) async {
    final project = _currentProject;
    if (project == null) {
      MachineToast.error("No project is open.");
      return false;
    }

    final repo = _ref.read(projectRepositoryProvider);
    final appNotifier = _ref.read(appNotifierProvider.notifier);
    final explorerService = _ref.read(explorerServiceProvider);
    final context = _ref.read(navigatorKeyProvider).currentContext;

    if (repo == null || context == null || !context.mounted) {
      return false;
    }

    // Sanitize path to use forward slashes, which our SAF handler expects.
    final sanitizedPath = relativePath.replaceAll(r'\', '/');
    DocumentFile? file =
        await repo.fileHandler.resolvePath(project.rootUri, sanitizedPath);

    if (file != null) {
      // File exists, open it directly.
      return await appNotifier.openFileInEditor(file);
    } else {
      // File does not exist, ask to create it.
      final shouldCreate = await showCreateFileConfirmationDialog(
        context,
        relativePath: sanitizedPath,
      );

      if (shouldCreate) {
        try {
          final newFile = await explorerService.createFileWithHierarchy(project.rootUri, sanitizedPath);
          return await appNotifier.openFileInEditor(newFile);
        } catch (e, st) {
          _ref.read(talkerProvider).handle(e, st, 'Failed to create file at path: $sanitizedPath');
          MachineToast.error("Could not create file: $e");
        }
      }
    }
    return false;
    }

  // REFACTORED: `openFile` now has two distinct logic paths.
  Future<OpenFileResult> openFile(
    Project project,
    DocumentFile file, {
    EditorPlugin? explicitPlugin,
  }) async {
    // Check if tab is already open (this logic remains the same and is first).
    final metadataMap = _ref.read(tabMetadataProvider);
    final existingTabId = metadataMap.entries
        .firstWhereOrNull((entry) => entry.value.file.uri == file.uri)
        ?.key;
    if (existingTabId != null) {
      final existingIndex = project.session.tabs.indexWhere(
        (t) => t.id == existingTabId,
      );
      if (existingIndex != -1) {
        return OpenFileSuccess(
          project: switchTab(project, existingIndex),
          wasAlreadyOpen: true,
        );
      }
    }

    try {
      // --- PATH 1: EXPLICIT PLUGIN (from "Open with...") ---
      if (explicitPlugin != null) {
        String? fileContent;
        Uint8List? fileBytes;

        if (explicitPlugin.dataRequirement == PluginDataRequirement.string) {
          fileContent = await _repo.readFile(file.uri);
          // Perform the content check for this specific plugin.
          if (!explicitPlugin.canOpenFileContent(fileContent, file)) {
            return OpenFileError(
              "${explicitPlugin.name} cannot open this file's content.",
            );
          }
        } else {
          fileBytes = await _repo.readFileAsBytes(file.uri);
        }

        final baseContentHash = (fileContent != null)
            ? md5.convert(utf8.encode(fileContent)).toString()
            : md5.convert(fileBytes!).toString();

        final initData = EditorInitData(
          stringData: fileContent,
          byteData: fileBytes,
          baseContentHash: baseContentHash,
        );

        final newTab = await explicitPlugin.createTab(file, initData);
        return _constructOpenFileSuccess(project, newTab, file);
      }
      // --- PATH 2: DEFAULT PLUGIN DISCOVERY (for single taps) ---
      else {
        final allPlugins = _ref.read(activePluginsProvider);
        final compatiblePlugins =
            allPlugins.where((p) => p.supportsFile(file)).toList();

        if (compatiblePlugins.isEmpty) {
          return OpenFileError("No plugin available to open '${file.name}'.");
        }

        EditorPlugin? chosenPlugin;
        EditorInitData? initData;

        final highestPriorityPlugin = compatiblePlugins.first;
        if (highestPriorityPlugin.dataRequirement == PluginDataRequirement.bytes) {
          chosenPlugin = highestPriorityPlugin;
          final fileBytes = await _repo.readFileAsBytes(file.uri);
          initData = EditorInitData(
            byteData: fileBytes,
            baseContentHash: md5.convert(fileBytes).toString(),
          );
        } else {
          final fileContent = await _repo.readFile(file.uri);
          for (final plugin in compatiblePlugins) {
            if (plugin.dataRequirement == PluginDataRequirement.string &&
                plugin.canOpenFileContent(fileContent, file)) {
              chosenPlugin = plugin;
              break;
            }
          }

          if (chosenPlugin == null) {
            return OpenFileError("Could not determine editor for '${file.name}'.");
          }

          initData = EditorInitData(
            stringData: fileContent,
            baseContentHash: md5.convert(utf8.encode(fileContent)).toString(),
          );
        }

        final newTab = await chosenPlugin.createTab(file, initData);
        return _constructOpenFileSuccess(project, newTab, file);
      }
    } catch (e, st) {
      _ref.read(talkerProvider).handle(e, st, "Could not create tab for: ${file.uri}");
      return OpenFileError("Error opening file '${file.name}'.");
    }
  }

  // NEW: Private helper to reduce code duplication in the success path.
  OpenFileSuccess _constructOpenFileSuccess(
    Project project,
    EditorTab newTab,
    DocumentFile file,
  ) {
    _ref.read(tabMetadataProvider.notifier).initTab(newTab.id, file);

    final oldTab = project.session.currentTab;
    final newSession = project.session.copyWith(
      tabs: [...project.session.tabs, newTab],
      currentTabIndex: project.session.tabs.length,
    );

    _handlePluginLifecycle(oldTab, newTab);

    return OpenFileSuccess(
      project: project.copyWith(session: newSession),
      wasAlreadyOpen: false,
    );
  }
  
  /// Called by EditorWidgetState's initState to resolve a pending future.
  void resolveCompleterForTab(String tabId, EditorWidgetState state) {
    final completer = _widgetCompleters[tabId];
    if (completer != null && !completer.isCompleted) {
      completer.complete(state);
      // The completer is removed in the 'finally' block of the calling function.
    }
  }

  /// Opens a file and, once the editor widget is built and ready,
  /// executes a given function on its state.
  Future<void> openFileAndExecute<T extends EditorWidgetState>({
    required DocumentFile file,
    EditorPlugin? explicitPlugin,
    required FutureOr<void> Function(T editorState) onOpened,
  }) async {
    final project = _currentProject;
    if (project == null) {
      MachineToast.error("No project is open.");
      return;
    }

    final appNotifier = _ref.read(appNotifierProvider.notifier);
    final talker = _ref.read(talkerProvider);
    String? tabIdToWaitFor;

    try {
      // Step 1: Check if the tab is already open.
      final metadataMap = _ref.read(tabMetadataProvider);
      final existingTabEntry = metadataMap.entries.firstWhereOrNull((entry) => entry.value.file.uri == file.uri);
      final existingTab = (existingTabEntry != null) ? project.session.tabs.firstWhereOrNull((t) => t.id == existingTabEntry.key) : null;
      
      if (existingTab != null) {
        // Tab exists, switch to it and check its type.
        final existingIndex = project.session.tabs.indexOf(existingTab);
        appNotifier.switchTab(existingIndex);

        final currentState = existingTab.editorKey.currentState;
        if (currentState != null) {
          // Widget is already built and its state is available.
          if (currentState is T) {
            // Correct type, execute immediately.
            await onOpened(currentState);
            return; // Success, we are done.
          } else {
            // Wrong type, show an error and abort.
            MachineToast.error("Cannot perform action. File is open in a different editor type.");
            return;
          }
        } else {
          // Widget is not built yet (it's in the background). Fall through to wait for it.
          tabIdToWaitFor = existingTab.id;
        }
      } else {
        // Tab does not exist, open it.
        final result = await openFile(project, file, explicitPlugin: explicitPlugin);
        if (result is OpenFileSuccess) {
          appNotifier.updateCurrentProject(result.project);
          tabIdToWaitFor = result.project.session.currentTab?.id;
        } else if (result is OpenFileError) {
          MachineToast.error(result.message);
          return;
        }
      }

      if (tabIdToWaitFor == null) {
        throw Exception("Failed to get a tab ID for the file operation.");
      }

      // Step 2: Create and wait for the completer.
      final completer = Completer<EditorWidgetState>();
      _widgetCompleters[tabIdToWaitFor] = completer;

      talker.info("Waiting for editor widget for tab '$tabIdToWaitFor' to be ready...");

      // Wait for the widget's initState to call `resolveCompleterForTab`.
      // Add a timeout for safety.
      final editorState = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException("Editor widget did not initialize in time."),
      );

      // Step 3: Execute the callback on the resolved widget state after type checking.
      if (editorState is T) {
        await onOpened(editorState);
      } else {
        throw Exception("Opened editor is of type ${editorState.runtimeType}, but expected $T.");
      }
    } catch (e, st) {
      talker.handle(e, st, "Failed during openFileAndExecute for ${file.name}");
      MachineToast.error("Could not perform action on ${file.name}: $e");
    } finally {
      // Step 4: Always clean up the completer from the map.
      if (tabIdToWaitFor != null) {
        _widgetCompleters.remove(tabIdToWaitFor);
      }
    }
  }
  
  /// Applies a specific [TextEdit] to a given [file].
  ///
  /// This service will find the appropriate plugin, open the file if necessary,
  /// verify that the editor supports text editing via the [TextEditable]
  /// interface, and then perform the edit.
  ///
  /// Returns `true` if the edit was successfully applied, `false` otherwise.
  Future<bool> applyTextEdit({
    required DocumentFile file,
    required TextEdit edit,
    EditorPlugin? explicitPlugin,
  }) async {
    bool success = false;
    await openFileAndExecute<EditorWidgetState>(
      file: file,
      explicitPlugin: explicitPlugin,
      onOpened: (editorState) {
        // Check if the opened editor has the text editing capability.
        if (editorState is TextEditable) {
          final editable = editorState as TextEditable;
          
          // Use a switch to apply the correct edit type.
          switch (edit) {
            case ReplaceLinesEdit():
              editable.replaceLines(edit.startLine, edit.endLine, edit.newContent);
              break;
            case ReplaceAllOccurrencesEdit():
              editable.replaceAllOccurrences(edit.find, edit.replace);
              break;
          }
          success = true;
        } else {
          // The opened editor (e.g., an image viewer) does not support this.
          final plugin = _ref.read(activePluginsProvider).firstWhereOrNull(
            (p) => p.supportsFile(file),
          );
          MachineToast.error(
            "Cannot apply text edit. The default editor '${plugin?.name ?? 'Unknown'}' does not support this action.",
          );
          success = false;
        }
      },
    );
    return success;
  }


  // NEW: A reusable method to save a specific tab.
  Future<void> saveTab(Project project, EditorTab tabToSave) async {
    final editorState = tabToSave.editorKey.currentState;
    final metadata = _ref.read(tabMetadataProvider)[tabToSave.id];

    if (editorState == null || metadata == null) {
      return;
    }

    try {
      final editorContent = await editorState.getContent();
      String newHash;

      if (editorContent is EditorContentString) {
        await _repo.writeFile(metadata.file, editorContent.content);
        newHash = md5.convert(utf8.encode(editorContent.content)).toString();
      } else if (editorContent is EditorContentBytes) {
        await _repo.writeFileAsBytes(metadata.file, editorContent.bytes);
        newHash = md5.convert(editorContent.bytes).toString();
      } else {
        throw Exception("Unknown EditorContent type");
      }

      _ref.read(tabMetadataProvider.notifier).markClean(tabToSave.id);
      await _ref
          .read(hotStateCacheServiceProvider)
          .clearTabState(project.id, tabToSave.id);
      editorState.onSaveSuccess(newHash);
    } catch (e, st) {
      _ref.read(talkerProvider).handle(
            e,
            st,
            "Failed to save tab: ${metadata.file.name}",
          );
      MachineToast.error("Failed to save ${metadata.file.name}");
    }
  }

  // NEW: A helper to save multiple tabs, used by the gatekeeper.
  Future<void> saveTabs(Project project, List<EditorTab> tabsToSave) async {
    final futures = tabsToSave.map((tab) => saveTab(project, tab));
    await Future.wait(futures);
  }

  // REFACTORED: saveCurrentTab now uses the new generic saveTab method.
  Future<void> saveCurrentTab() async {
    final project = _currentProject;
    final tab = _currentTab;
    if (project != null && tab != null) {
      await saveTab(project, tab);
    }
  }

  Project switchTab(Project project, int index) {
    final oldTab = project.session.currentTab;
    final newSession = project.session.copyWith(currentTabIndex: index);
    final newProject = project.copyWith(session: newSession);
    final newTab = newProject.session.currentTab;

    _handlePluginLifecycle(oldTab, newTab);
    return newProject;
  }

  Project closeTab(Project project, int index) {
    final closedTab = project.session.tabs[index];
    final oldTab = project.session.currentTab;
    final newTabs = List<EditorTab>.from(project.session.tabs)..removeAt(index);

    int newCurrentIndex;
    if (newTabs.isEmpty) {
      newCurrentIndex = 0;
    } else {
      final oldIndex = project.session.currentTabIndex;
      if (oldIndex > index) {
        newCurrentIndex = oldIndex - 1;
      } else if (oldIndex == index) {
        newCurrentIndex = (oldIndex - 1).clamp(0, newTabs.length - 1);
      } else {
        newCurrentIndex = oldIndex;
      }
    }

    final newProject = project.copyWith(
      session: project.session.copyWith(
        tabs: newTabs,
        currentTabIndex: newCurrentIndex,
      ),
    );

    _ref.read(tabMetadataProvider.notifier).removeTab(closedTab.id);

    _ref
        .read(hotStateCacheServiceProvider)
        .clearTabState(project.id, closedTab.id);

    closedTab.plugin.deactivateTab(closedTab, _ref);
    closedTab.plugin.disposeTab(closedTab);
    closedTab.dispose();

    final newTab = newProject.session.currentTab;
    if (oldTab != newTab) {
      newTab?.plugin.activateTab(newTab, _ref);
    }
    return newProject;
  }

  Project reorderTabs(Project project, int oldIndex, int newIndex) {
    final currentOpenTab = project.session.currentTab;
    final newTabs = List<EditorTab>.from(project.session.tabs);
    final movedTab = newTabs.removeAt(oldIndex);
    if (oldIndex < newIndex) newIndex--;
    newTabs.insert(newIndex, movedTab);
    final newCurrentIndex =
        currentOpenTab != null ? newTabs.indexOf(currentOpenTab) : 0;
    return project.copyWith(
      session: project.session.copyWith(
        tabs: newTabs,
        currentTabIndex: newCurrentIndex,
      ),
    );
  }

  void updateTabForRenamedFile(String oldUri, DocumentFile newFile) {
    final metadataMap = _ref.read(tabMetadataProvider);
    final tabId =
        metadataMap.entries
            .firstWhereOrNull((entry) => entry.value.file.uri == oldUri)
            ?.key;
    if (tabId != null) {
      _ref.read(tabMetadataProvider.notifier).updateFile(tabId, newFile);
    }
  }
}

@immutable
sealed class OpenFileResult {}

class OpenFileSuccess extends OpenFileResult {
  final Project project;
  final bool wasAlreadyOpen;
  OpenFileSuccess({required this.project, required this.wasAlreadyOpen});
}

class OpenFileShowChooser extends OpenFileResult {
  final List<EditorPlugin> plugins;
  OpenFileShowChooser(this.plugins);
}

class OpenFileError extends OpenFileResult {
  final String message;
  OpenFileError(this.message);
}
