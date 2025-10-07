import 'dart:typed_data';
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
import '../tab_state_manager.dart';
import '../../explorer/common/save_as_dialog.dart';
import '../../utils/toast.dart';
import '../../data/dto/project_dto.dart';
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
      talker.info("Tab : ${tabDto.id}, ${tabDto.pluginType}");
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

        talker.info("Trying to load cache");
        final cachedDto = await hotStateCacheService.getTabState(
          projectMetadata.id,
          tabId,
        );

        String? fileContent;
        Uint8List? fileBytes;
        bool wasLoadedFromCache = cachedDto != null;

        if (!wasLoadedFromCache) {
          if (plugin.dataRequirement == PluginDataRequirement.bytes) {
            fileBytes = await _repo.readFileAsBytes(file.uri);
          } else {
            fileContent = await _repo.readFile(file.uri);
          }
        } else {
          await hotStateCacheService.clearTabState(projectMetadata.id, tabId);
        }

        final initData = EditorInitData(
          stringData: fileContent,
          byteData: fileBytes,
          hotState: cachedDto,
        );

        final newTab = await plugin.createTab(file, initData, id: tabId);

        metadataNotifier.initTab(newTab.id, file);
        if (wasLoadedFromCache || persistedMetadata.isDirty) {
          metadataNotifier.markDirty(newTab.id);
        }

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
      final String? fileContent =
          (chosenPlugin.dataRequirement != PluginDataRequirement.bytes)
              ? await _repo.readFile(file.uri)
              : null;
      final Uint8List? fileBytes =
          (chosenPlugin.dataRequirement == PluginDataRequirement.bytes)
              ? await _repo.readFileAsBytes(file.uri)
              : null;

      final initData = EditorInitData(
        stringData: fileContent,
        byteData: fileBytes,
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
      final hotStateDto = await tab.plugin.serializeHotState(tab);
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

  Future<OpenFileResult> openFile(
    Project project,
    DocumentFile file, {
    EditorPlugin? explicitPlugin,
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

    final result = await _createTabForFile(
      file,
      explicitPlugin: explicitPlugin,
    );
    if (result == null) {
      return OpenFileError("No plugin available to open '${file.name}'.");
    }

    final newTab = result.tab;
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

  Future<bool> saveCurrentTab(
    Project project, {
    String? content,
    Uint8List? bytes,
  }) async {
    final tabToSaveId = project.session.currentTab?.id;
    final metadata =
        tabToSaveId != null
            ? _ref.read(tabMetadataProvider)[tabToSaveId]
            : null;
    if (tabToSaveId == null || metadata == null) return false;

    try {
      if (content != null) {
        await _repo.writeFile(metadata.file, content);
      } else if (bytes != null) {
        await _repo.writeFileAsBytes(metadata.file, bytes);
      } else {
        return false;
      }
      _ref.read(tabMetadataProvider.notifier).markClean(tabToSaveId);
      return true;
    } catch (e) {
      _ref.read(talkerProvider).error("Failed to save tab: $e");
      return false;
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
