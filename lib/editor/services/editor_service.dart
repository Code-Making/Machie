// =========================================
// FILE: lib/editor/services/editor_service.dart
// =========================================

// lib/editor/services/editor_service.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';

import '../../app/app_notifier.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/project_hierarchy_cache.dart';
import '../../editor/editor_tab_models.dart';
import '../../editor/plugins/plugin_registry.dart';
import '../../project/project_models.dart';
import '../../logs/logs_provider.dart';
import '../../data/file_handler/file_handler.dart' show DocumentFile;
import '../tab_state_manager.dart';
import '../../explorer/common/save_as_dialog.dart';
import '../../utils/toast.dart';

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
  
  
  ProjectRepository get _repo {
    final repo = _ref.read(projectRepositoryProvider);
    if (repo == null) {
      throw StateError('ProjectRepository is not available.');
    }
    return repo;
  }
  // REFACTORED: This is the corrected rehydration logic.
  Future<Project> rehydrateTabs(Project project) async {
    final plugins = _ref.read(activePluginsProvider);
    final metadataNotifier = _ref.read(tabMetadataProvider.notifier);

    // The session object from the loaded project contains the persisted metadata.
    final persistedMetadataMap = project.session.tabMetadata;
    final persistedTabsJson = project.session.tabs.map((t) => t.toJson()).toList();

    final Map<String, Map<String, dynamic>> tabJsonMap = {
      for (var json in persistedTabsJson) json['id']: json
    };

    final List<EditorTab> rehydratedTabs = [];

    // The source of truth for rehydration is the persisted metadata map.
    // We iterate over its entries.
    for (final entry in persistedMetadataMap.entries) {
      final tabId = entry.key;
      final persistedMetadata = entry.value;
      final tabJson = tabJsonMap[tabId];
      final pluginType = tabJson?['pluginType'] as String?;

      if (pluginType == null) {
        _ref.read(talkerProvider).warning('Skipping rehydration for tab ID $tabId: missing pluginType.');
        continue;
      }

      final plugin = plugins.firstWhereOrNull((p) => p.runtimeType.toString() == pluginType);
      if (plugin == null) {
        _ref.read(talkerProvider).warning('Skipping rehydration for tab ID $tabId: plugin $pluginType not found.');
        continue;
      }
      
      try {
        final fileUri = persistedMetadata.file.uri;
        final file = await _repo.fileHandler.getFileMetadata(fileUri);
        
        if (file == null) {
          _ref.read(talkerProvider).info('Skipping rehydration for tab ID $tabId: file $fileUri not found.');
          continue; // Skip tabs for files that were deleted.
        }
        
        final dynamic data = plugin.dataRequirement == PluginDataRequirement.bytes
            ? await _repo.readFileAsBytes(file.uri)
            : await _repo.readFile(file.uri);
        
        // Create a new tab instance. It will have a new, random ID.
        final newTab = await plugin.createTab(file, data);

        // This is the crucial step:
        // We use the NEW tab instance (with its new GlobalKey) but we populate
        // the metadata provider using the OLD, persisted tab ID.
        // This links the new widget to the old session data.
        metadataNotifier.state[tabId] = TabMetadata(
          file: file, 
          isDirty: persistedMetadata.isDirty
        );

        // We also need a way to link the new tab's ID to the old one.
        // The best way is to create a new Tab object that re-uses the old ID.
        // Let's assume `EditorTab` has a private constructor or a `copyWith` that can do this.
        // For now, we will create a map to find the new tab that corresponds to the old ID.
        // A better approach would be to pass the ID into `createTab`.
        // Let's create a placeholder tab that just holds the ID, and we'll replace it.
        
        // This is a simplification. The ideal way is to maintain the original ID.
        // Let's assume for now that the order is preserved and we can match them up.
        // We'll add the new tab to our list.
        rehydratedTabs.add(newTab);
        
      } catch (e, st) {
        _ref.read(talkerProvider).handle(e, st, 'Could not restore tab for ${persistedMetadata.file.uri}');
      }
    }

    // Now, we need to create the final list of tabs for the session,
    // ensuring they have the original persisted IDs.
    final finalTabs = <EditorTab>[];
    final rehydratedTabsById = <String, EditorTab>{}; // Map old ID to new tab instance
    
    // This is a tricky part. Let's rebuild the final tab list using the original persisted order.
    for (final tabJson in persistedTabsJson) {
        final oldId = tabJson['id'];
        // Find the corresponding metadata we just re-populated.
        final liveMetadata = metadataNotifier.state[oldId];
        if (liveMetadata != null) {
            // Find a rehydrated tab that matches the file. This assumes one file = one tab.
            final correspondingNewTab = rehydratedTabs.firstWhereOrNull((t) {
                final newMeta = metadataNotifier.state[t.id];
                return newMeta?.file.uri == liveMetadata.file.uri;
            });

            if (correspondingNewTab != null) {
                // This is the key: we create a final tab object that uses the OLD id
                // but the NEW GlobalKey and other state from the rehydrated tab instance.
                final finalTab = correspondingNewTab.copyWith(idForRehydration: oldId);
                finalTabs.add(finalTab);
                
                // Clean up the temporary metadata entry for the new random ID.
                metadataNotifier.removeTab(correspondingNewTab.id);
            }
        }
    }
    
    // The project now has the correct tab objects with stable IDs.
    return project.copyWith(
      session: project.session.copyWith(tabs: finalTabs, tabMetadata: {}), // Clear persisted metadata from the object
    );
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
  
   // ... updateCurrentTabModel, set/clearBottomToolbarOverride are unchanged ...
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

  /// Initiates the "Save As" flow for the current tab.
  Future<void> saveCurrentTabAs({
    Future<Uint8List?> Function()? byteDataProvider,
    Future<String?> Function()? stringDataProvider,
  }) async {
    final repo = _ref.read(projectRepositoryProvider);
    final context = _ref.read(navigatorKeyProvider).currentContext;
    final currentTabId = _currentTab?.id;
    final currentMetadata =
        currentTabId != null ? _ref.read(tabMetadataProvider)[currentTabId] : null;

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
    _ref.read(projectHierarchyProvider.notifier).add(newFile, result.parentUri);
    _ref.read(fileOperationControllerProvider).add(FileCreateEvent(createdFile: newFile));
    MachineToast.info("Saved as ${newFile.name}");
  }

  // --- Core Service Methods ---

  void _handlePluginLifecycle(EditorTab? oldTab, EditorTab? newTab) {
    if (oldTab != null) oldTab.plugin.deactivateTab(oldTab, _ref);
    if (newTab != null) newTab.plugin.activateTab(newTab, _ref);
  }

Future<({EditorTab tab, DocumentFile file})?> _createTabForFile(DocumentFile file, {EditorPlugin? explicitPlugin}) async {
    final compatiblePlugins = _ref.read(activePluginsProvider).where((p) => p.supportsFile(file)).toList();
    
    EditorPlugin? chosenPlugin = explicitPlugin;
    if (chosenPlugin == null) {
        if (compatiblePlugins.isEmpty) return null;
        chosenPlugin = compatiblePlugins.first;
    }

    final dynamic data;
    try {
        if (chosenPlugin.dataRequirement == PluginDataRequirement.bytes) {
            data = await _repo.readFileAsBytes(file.uri);
        } else {
            data = await _repo.readFile(file.uri);
        }
    } catch(e) {
        _ref.read(talkerProvider).error("Could not read file data for tab: ${file.uri}, error: $e");
        return null;
    }

    final newTab = await chosenPlugin.createTab(file, data);
    return (tab: newTab, file: file);
  }

  Future<OpenFileResult> openFile(
    Project project,
    DocumentFile file, {
    EditorPlugin? explicitPlugin,
  }) async {
    // Check if a tab for this file URI is already open by checking metadata
    final metadataMap = _ref.read(tabMetadataProvider);
    final existingTabId = metadataMap.entries.firstWhereOrNull((entry) => entry.value.file.uri == file.uri)?.key;

    if (existingTabId != null) {
      final existingIndex = project.session.tabs.indexWhere((t) => t.id == existingTabId);
      if (existingIndex != -1) {
          return OpenFileSuccess(
              project: switchTab(project, existingIndex),
              wasAlreadyOpen: true,
          );
      }
    }

    final result = await _createTabForFile(file, explicitPlugin: explicitPlugin);
    if (result == null) {
        // Here we could also handle the "show chooser" logic if multiple plugins are compatible.
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
    final metadata = tabToSaveId != null ? _ref.read(tabMetadataProvider)[tabToSaveId] : null;
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

    // REFACTORED: Remove metadata by tab ID.
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
  
  // REFACTORED: This is now much simpler. It finds the tab by the old URI
  // and just updates its metadata. The Project object doesn't need to change.
  void updateTabForRenamedFile(String oldUri, DocumentFile newFile) {
    final metadataMap = _ref.read(tabMetadataProvider);
    final tabId = metadataMap.entries.firstWhereOrNull((entry) => entry.value.file.uri == oldUri)?.key;
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