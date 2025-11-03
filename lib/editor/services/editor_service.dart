import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_notifier.dart';
import '../../data/cache/hot_state_cache_service.dart';
import '../../data/dto/project_dto.dart';
import '../../data/repositories/project_repository.dart';
import '../../explorer/common/file_explorer_dialogs.dart';
import '../../explorer/common/save_as_dialog.dart';
import '../../explorer/services/explorer_service.dart';
import '../../logs/logs_provider.dart';
import '../../project/project_models.dart';
import '../../utils/toast.dart';
import '../editor_tab_models.dart';
import '../plugins/plugin_registry.dart';
import '../tab_state_manager.dart';
import 'file_content_provider.dart';
import 'text_editing_capability.dart';

import '../../data/file_handler/file_handler.dart'
    show DocumentFile, ProjectDocumentFile;

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

  FileContentProviderRegistry get _contentProviderRegistry =>
      _ref.read(fileContentProviderRegistryProvider);

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
      final tabId = tabDto.id;
      final pluginId = tabDto.pluginType;
      final persistedMetadata = dto.session.tabMetadata[tabId];

      if (persistedMetadata == null) continue;

      final plugin = plugins.firstWhereOrNull((p) => p.id == pluginId);
      if (plugin == null) continue;

      try {
        final file = await _contentProviderRegistry.rehydrateFileFromDto(
          persistedMetadata,
        );

        if (file == null) continue;

        final contentProvider = _contentProviderRegistry.getProviderFor(file);

        final currentContentResult = await contentProvider.getContent(
          file,
          plugin.dataRequirement,
        );
        final currentDiskHash = currentContentResult.baseContentHash;

        TabHotStateDto? cachedDto = await hotStateCacheService.getTabState(
          projectMetadata.id,
          tabId,
        );

        if (cachedDto != null && cachedDto.baseContentHash != currentDiskHash) {
          talker.warning(
            'Cache conflict detected for ${file.name}. '
            'Cached Hash: ${cachedDto.baseContentHash}, '
            'Disk Hash: $currentDiskHash',
          );
          final context = _ref.read(navigatorKeyProvider).currentContext;
          if (context != null) {
            final resolution = await showCacheConflictDialog(
              context,
              fileName: file.name,
            );
            if (resolution == CacheConflictResolution.loadDisk) {
              talker.info('User chose to discard cache for ${file.name}.');
              await hotStateCacheService.clearTabState(
                projectMetadata.id,
                tabId,
              );
              cachedDto = null;
            }
          }
        }

        final initData = EditorInitData(
          initialContent: currentContentResult.content,
          hotState: cachedDto,
          baseContentHash: currentDiskHash,
        );

        final newTab = await plugin.createTab(file, initData, id: tabId);

        metadataNotifier.initTab(newTab.id, file);
        rehydratedTabs.add(newTab);
      } catch (e, st) {
        _ref
            .read(talkerProvider)
            .handle(
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

  Future<void> updateAndCacheDirtyTab(Project project, EditorTab tab) async {
    final hotStateCacheService = _ref.read(hotStateCacheServiceProvider);
    final metadata = _ref.read(tabMetadataProvider)[tab.id];

    if (metadata != null && metadata.isDirty) {
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

  Future<void> saveCurrentTabAs() async {
    final project = _currentProject;
    final tab = _currentTab;
    if (project == null || tab == null) return;

    final editorState = tab.editorKey.currentState;
    final metadata = _ref.read(tabMetadataProvider)[tab.id];
    if (editorState == null || metadata == null) return;

    final context = _ref.read(navigatorKeyProvider).currentContext;
    if (context == null || !context.mounted) return;

    try {
      final editorContent = await editorState.getContent();
      final result = await showDialog<SaveAsDialogResult>(
        context: context,
        builder: (_) => SaveAsDialog(initialFileName: metadata.file.name),
      );
      if (result == null) return;

      final ProjectDocumentFile newFile =
          (editorContent is EditorContentString)
              ? await _repo.createDocumentFile(
                result.parentUri,
                result.fileName,
                initialContent: editorContent.content,
                overwrite: true,
              )
              : await _repo.createDocumentFile(
                result.parentUri,
                result.fileName,
                initialBytes: (editorContent as EditorContentBytes).bytes,
                overwrite: true,
              );

      final newHash =
          (editorContent is EditorContentString)
              ? md5.convert(utf8.encode(editorContent.content)).toString()
              : md5
                  .convert((editorContent as EditorContentBytes).bytes)
                  .toString();

      _ref.read(tabMetadataProvider.notifier).updateFile(tab.id, newFile);
      _ref.read(tabMetadataProvider.notifier).markClean(tab.id);

      await _ref
          .read(hotStateCacheServiceProvider)
          .clearTabState(project.id, tab.id);
      editorState.onSaveSuccess(newHash);

      _ref
          .read(fileOperationControllerProvider)
          .add(FileCreateEvent(createdFile: newFile));
      MachineToast.info("Saved as ${newFile.name}");
    } catch (e, st) {
      _ref.read(talkerProvider).handle(e, st, 'Save As operation failed');
      MachineToast.error("Save As operation failed.");
    }
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
    DocumentFile? file = await repo.fileHandler.resolvePath(
      project.rootUri,
      sanitizedPath,
    );

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
          final newFile = await explorerService.createFileWithHierarchy(
            project.rootUri,
            sanitizedPath,
          );
          return await appNotifier.openFileInEditor(newFile);
        } catch (e, st) {
          _ref
              .read(talkerProvider)
              .handle(e, st, 'Failed to create file at path: $sanitizedPath');
          MachineToast.error("Could not create file: $e");
        }
      }
    }
    return false;
  }

  /// Opens a file if not already open, switches to its tab, and applies a generic [TextEdit].
  Future<bool> openAndApplyEdit(String relativePath, TextEdit edit) async {
    final project = _currentProject;
    if (project == null) {
      MachineToast.error("No project is open.");
      return false;
    }

    // Sanitize path just in case
    final sanitizedPath = relativePath.replaceAll(r'\', '/');
    final file = await _repo.fileHandler.resolvePath(
      project.rootUri,
      sanitizedPath,
    );

    if (file == null) {
      MachineToast.error("File not found: $sanitizedPath");
      return false;
    }

    final appNotifier = _ref.read(appNotifierProvider.notifier);
    final metadataMap = _ref.read(tabMetadataProvider);
    final existingTabId =
        metadataMap.entries
            .firstWhereOrNull((entry) => entry.value.file.uri == file.uri)
            ?.key;
    EditorTab? tabToEdit = (project.session.tabs).firstWhereOrNull(
      (t) => t.id == existingTabId,
    );

    try {
      final EditorWidgetState editorState;
      if (tabToEdit == null) {
        final onReadyCompleter = Completer<EditorWidgetState>();
        if (!await appNotifier.openFileInEditor(
          file,
          onReadyCompleter: onReadyCompleter,
        )) {
          return false;
        }
        editorState = await onReadyCompleter.future;
      } else {
        final index = project.session.tabs.indexOf(tabToEdit);
        appNotifier.switchTab(index);
        editorState = await tabToEdit.onReady.future;
      }

      // The service simply tells the editor to apply the edit.
      // It doesn't need to know what kind of edit it is.
      if (editorState is TextEditable) {
        (editorState as TextEditable).applyEdit(edit); // <-- UNIFIED CALL
        return true;
      } else {
        throw TypeError();
      }
    } catch (e, st) {
      final errorMessage =
          e is TypeError
              ? "The editor for this file does not support programmatic edits."
              : "Failed to apply edit: $e";
      _ref.read(talkerProvider).handle(e, st, 'Error in openAndApplyEdit');
      MachineToast.error(errorMessage);
      return false;
    }
  }

  Future<OpenFileResult> openFile(
    Project project,
    DocumentFile file, {
    EditorPlugin? explicitPlugin,
    Completer<EditorWidgetState>? onReadyCompleter,
  }) async {
    final metadataMap = _ref.read(tabMetadataProvider);
    final existingTabId =
        metadataMap.entries
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
      // Step 1: Pick plugin candidates
      final EditorPlugin chosenPlugin;
      if (explicitPlugin != null) {
        // Use explicit plugin directly without supportsFile check since it's an override
        chosenPlugin = explicitPlugin;
      } else {
        final allPlugins = _ref.read(activePluginsProvider);
        final compatiblePlugins =
            allPlugins.where((p) => p.supportsFile(file)).toList();
        if (compatiblePlugins.isEmpty) {
          return OpenFileError("No plugin available to open '${file.name}'.");
        }

        if (compatiblePlugins.length == 1) {
          chosenPlugin = compatiblePlugins.first;
        } else {
          // For multiple compatible plugins, find the best match
          final contentProvider = _contentProviderRegistry.getProviderFor(file);
          final contentResult = await contentProvider.getContent(
            file,
            PluginDataRequirement.string,
          );
          final fileContent =
              (contentResult.content as EditorContentString).content;

          final contentMatchingPlugins =
              compatiblePlugins
                  .where(
                    (p) =>
                        p.dataRequirement == PluginDataRequirement.string &&
                        p.canOpenFileContent(fileContent, file),
                  )
                  .toList();

          if (contentMatchingPlugins.isEmpty) {
            chosenPlugin = compatiblePlugins.first;
          } else if (contentMatchingPlugins.length == 1) {
            chosenPlugin = contentMatchingPlugins.first;
          } else {
            return OpenFileShowChooser(contentMatchingPlugins);
          }
        }
      }

      // Step 2: Open content
      final contentProvider = _contentProviderRegistry.getProviderFor(file);
      final contentResult = await contentProvider.getContent(
        file,
        chosenPlugin.dataRequirement,
      );

      // Step 3: Run content check (for string-based plugins)
      if (chosenPlugin.dataRequirement == PluginDataRequirement.string) {
        final fileContent =
            (contentResult.content as EditorContentString).content;
        if (!chosenPlugin.canOpenFileContent(fileContent, file)) {
          return OpenFileError(
            "${chosenPlugin.name} cannot open this file's content.",
          );
        }
      }

      // Step 4: Send content to selected plugin
      final initData = EditorInitData(
        initialContent: contentResult.content,
        baseContentHash: contentResult.baseContentHash,
      );
      final newTab = await chosenPlugin.createTab(
        file,
        initData,
        onReadyCompleter: onReadyCompleter,
      );
      return _constructOpenFileSuccess(project, newTab, file);
    } catch (e, st) {
      _ref
          .read(talkerProvider)
          .handle(e, st, "Could not create tab for: ${file.uri}");
      return OpenFileError("Error opening file '${file.name}'.");
    }
  }

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

  Future<void> saveTab(Project project, EditorTab tabToSave) async {
    final editorState = tabToSave.editorKey.currentState;
    final metadata = _ref.read(tabMetadataProvider)[tabToSave.id];
    if (editorState == null || metadata == null) return;

    final file = metadata.file;
    final contentProvider = _contentProviderRegistry.getProviderFor(file);

    try {
      final editorContent = await editorState.getContent();
      final saveResult = await contentProvider.saveContent(file, editorContent);
      _ref.read(tabMetadataProvider.notifier).markClean(tabToSave.id);
      await _ref
          .read(hotStateCacheServiceProvider)
          .clearTabState(project.id, tabToSave.id);
      editorState.onSaveSuccess(saveResult.newContentHash);
      if (saveResult.savedFile.uri != file.uri) {
        _ref
            .read(tabMetadataProvider.notifier)
            .updateFile(tabToSave.id, saveResult.savedFile);
      }
    } on RequiresSaveAsException {
      await saveCurrentTabAs();
    } catch (e, st) {
      _ref
          .read(talkerProvider)
          .handle(e, st, "Failed to save tab: ${metadata.file.name}");
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
