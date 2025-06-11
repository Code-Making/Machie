// lib/project/local_file_system_project.dart
import 'dart:convert'; // NEW
import 'package:flutter_riverpod/flutter_riverpod.dart'; // NEW
import '../data/file_handler/file_handler.dart'; // NEW
import '../plugins/plugin_models.dart'; // NEW
import '../plugins/plugin_registry.dart'; // NEW
import '../session/session_models.dart';
import 'project_models.dart';

// Concrete implementation for projects on the local device file system.
class LocalProject extends Project {
  String projectDataPath;
  Set<String> expandedFolders;
  FileExplorerViewMode fileExplorerViewMode;

  LocalProject({
    required super.metadata,
    required super.fileHandler,
    required super.session,
    required this.projectDataPath,
    this.expandedFolders = const {},
    this.fileExplorerViewMode = FileExplorerViewMode.sortByNameAsc,
  });

  LocalProject copyWith({
    ProjectMetadata? metadata,
    SessionState? session,
    Set<String>? expandedFolders,
    FileExplorerViewMode? fileExplorerViewMode,
  }) {
    return LocalProject(
      metadata: metadata ?? this.metadata,
      fileHandler:
          fileHandler, // File handler is immutable per project instance
      session: session ?? this.session.copyWith(),
      projectDataPath: projectDataPath,
      expandedFolders: expandedFolders ?? Set.from(this.expandedFolders),
      fileExplorerViewMode: fileExplorerViewMode ?? this.fileExplorerViewMode,
    );
  }

  // --- NEW: Project-specific logic (not on abstract class) ---
  LocalProject toggleFolderExpansion(String folderUri) {
    final newExpanded = Set<String>.from(expandedFolders);
    if (newExpanded.contains(folderUri)) {
      newExpanded.remove(folderUri);
    } else {
      newExpanded.add(folderUri);
    }
    return copyWith(expandedFolders: newExpanded);
  }

  // --- NEW: Lifecycle Implementations ---

  @override
  Future<void> save() async {
    final content = jsonEncode(toJson());
    await fileHandler.createDocumentFile(
      projectDataPath,
      'project_data.json',
      initialContent: content,
      overwrite: true,
    );
  }

  @override
  Future<void> close() async {
    await save();
    for (final tab in session.tabs) {
      tab.plugin.deactivateTab(tab, ProviderScope.containerOf(GlobalKey().currentContext!));
      tab.dispose();
    }
  }

  // --- NEW: Session Logic Implementations (from the old SessionService) ---

  void _handlePluginLifecycle(EditorTab? oldTab, EditorTab? newTab, Ref ref) {
    if (oldTab != null) oldTab.plugin.deactivateTab(oldTab, ref);
    if (newTab != null) newTab.plugin.activateTab(newTab, ref);
  }

  @override
  Future<Project> openFile(DocumentFile file, {EditorPlugin? plugin, required Ref ref}) async {
    final existingIndex = session.tabs.indexWhere(
      (t) => t.file.uri == file.uri,
    );
    if (existingIndex != -1) {
      return switchTab(existingIndex, ref: ref);
    }

    final plugins = ref.read(activePluginsProvider);
    final selectedPlugin = plugin ?? plugins.firstWhere((p) => p.supportsFile(file));
    final content = await fileHandler.readFile(file.uri);
    final newTab = await selectedPlugin.createTab(file, content);

    final oldTab = session.currentTab;
    final newSession = session.copyWith(
      tabs: [...session.tabs, newTab],
      currentTabIndex: session.tabs.length,
    );
    _handlePluginLifecycle(oldTab, newTab, ref);

    return copyWith(session: newSession);
  }

  @override
  Project switchTab(int index, {required Ref ref}) {
    final oldTab = session.currentTab;
    final newSession = session.copyWith(currentTabIndex: index);
    final newProject = copyWith(session: newSession);
    final newTab = newProject.session.currentTab;

    _handlePluginLifecycle(oldTab, newTab, ref);
    return newProject;
  }

  @override
  Project reorderTabs(int oldIndex, int newIndex) {
    final currentOpenTab = session.currentTab;
    final newTabs = List<EditorTab>.from(session.tabs);
    final movedTab = newTabs.removeAt(oldIndex);

    if (oldIndex < newIndex) newIndex--;
    newTabs.insert(newIndex, movedTab);

    final newCurrentIndex =
        currentOpenTab != null ? newTabs.indexOf(currentOpenTab) : 0;

    return copyWith(
      session: session.copyWith(
        tabs: newTabs,
        currentTabIndex: newCurrentIndex,
      ),
    );
  }

  @override
  Future<Project> saveTab(int tabIndex) async {
    if (tabIndex < 0 || tabIndex >= session.tabs.length) return this;

    final tabToSave = session.tabs[tabIndex];
    final newFile = await fileHandler.writeFile(
      tabToSave.file,
      tabToSave.contentString,
    );
    final newTab = tabToSave.copyWith(file: newFile, isDirty: false);

    return updateTab(tabIndex, newTab);
  }

  @override
  Project closeTab(int index, {required Ref ref}) {
    if (index < 0 || index >= session.tabs.length) {
      return this;
    }

    final closedTab = session.tabs[index];
    final oldTab = session.currentTab;
    final newTabs = List<EditorTab>.from(session.tabs)..removeAt(index);

    int newCurrentIndex;
    if (newTabs.isEmpty) {
      newCurrentIndex = 0; // No tabs left, reset index.
    } else {
      final oldIndex = session.currentTabIndex;
      if (oldIndex > index) {
        newCurrentIndex = oldIndex - 1;
      } else if (oldIndex == index) {
        newCurrentIndex = (oldIndex - 1).clamp(0, newTabs.length - 1);
      } else {
        newCurrentIndex = oldIndex;
      }
    }

    final newProject = copyWith(
      session: session.copyWith(
        tabs: newTabs,
        currentTabIndex: newCurrentIndex,
      ),
    );

    closedTab.plugin.deactivateTab(closedTab, ref);
    closedTab.dispose();

    final newTab = newProject.session.currentTab;
    if (oldTab != newTab) {
      newTab?.plugin.activateTab(newTab, ref);
    }

    return newProject;
  }

  @override
  Project markCurrentTabDirty() {
    final currentTab = session.currentTab;
    if (currentTab == null || currentTab.isDirty) return this;

    final newTab = currentTab.copyWith(isDirty: true);
    return updateTab(session.currentTabIndex, newTab);
  }

  @override
  Project updateTab(int tabIndex, EditorTab newTab) {
    if (tabIndex < 0 || tabIndex >= session.tabs.length) return this;

    final newTabs = List<EditorTab>.from(session.tabs);
    newTabs[tabIndex] = newTab;

    return copyWith(session: session.copyWith(tabs: newTabs));
  }

  // Serialization for .machine/project_data.json
  Map<String, dynamic> toJson() => {
    'id': metadata.id, // For verification
    'session': session.toJson(),
    'expandedFolders': expandedFolders.toList(),
    'fileExplorerViewMode': fileExplorerViewMode.name,
  };
}