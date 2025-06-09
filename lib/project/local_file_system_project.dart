// lib/project/local_file_system_project.dart

import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

import '../file_system/file_handler.dart';
import '../plugins/plugin_architecture.dart';
import '../plugins/plugin_registry.dart';
import '../session/session_management.dart';
import 'project_interface.dart';
import 'project_models.dart';

class LocalFileSystemProject implements Project {
  @override
  final ProjectMetadata metadata;
  @override
  SessionState session;
  
  final WidgetRef _ref;
  late final FileHandler _fileHandler;
  late final Set<EditorPlugin> _plugins;

  // From the old `Project` class
  Set<String> expandedFolders;
  FileExplorerViewMode fileExplorerViewMode;

  LocalFileSystemProject({required this.metadata, required WidgetRef ref})
      : _ref = ref,
        session = const SessionState(),
        expandedFolders = {metadata.rootUri},
        fileExplorerViewMode = FileExplorerViewMode.sortByNameAsc {
    _fileHandler = _ref.read(fileHandlerProvider);
    _plugins = _ref.read(activePluginsProvider);
  }

  @override
  String get id => metadata.id;
  @override
  String get name => metadata.name;
  @override
  String get rootUri => metadata.rootUri;
  
  @override
  Future<void> open() async {
    final projectDataFolder = await _fileHandler.ensureProjectDataFolder(rootUri);
    if (projectDataFolder == null) {
      throw Exception('Could not access or create .machine folder for project $name');
    }
    final filesInMachineDir = await _fileHandler.listDirectory(projectDataFolder.uri, includeHidden: true);
    final projectDataFile = filesInMachineDir.firstWhereOrNull((f) => f.name == 'project_data.json');

    if (projectDataFile != null) {
      try {
        final content = await _fileHandler.readFile(projectDataFile.uri);
        final json = jsonDecode(content);
        
        // Deserialize session
        session = SessionState.fromJson(json['sessionData'] ?? {});
        
        // Deserialize other project properties
        expandedFolders = Set<String>.from(json['expandedFolders'] ?? {rootUri});
        fileExplorerViewMode = FileExplorerViewMode.values.firstWhere(
            (e) => e.name == json['fileExplorerViewMode'],
            orElse: () => FileExplorerViewMode.sortByNameAsc);
        
        // Restore tab content
        final List<EditorTab> restoredTabs = [];
        for (final tabJson in (json['sessionData']['tabs'] as List<dynamic>? ?? [])) {
            try {
                final pluginType = tabJson['pluginType'];
                final plugin = _plugins.firstWhere((p) => p.runtimeType.toString() == pluginType);
                final tab = await plugin.createTabFromSerialization(tabJson, _fileHandler);
                restoredTabs.add(tab);
            } catch (e) {
                print('Could not restore tab: $e');
            }
        }
        session = session.copyWith(tabs: restoredTabs);

      } catch (e) {
        print('Error loading project data from file: $e. Using default project state.');
      }
    }
  }

  @override
  Future<void> save() async {
    final projectDataFolder = await _fileHandler.ensureProjectDataFolder(rootUri);
    if (projectDataFolder == null) return;

    final dataToSave = {
      'expandedFolders': expandedFolders.toList(),
      'fileExplorerViewMode': fileExplorerViewMode.name,
      'sessionData': session.toJson(),
    };

    await _fileHandler.createDocumentFile(
      projectDataFolder.uri,
      'project_data.json',
      initialContent: jsonEncode(dataToSave),
      overwrite: true,
    );
  }

  @override
  Future<void> close() async {
    await save();
    for (final tab in session.tabs) {
      tab.dispose();
    }
  }

  @override
  Future<List<DocumentFile>> listDirectory(String uri) {
    return _fileHandler.listDirectory(uri);
  }

  @override
  Future<void> openFileInSession(DocumentFile file) async {
    final existingIndex = session.tabs.indexWhere((t) => t.file.uri == file.uri);
    if (existingIndex != -1) {
      switchTabInSession(existingIndex);
      return;
    }

    try {
      final content = await _fileHandler.readFile(file.uri);
      final plugin = _plugins.firstWhere((p) => p.supportsFile(file), orElse: () => throw Exception('Unsupported file type'));
      final tab = await plugin.createTab(file, content);
      
      session = session.copyWith(
        tabs: [...session.tabs, tab],
        currentTabIndex: session.tabs.length,
      );
    } catch (e) {
        print("Error opening file: $e");
    }
  }
  
  @override
  void switchTabInSession(int tabIndex) {
    if(tabIndex < 0 || tabIndex >= session.tabs.length) return;
    session = session.copyWith(currentTabIndex: tabIndex);
  }

  @override
  void closeTabInSession(int index) {
    if (index < 0 || index >= session.tabs.length) return;
    final newTabs = List<EditorTab>.from(session.tabs)..removeAt(index);
    int newIndex = session.currentTabIndex;
    if (newIndex >= index) {
        newIndex = (newIndex - 1).clamp(0, newTabs.length - 1);
    }
    if (newTabs.isEmpty) newIndex = 0;

    session = session.copyWith(
      tabs: newTabs,
      currentTabIndex: newIndex,
    );
  }

  @override
  Future<void> saveTabInSession(int tabIndex) async {
     if (tabIndex < 0 || tabIndex >= session.tabs.length) return;
     final targetTab = session.tabs[tabIndex];

     try {
       final newFile = await _fileHandler.writeFile(targetTab.file, targetTab.contentString);
       final newTab = targetTab.copyWith(file: newFile, isDirty: false);
       final newTabs = session.tabs.map((t) => t == targetTab ? newTab : t).toList();
       session = session.copyWith(tabs: newTabs);
     } catch (e) {
        print("Save failed: $e");
     }
  }

  @override
  void reorderTabsInSession(int oldIndex, int newIndex) {
    final newTabs = List<EditorTab>.from(session.tabs);
    if (oldIndex < newIndex) newIndex -= 1;
    final movedTab = newTabs.removeAt(oldIndex);
    newTabs.insert(newIndex, movedTab);
    session = session.copyWith(tabs: newTabs);
  }

  @override
  Future<void> renameFile(DocumentFile file, String newName) async {
    final newFile = await _fileHandler.renameDocumentFile(file, newName);
    if (newFile == null) return;

    // Update any open tab with the new file info
    final tabIndex = session.tabs.indexWhere((t) => t.file.uri == file.uri);
    if (tabIndex != -1) {
        final newTabs = List<EditorTab>.from(session.tabs);
        newTabs[tabIndex] = newTabs[tabIndex].copyWith(file: newFile);
        session = session.copyWith(tabs: newTabs);
    }
  }

  @override
  Future<void> deleteFile(DocumentFile file) async {
    // Close tab if open
    final tabIndex = session.tabs.indexWhere((t) => t.file.uri == file.uri);
    if (tabIndex != -1) {
        closeTabInSession(tabIndex);
    }
    await _fileHandler.deleteDocumentFile(file);
  }

  @override
  void updateExplorerViewMode(FileExplorerViewMode mode) {
    fileExplorerViewMode = mode;
    // We need to trigger a state update. The easiest way is to re-assign session
    // This isn't ideal, but works with the current proxy notifier setup.
    // A better way would be for AppState to hold these properties.
    session = session.copyWith();
  }
  
  @override
  void toggleFolderExpansion(String folderUri) {
    if (expandedFolders.contains(folderUri)) {
        expandedFolders.remove(folderUri);
    } else {
        expandedFolders.add(folderUri);
    }
    session = session.copyWith(); // Trigger state update
  }
}