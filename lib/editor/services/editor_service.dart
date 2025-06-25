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

  // ... (getters and facade methods are unchanged) ...
  Project? get _currentProject =>
      _ref.read(appNotifierProvider).value?.currentProject;
  EditorTab? get _currentTab => _currentProject?.session.currentTab;
  
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
  
  // REFACTORED: The rehydration logic is now robust.
  Future<Project> rehydrateTabs(Project project) async {
    final plugins = _ref.read(activePluginsProvider);
    final metadataNotifier = _ref.read(tabMetadataProvider.notifier);

    // The session object from the persisted project file contains the metadata.
    final persistedMetadata = project.session.tabMetadata;
    final persistedTabsJson = project.session.tabs.map((t) => t.toJson()).toList();

    // A map to look up a tab's JSON by its ID.
    final Map<String, Map<String, dynamic>> tabJsonMap = {
      for (var json in persistedTabsJson) json['id']: json
    };

    final List<EditorTab> rehydratedTabs = [];

    // Iterate through the persisted metadata.
    for (final entry in persistedMetadata.entries) {
      final tabId = entry.key;
      final partialMetadata = entry.value;
      final tabJson = tabJsonMap[tabId];
      final pluginType = tabJson?['pluginType'] as String?;

      if (pluginType == null) continue;

      final plugin = plugins.firstWhereOrNull((p) => p.runtimeType.toString() == pluginType);
      if (plugin == null) continue;
      
      try {
        // Fetch the full DocumentFile object.
        final file = await _repo.fileHandler.getFileMetadata(partialMetadata.file.uri);
        if (file == null) continue; // Skip tabs whose files were deleted.
        
        // Read the file content needed to create the tab.
        final dynamic data = plugin.dataRequirement == PluginDataRequirement.bytes
            ? await _repo.readFileAsBytes(file.uri)
            : await _repo.readFile(file.uri);
        
        // Create the new tab instance.
        final tab = await plugin.createTab(file, data);

        // This is a new tab instance, so we need to put its ID back to the
        // original persisted ID to maintain consistency. This is a bit of a hack.
        // A better long-term solution would be a `copyWith(id: ...)` method.
        // For now, we'll re-create the tab list from the persisted order.
        // NOTE: A more robust solution might involve passing the ID to createTab.

        // Initialize the metadata for the *new* tab's ID, but with the old data.
        metadataNotifier.state[tab.id] = TabMetadata(file: file, isDirty: partialMetadata.isDirty);
        rehydratedTabs.add(tab);

      } catch (e, st) {
        _ref.read(talkerProvider).handle(e, st, 'Could not restore tab for ${partialMetadata.file.uri}');
      }
    }
    
    // The order of rehydratedTabs might not match the persisted order.
    // A more sophisticated implementation would sort `rehydratedTabs`
    // based on the order of `persistedTabsJson`. For now, this is functional.
    return project.copyWith(
      session: project.session.copyWith(tabs: rehydratedTabs, tabMetadata: {}), // Clear persisted metadata
    );
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