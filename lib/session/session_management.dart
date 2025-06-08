// =========================================
// FILE: lib/session/session_management.dart
// =========================================

import 'dart:convert';
import 'dart:math'; // For max()

import 'package:collection/collection.dart'; // For DeepCollectionEquality
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart'; // For CodeLineEditingController, CodeCommentFormatter, CodeLinePosition

import '../file_system/file_handler.dart'; // For DocumentFile, FileHandler
import '../main.dart'; // For sharedPreferencesProvider, printStream
import '../plugins/plugin_architecture.dart'; // For EditorPlugin, activePluginsProvider
import '../plugins/plugin_registry.dart'; // For EditorPlugin, activePluginsProvider
import '../project/project_models.dart'; // NEW: Import ProjectMetadata, Project, FileExplorerViewMode
import '../screens/settings_screen.dart'; // For LogNotifier
import '../widgets/file_explorer_drawer.dart'; // NEW: Import for rootUriProvider

import 'package:uuid/uuid.dart'; // Add to pubspec.yaml if not already
import 'package:shared_preferences/shared_preferences.dart'; // For SharedPreferences

// --------------------
// Session Management Providers
// --------------------

final sessionManagerProvider = Provider<SessionManager>((ref) {
  return SessionManager(
    fileHandler: ref.watch(fileHandlerProvider),
    plugins: ref.watch(activePluginsProvider),
    prefs: ref.watch(sharedPreferencesProvider).requireValue,
  );
});

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(
  SessionNotifier.new,
);

// --------------------
//  Lifecycle Handler
// --------------------
class LifecycleHandler extends StatefulWidget {
  final Widget child;
  const LifecycleHandler({super.key, required this.child});
  @override
  State<LifecycleHandler> createState() => _LifecycleHandlerState();
}

class _LifecycleHandlerState extends State<LifecycleHandler> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final container = ProviderScope.containerOf(context);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        await container.read(sessionProvider.notifier).saveSession();
        break;
      case AppLifecycleState.resumed:
        // On resume, ensure root URI is persisted for the current project
        final currentProject = container.read(sessionProvider).currentProject; // NEW: Access currentProject
        if (currentProject != null) {
          await container
              .read(fileHandlerProvider)
              .persistRootUri(currentProject.rootUri); // MODIFIED: Persist rootUri of currentProject
        }
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
// --------------------
//      Session State
// --------------------
@immutable
class SessionState {
  final List<EditorTab> tabs;
  final int currentTabIndex;
  final Project? currentProject; // MODIFIED: Use Project instead of DocumentFile
  final List<ProjectMetadata> knownProjects; // NEW: List of all known projects
  final DateTime? lastSaved;

  const SessionState({
    this.tabs = const [],
    this.currentTabIndex = 0,
    this.currentProject,
    this.knownProjects = const [], // Initialize
    this.lastSaved,
  });

  EditorTab? get currentTab => tabs.isNotEmpty ? tabs[currentTabIndex] : null;

  SessionState copyWith({
    List<EditorTab>? tabs,
    int? currentTabIndex,
    Project? currentProject, // MODIFIED
    List<ProjectMetadata>? knownProjects, // NEW
    DateTime? lastSaved,
  }) {
    return SessionState(
      tabs: tabs ?? this.tabs,
      currentTabIndex: currentTabIndex ?? this.currentTabIndex,
      currentProject: currentProject ?? this.currentProject,
      knownProjects: knownProjects ?? this.knownProjects, // NEW
      lastSaved: lastSaved ?? this.lastSaved,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionState &&
          currentTabIndex == other.currentTabIndex &&
          const DeepCollectionEquality().equals(tabs, other.tabs) &&
          currentProject?.id == other.currentProject?.id; // MODIFIED: Compare by Project ID

  @override
  int get hashCode => Object.hash(
    currentTabIndex,
    const DeepCollectionEquality().hash(tabs),
    currentProject?.id, // MODIFIED
  );

  Map<String, dynamic> toJson() {
    // Only persist currentProject's metadata and knownProjects
    final currentProjectMetadata = currentProject != null
        ? currentProject!.toMetadata() // Convert Project to ProjectMetadata for global persistence
        : null;

    final updatedKnownProjects = List<ProjectMetadata>.from(knownProjects);
    if (currentProjectMetadata != null) {
      final existingIndex = updatedKnownProjects.indexWhere((p) => p.id == currentProjectMetadata.id);
      if (existingIndex != -1) {
        updatedKnownProjects[existingIndex] = currentProjectMetadata; // Update existing
      } else {
        updatedKnownProjects.add(currentProjectMetadata); // Add new
      }
    }

    return {
      'lastOpenedProjectId': currentProject?.id, // NEW: Persist ID of last opened project
      'knownProjects': updatedKnownProjects.map((p) => p.toJson()).toList(), // NEW: Persist list of known projects
      // Tabs are no longer directly persisted in global session state,
      // but managed within the Project's sessionData.
    };
  }

  static Future<SessionState> fromJson(
    Map<String, dynamic> json,
    Set<EditorPlugin> plugins,
    FileHandler fileHandler,
  ) async {
    // Deserialize known projects
    final knownProjectsJson = json['knownProjects'] as List<dynamic>? ?? [];
    final knownProjects = knownProjectsJson.map((p) => ProjectMetadata.fromJson(p)).toList();

    return SessionState(
      tabs: [], // Tabs are loaded with the specific project
      currentTabIndex: 0, // Reset to 0 when loading a project
      currentProject: null, // Project will be loaded by SessionNotifier later
      knownProjects: knownProjects,
    );
  }
}

// NEW: Extension to convert Project to ProjectMetadata
extension ProjectToMetadata on Project {
  ProjectMetadata toMetadata({int? lastOpenedTabIndex, String? lastOpenedFileUri}) {
    // Find the current tab's info to store in metadata
    int? currentTabIndexToStore;
    String? currentFileUriToStore;

    // This extension needs context of the current session state.
    // However, for serialization, it's safer to pass this explicitly
    // or assume the caller will provide it. For simplicity, we'll assume
    // sessionManager will pass this correctly.
    // A more robust solution might pass the SessionState to this method
    // or have SessionNotifier handle populating this data.

    return ProjectMetadata(
      id: id,
      name: name,
      rootUri: rootUri,
      lastOpenedDateTime: DateTime.now(),
      lastOpenedTabIndex: lastOpenedTabIndex,
      lastOpenedFileUri: lastOpenedFileUri,
    );
  }
}

// --------------------
//    Session Manager
// --------------------

class SessionManager {
  final FileHandler _fileHandler;
  final Set<EditorPlugin> _plugins;
  final SharedPreferences _prefs; // Changed type from dynamic

  SessionManager({
    required FileHandler fileHandler,
    required Set<EditorPlugin> plugins,
    required SharedPreferences prefs, // Changed type
  }) : _fileHandler = fileHandler,
       _plugins = plugins,
       _prefs = prefs;

  // NEW: Open a project by its metadata
  Future<Project> openProject(ProjectMetadata projectMetadata) async {
    final projectDataFolder = await _fileHandler.ensureProjectDataFolder(projectMetadata.rootUri);
    if (projectDataFolder == null) {
      throw Exception('Could not access or create .machine folder for project ${projectMetadata.name}');
    }

    final projectDataFile = await _fileHandler.getFileMetadata('${projectDataFolder.uri}/project_data.json');
    Project project;

    if (projectDataFile != null) {
      try {
        final content = await _fileHandler.readFile(projectDataFile.uri);
        project = Project.fromJson(jsonDecode(content));
        // Ensure properties from metadata override in-file data for name/rootUri
        project.name = projectMetadata.name;
        project.rootUri = projectMetadata.rootUri;
      } catch (e) {
        print('Error loading project data from file: $e. Re-initializing project.');
        project = _createDefaultProject(projectMetadata);
      }
    } else {
        print("creating project from scratch");
      project = _createDefaultProject(projectMetadata);
    }
    return project;
  }

  // NEW: Create a project object from an existing folder
  Future<Project> createProjectFromFolder(DocumentFile projectRoot) async {
    final projectDataDir = await _fileHandler.ensureProjectDataFolder(projectRoot.uri);
    if (projectDataDir == null) {
      throw Exception('Could not create .machine folder for project at ${projectRoot.uri}');
    }

    final projectId = const Uuid().v4(); // Generate a unique ID for the project
    final project = Project(
      id: projectId,
      name: projectRoot.name,
      rootUri: projectRoot.uri,
      projectDataPath: projectDataDir.uri,
      expandedFolders: {projectRoot.uri}, // Start with root expanded
    );

    await saveProject(project); // Save initial project data
    return project;
  }

  // REMOVED: createProject that created a subfolder is no longer needed from the UI.

  // NEW: Save current project state to its .machine folder
  Future<void> saveProject(Project project) async {
    final projectDataFolder = await _fileHandler.ensureProjectDataFolder(project.rootUri);
    if (projectDataFolder == null) {
      print('Warning: Could not access .machine folder for project ${project.name}. Project data not saved.');
      return;
    }

    final projectDataFile = await _fileHandler.createDocumentFile(
      projectDataFolder.uri,
      'project_data.json',
      initialContent: jsonEncode(project.toJson()),
    );
    if (projectDataFile == null) {
      print('Warning: Could not create/write project_data.json for ${project.name}.');
    }
  }

  // Helper to create a default project object if no saved data exists
  Project _createDefaultProject(ProjectMetadata metadata) {
    return Project(
      id: metadata.id,
      name: metadata.name,
      rootUri: metadata.rootUri,
      projectDataPath: '${metadata.rootUri}/.machine', // Assuming .machine exists or can be created
      expandedFolders: {metadata.rootUri}, // Default to root expanded
      sessionData: {},
    );
  }

  Future<SessionState> openFile(
      SessionState current,
      DocumentFile file,
      {EditorPlugin? plugin}
      ) async {
    final existingIndex = current.tabs.indexWhere((t) => t.file.uri == file.uri);
    if (existingIndex != -1) return current.copyWith(currentTabIndex: existingIndex);

    final content = await _fileHandler.readFile(file.uri);
    final selectedPlugin = plugin ?? _plugins.firstWhere((p) => p.supportsFile(file));
    final tab = await selectedPlugin.createTab(file, content);
    
    return current.copyWith(
      tabs: [...current.tabs, tab],
      currentTabIndex: current.tabs.length,
    );
  }

  Future<EditorTab> saveTabFile(EditorTab tab) async {
    try {
      final newFile = await _fileHandler.writeFile(tab.file, tab.contentString);
      return tab.copyWith(file: newFile, isDirty: false);
    } catch (e, st) {
      print('Save failed: $e\n$st');
      return tab;
    }
  }

  SessionState reorderTabs(SessionState current, int oldIndex, int newIndex) {
    final newTabs = List<EditorTab>.from(current.tabs);
    final movedTab = newTabs.removeAt(oldIndex);
    newTabs.insert(newIndex, movedTab);

    return current.copyWith(
      tabs: newTabs,
      currentTabIndex: current.currentTabIndex,
    );
  }

  SessionState closeTab(SessionState current, int index) {
    final newTabs = List<EditorTab>.from(current.tabs)..removeAt(index);
    return current.copyWith(
      tabs: newTabs,
      currentTabIndex: _calculateNewIndex(current.currentTabIndex, index),
    );
  }

  int _calculateNewIndex(int currentIndex, int closedIndex) =>
      currentIndex == closedIndex ? max(0, closedIndex - 1) : currentIndex;

  Future<void> persistRootUri(String? uri) async {
    // This is typically handled by SAFFileHandler's internal persistence.
    // This method might be deprecated or used for app-level root folder selection.
    // For project-based persistence, save it within the Project object.
    if (uri != null) {
      await _fileHandler.persistRootUri(uri);
    }
  }

  Future<SessionState> loadSession() async {
    try {
      final json = _prefs.getString('session');
      if (json == null) return const SessionState();

      final data = jsonDecode(json) as Map<String, dynamic>;
      // SessionState.fromJson now only loads knownProjects
      return await SessionState.fromJson(data, _plugins, _fileHandler);
    } catch (e) {
      print('Session load error: $e');
      await _prefs.remove('session');
      return const SessionState();
    }
  }

  Future<void> saveSession(SessionState state) async {
    try {
      // Pass the current tab info for metadata update
      final currentTab = state.currentTab;
      final currentTabIndex = state.currentTabIndex;
      final currentFileUri = currentTab?.file.uri;

      // Update current project metadata before saving known projects list
      if (state.currentProject != null) {
        state.currentProject!.sessionData['lastOpenedTabIndex'] = currentTabIndex;
        state.currentProject!.sessionData['lastOpenedFileUri'] = currentFileUri;
        await saveProject(state.currentProject!); // Save current project's detailed state
      }

      await _prefs.setString('session', jsonEncode(state.toJson()));
    } catch (e) {
      print('Error saving session: $e');
    }
  }

  // NEW: Add a project to the known projects list
  Future<void> addKnownProject(ProjectMetadata projectMetadata) async {
    final currentSession = await loadSession(); // Load current known projects
    final updatedKnownProjects = List<ProjectMetadata>.from(currentSession.knownProjects);
    final existingIndex = updatedKnownProjects.indexWhere((p) => p.id == projectMetadata.id);

    if (existingIndex != -1) {
      updatedKnownProjects[existingIndex] = projectMetadata; // Update if exists
    } else {
      updatedKnownProjects.add(projectMetadata); // Add new
    }
    final newState = currentSession.copyWith(knownProjects: updatedKnownProjects);
    await saveSession(newState); // Save the updated list
  }

  // NEW: Remove a project from the known projects list
  Future<void> removeKnownProject(String projectId) async {
    final currentSession = await loadSession();
    final updatedKnownProjects = List<ProjectMetadata>.from(currentSession.knownProjects)
      ..removeWhere((p) => p.id == projectId);
    final newState = currentSession.copyWith(knownProjects: updatedKnownProjects);
    await saveSession(newState);
  }
}

// --------------------
//  Session Notifier
// --------------------

class SessionNotifier extends Notifier<SessionState> {
  late final SessionManager _manager;
  bool _loaded = false;
  bool _isSaving = false;
  bool _initialized = false;
  final Uuid _uuid = const Uuid(); // NEW: For generating project IDs

  @override
  SessionState build() {
    _manager = ref.read(sessionManagerProvider);
    return const SessionState(); // Initial state
  }

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final loadedState = await _manager.loadSession();
      state = loadedState;
    } catch (e, st) {
      ref.read(logProvider.notifier).add('Session load error: $e\n$st');
    } finally {
      _initialized = true;
    }
  }

  @override
  Future<void> loadSession() async { // MODIFIED to integrate with new Project loading
    try {
      final loadedState = await _manager.loadSession();
      state = loadedState;

      final lastOpenedProjectId = _manager._prefs.getString('lastOpenedProjectId');
      if (lastOpenedProjectId != null) {
        final lastProjectMetadata = state.knownProjects.firstWhereOrNull((p) => p.id == lastOpenedProjectId);
        if (lastProjectMetadata != null) {
          await openProject(lastProjectMetadata.id); // Attempt to open last project
        }
      }
      // If no project is opened (or couldn't be loaded), currentProject will be null.
      _handlePluginLifecycle(null, state.currentTab);
    } catch (e) {
      print('Error loading session: $e');
      _handlePluginLifecycle(state.currentTab, null);
    }
  }

  // NEW: Open an existing project by its ID
  Future<void> openProject(String projectId) async {
    final projectMetadata = state.knownProjects.firstWhereOrNull((p) => p.id == projectId);
    if (projectMetadata == null) {
      print('Project with ID $projectId not found in known projects.');
      return;
    }

    try {
      final project = await _manager.openProject(projectMetadata);
      state = state.copyWith(currentProject: project);

      // Open last opened tabs/files for this project
      final lastOpenedTabIndex = project.sessionData['lastOpenedTabIndex'] as int?;
      final lastOpenedFileUri = project.sessionData['lastOpenedFileUri'] as String?;

      if (lastOpenedFileUri != null) {
        final file = await ref.read(fileHandlerProvider).getFileMetadata(lastOpenedFileUri);
        if (file != null) {
          //await openFile(file); // Re-open the file
          if (lastOpenedTabIndex != null && lastOpenedTabIndex < state.tabs.length) {
            switchTab(lastOpenedTabIndex); // Switch to the specific tab
          }
        }
      }
      // Ensure the project's root URI is persisted for SAF permissions
      await ref.read(fileHandlerProvider).persistRootUri(project.rootUri);

      print('Project "${project.name}" opened successfully.');
    } catch (e, st) {
      print('Error opening project $projectId: $e\n$st');
      ref.read(logProvider.notifier).add('Error opening project: $e');
      state = state.copyWith(currentProject: null); // Clear current project on error
    }
  }

  // NEW: Open a folder as a project. If it's a known project, open it.
  // If it's a new folder, create a project from it and open it.
  Future<void> openProjectFromFolder(DocumentFile folder) async {
    try {
      // Check if a project with this root URI already exists
      final existingMeta = state.knownProjects.firstWhereOrNull((p) => p.rootUri == folder.uri);

      if (existingMeta != null) {
        // If it exists, just open it
        await openProject(existingMeta.id);
        return;
      }

      // If it doesn't exist, create a new project from the folder
      final newProject = await _manager.createProjectFromFolder(folder);
      final newMeta = newProject.toMetadata();

      // Add to known projects list in state and persist the list
      final updatedKnownProjects = [...state.knownProjects, newMeta];
      state = state.copyWith(
        currentProject: newProject,
        knownProjects: updatedKnownProjects,
      );

      // Persist the session which now includes the new project in the known list
      await _manager.saveSession(state);

      // Persist SAF permissions for the new project root
      await ref.read(fileHandlerProvider).persistRootUri(newProject.rootUri);

      print('Project "${newProject.name}" created and opened from folder.');
    } catch (e, st) {
      print('Error opening project from folder: $e\n$st');
      ref.read(logProvider.notifier).add('Error opening project: $e');
    }
  }

  // REMOVED: `createProject(String parentUri, String name)` is no longer needed.

  // NEW: Close the current project
  Future<void> closeProject() async {
    if (state.currentProject == null) return;

    // Save current project state before closing
    await _manager.saveProject(state.currentProject!);

    // Close all open tabs for the current project
    for (var tab in state.tabs) {
      tab.dispose();
    }

    state = state.copyWith(
      tabs: [], // Clear all tabs
      currentTabIndex: 0,
      currentProject: null, // Clear current project
    );
    print('Project closed.');
    await ref.read(fileHandlerProvider).persistRootUri(null); // Clear persisted URI
  }

  // MODIFIED: `deleteProject` no longer deletes the folder, only removes it from history.
  Future<void> deleteProject(String projectId) async {
    final projectToDeleteMetadata = state.knownProjects.firstWhereOrNull((p) => p.id == projectId);
    if (projectToDeleteMetadata == null) return;

    if (state.currentProject?.id == projectId) {
      await closeProject(); // Close if it's the current project
    }

    try {
      await _manager.removeKnownProject(projectId); // Remove from global list
      state = state.copyWith(
        knownProjects: state.knownProjects.where((p) => p.id != projectId).toList(),
      );
      print('Project "${projectToDeleteMetadata.name}" removed from history.');
    } catch (e, st) {
      print('Error removing project from history: $e\n$st');
      ref.read(logProvider.notifier).add('Error removing project: $e');
    }
  }

  // NEW: Update project explorer view mode
  void updateProjectExplorerMode(FileExplorerViewMode mode) {
    if (state.currentProject != null) {
      state = state.copyWith(
        currentProject: state.currentProject!.copyWith(fileExplorerViewMode: mode),
      );
    }
  }

  // NEW: Toggle folder expansion state
  void toggleFolderExpansion(String folderUri) {
    if (state.currentProject != null) {
      final updatedExpandedFolders = Set<String>.from(state.currentProject!.expandedFolders);
      if (updatedExpandedFolders.contains(folderUri)) {
        updatedExpandedFolders.remove(folderUri);
      } else {
        updatedExpandedFolders.add(folderUri);
      }
      state = state.copyWith(
        currentProject: state.currentProject!.copyWith(expandedFolders: updatedExpandedFolders),
      );
    }
  }

  // NEW: Toggle all folder expansion (for expand/collapse all buttons)
  Future<void> toggleAllFolderExpansion({required bool expand}) async {
    if (state.currentProject == null) return;

    final handler = ref.read(fileHandlerProvider);
    final Set<String> newExpandedFolders = {};

    if (expand) {
      // Recursively add all subdirectories to expandedFolders
      Future<void> expandRecursive(String uri) async {
        newExpandedFolders.add(uri);
        final contents = await handler.listDirectory(uri, includeHidden: true);
        for (final item in contents) {
          if (item.isDirectory && item.name != '.machine') { // Don't expand .machine
            await expandRecursive(item.uri);
          }
        }
      }
      await expandRecursive(state.currentProject!.rootUri);
    }
    // If expand is false, newExpandedFolders will remain empty.

    state = state.copyWith(
      currentProject: state.currentProject!.copyWith(expandedFolders: newExpandedFolders),
    );
  }


  Future<void> openFile(DocumentFile file, {EditorPlugin? plugin}) async {
    final prevTab = state.currentTab;
    state = await _manager.openFile(state, file, plugin: plugin);
    _handlePluginLifecycle(prevTab, state.currentTab);
  }

  void switchTab(int index) {
    final prevTab = state.currentTab;
    state = state.copyWith(currentTabIndex: index);
    _handlePluginLifecycle(prevTab, state.currentTab);
  }

  void updateTabState(EditorTab oldTab, EditorTab newTab) {
    state = state.copyWith(
      tabs: state.tabs.map((t) => t == oldTab ? newTab : t).toList(),
    );
  }

  void updateTabLanguageKey(int tabIndex, String newLanguageKey) {
    final currentTabs = List<EditorTab>.from(state.tabs);
    if (tabIndex < 0 || tabIndex >= currentTabs.length) return;

    final targetTab = currentTabs[tabIndex];
    if (targetTab is CodeEditorTab) {
      final updatedTab = targetTab.copyWith(languageKey: newLanguageKey);
      currentTabs[tabIndex] = updatedTab;
      state = state.copyWith(tabs: currentTabs);
    }
  }


  void markCurrentTabDirty() {
    final current = state;
    final currentTab = current.currentTab;
    if (currentTab == null) return;
    if (currentTab.isDirty == true) return;

    state = current.copyWith(
      tabs:
      current.tabs
          .map(
            (t) => t == currentTab ? currentTab.copyWith(isDirty: true) : t,
      )
          .toList(),
    );
  }

  void _handlePluginLifecycle(EditorTab? oldTab, EditorTab? newTab) {
    if (oldTab != null) {
      oldTab.plugin.deactivateTab(oldTab, ref);
    }
    if (newTab != null) {
      newTab.plugin.activateTab(newTab, ref);
    }
  }

  void closeTab(int index) {
    final current = state;
    if (index < 0 || index >= current.tabs.length) return;

    final closedTab = current.tabs[index];
    closedTab.plugin.deactivateTab(closedTab, ref);
    closedTab.dispose();

    state = _manager.closeTab(state, index);

    if (state.currentTab != null) {
      state.currentTab!.plugin.activateTab(state.currentTab!, ref);
    }
  }

  void reorderTabs(int oldIndex, int newIndex) {
    state = _manager.reorderTabs(state, oldIndex, newIndex);
  }

  // REMOVED: changeDirectory(DocumentFile directory) is replaced by openProject

  Future<void> saveTab(int index) async {
    final current = state;
    if (index < 0 || index >= current.tabs.length) return;

    final targetTab = current.tabs[index];

    try {
      final newTab = await _manager.saveTabFile(targetTab);

      final newTabs =
          current.tabs.map((t) => t == targetTab ? newTab : t).toList();

      state = current.copyWith(tabs: newTabs, lastSaved: DateTime.now());
    } catch (e) {
      ref.read(logProvider.notifier).add('Save failed: ${e.toString()}');
    }
  }

  Future<void> saveSession() async {
    if (!_isSaving) {
      _isSaving = true;
      try {
        await _manager.saveSession(state);
        state = state.copyWith(lastSaved: DateTime.now());
      } catch (e) {
        print('Error saving session: $e');
      } finally {
        _isSaving = false;
      }
    }
  }
}

// --------------------
//  Tabs
// --------------------

abstract class EditorTab {
  final DocumentFile file;
  final EditorPlugin plugin;
  bool isDirty;

  EditorTab({required this.file, required this.plugin, this.isDirty = false});
  String get contentString;
  void dispose();

  EditorTab copyWith({DocumentFile? file, EditorPlugin? plugin, bool? isDirty});

  // New: Abstract methods for serialization
  Map<String, dynamic> toJson();
  // Not a static factory here, as it needs plugin instance.
  // The actual deserialization factory is on EditorPlugin.
}

class CodeEditorTab extends EditorTab {
  final CodeLineEditingController controller;
  final CodeCommentFormatter commentFormatter;
  final String? languageKey; // New: Store the language key (e.g., 'dart', 'python')

  CodeEditorTab({
    required super.file,
    required this.controller,
    required super.plugin,
    required this.commentFormatter,
    super.isDirty = false,
    this.languageKey, // Initialize new property
  });

  @override
  void dispose() {
    controller.dispose();
  }

  @override
  String get contentString {
    return this.controller.text ?? ""; // Corrected to use `this.controller.text`
  }

  @override
  CodeEditorTab copyWith({
    DocumentFile? file,
    EditorPlugin? plugin,
    bool? isDirty,
    CodeLineEditingController? controller,
    CodeCommentFormatter? commentFormatter,
    String? languageKey, // Include in copyWith
  }) {
    return CodeEditorTab(
      file: file ?? this.file,
      plugin: plugin ?? this.plugin,
      isDirty: isDirty ?? this.isDirty,
      controller: controller ?? this.controller,
      commentFormatter: commentFormatter ?? this.commentFormatter,
      languageKey: languageKey ?? this.languageKey, // Copy new property
    );
  }

  // New: Convert CodeEditorTab to JSON
  @override
  Map<String, dynamic> toJson() => {
    'fileUri': file.uri,
    'pluginType': plugin.runtimeType.toString(),
    'languageKey': languageKey, // Serialize language key
    'isDirty': isDirty, // Also serialize dirty state for initial load
  };
}