import 'dart:convert';
import 'dart:math'; // For max()

import 'package:collection/collection.dart'; // For DeepCollectionEquality
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart'; // For CodeLineEditingController, CodeCommentFormatter, CodeLinePosition

import '../file_system/file_handler.dart'; // For DocumentFile, FileHandler
import '../main.dart'; // For sharedPreferencesProvider, printStream
import '../plugins/plugin_architecture.dart'; // For EditorPlugin, activePluginsProvider
import '../screens/settings_screen.dart'; // For LogNotifier

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

class _LifecycleHandlerState extends State<LifecycleHandler>
    with WidgetsBindingObserver {
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
        final currentDir = container.read(rootUriProvider);
        if (currentDir != null) {
          await container
              .read(fileHandlerProvider)
              .persistRootUri(currentDir.uri);
        }
        break;
      default:
        break;
    }
  }

  Future<void> _debouncedSave(ProviderContainer container) async {
    await container.read(sessionProvider.notifier).saveSession();
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
  final DocumentFile? currentDirectory;
  final DateTime? lastSaved;

  const SessionState({
    this.tabs = const [],
    this.currentTabIndex = 0,
    this.currentDirectory,
    this.lastSaved,
  });

  EditorTab? get currentTab => tabs.isNotEmpty ? tabs[currentTabIndex] : null;

  SessionState copyWith({
    List<EditorTab>? tabs,
    int? currentTabIndex,
    DocumentFile? currentDirectory,
    DateTime? lastSaved,
  }) {
    return SessionState(
      tabs: tabs ?? this.tabs,
      currentTabIndex: currentTabIndex ?? this.currentTabIndex,
      currentDirectory: currentDirectory ?? this.currentDirectory,
      lastSaved: lastSaved ?? this.lastSaved,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionState &&
          currentTabIndex == other.currentTabIndex &&
          const DeepCollectionEquality().equals(tabs, other.tabs) &&
          currentDirectory?.uri == other.currentDirectory?.uri;

  @override
  int get hashCode => Object.hash(
    currentTabIndex,
    const DeepCollectionEquality().hash(tabs),
    currentDirectory?.uri,
  );

  // Modified: Call tab.toJson() directly
  Map<String, dynamic> toJson() => {
    'tabs': tabs.map((t) => t.toJson()).toList(),
    'currentIndex': currentTabIndex,
    'directory': currentDirectory?.uri,
  };

  // Modified: Use EditorPlugin.createTabFromSerialization for deserialization
  static Future<SessionState> fromJson(
    Map<String, dynamic> json,
    Set<EditorPlugin> plugins,
    FileHandler fileHandler,
  ) async {
    final directoryUri = json['directory'];
    DocumentFile? directory;

    if (directoryUri != null) {
      directory = await fileHandler.getFileMetadata(directoryUri);
    }

    final tabsJson = json['tabs'] as List<dynamic>? ?? [];
    final loadedTabs = <EditorTab>[];

    for (final item in tabsJson) {
      try {
        final tabMap = item as Map<String, dynamic>;
        final pluginTypeString = tabMap['pluginType'] as String;
        final plugin = plugins.firstWhere(
          (p) => p.runtimeType.toString() == pluginTypeString,
        );
        final tab = await plugin.createTabFromSerialization(tabMap, fileHandler);
        loadedTabs.add(tab);
      } catch (e) {
        // Log error and skip problematic tab
        print('Error loading tab from JSON: $e');
      }
    }

    return SessionState(
      tabs: loadedTabs,
      currentTabIndex: json['currentIndex'] ?? 0,
      currentDirectory: directory,
    );
  }
}

// --------------------
//    Session Manager
// --------------------

class SessionManager {
  final FileHandler _fileHandler;
  final Set<EditorPlugin> _plugins;
  final SharedPreferences _prefs;

  SessionManager({
    required FileHandler fileHandler,
    required Set<EditorPlugin> plugins,
    required SharedPreferences prefs,
  }) : _fileHandler = fileHandler,
       _plugins = plugins,
       _prefs = prefs;

  Future<SessionState> openFile(
      SessionState current,
      DocumentFile file,
      {EditorPlugin? plugin}
      ) async {
    final existingIndex = current.tabs.indexWhere((t) => t.file.uri == file.uri);
    if (existingIndex != -1) return current.copyWith(currentTabIndex: existingIndex);

    final content = await _fileHandler.readFile(file.uri);
    final selectedPlugin = plugin ?? _plugins.firstWhere((p) => p.supportsFile(file));
    final tab = await selectedPlugin.createTab(file, content); // This uses createTab
    
    return current.copyWith(
      tabs: [...current.tabs, tab],
      currentTabIndex: current.tabs.length,
    );
  }

  Future<EditorTab> saveTabFile(EditorTab tab) async {
    try {
      final newFile = await _fileHandler.writeFile(tab.file, tab.contentString);

      // Preserve existing tab properties, only update file and dirty state
      final newTab = tab.copyWith(file: newFile, isDirty: false);
      return newTab;

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

  Future<void> persistDirectory(SessionState state) async {
    if (state.currentDirectory != null) {
      await _fileHandler.persistRootUri(state.currentDirectory!.uri);
    }
  }

  Future<SessionState> loadSession() async {
    try {
      final json = _prefs.getString('session');
      if (json == null) return const SessionState();

      final data = jsonDecode(json) as Map<String, dynamic>;
      return await SessionState.fromJson(data, _plugins, _fileHandler); // Use static fromJson
    } catch (e) {
      print('Session load error: $e');
      await _prefs.remove('session'); // Clear corrupt session data
      return const SessionState();
    }
  }

  // REMOVED: _deserializeState is no longer needed, logic moved to SessionState.fromJson
  // REMOVED: _loadTabFromJson is no longer needed, logic moved to SessionState.fromJson

  Future<DocumentFile?> _loadDirectory(String? uri) async {
    return uri != null ? await _fileHandler.getFileMetadata(uri) : null;
  }

  Future<void> saveSession(SessionState state) async {
    try {
      await _prefs.setString('session', jsonEncode(state.toJson()));
    } catch (e) {
      print('Error saving session: $e');
    }
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

  Future<void> openFile(DocumentFile file, {EditorPlugin? plugin}) async {
    final prevTab = state.currentTab;
    state = await _manager.openFile(state, file, plugin: plugin);
    _handlePluginLifecycle(prevTab, state.currentTab);
  }

  void switchTab(int index) {
    // FocusNode is now managed internally by CodeEditorMachine.
    // Unfocusing is handled by the widget's lifecycle (dispose/recreate)
    // and its internal focus listener.
    final prevTab = state.currentTab;
    state = state.copyWith(currentTabIndex: index);
    _handlePluginLifecycle(prevTab, state.currentTab);
  }

  void updateTabState(EditorTab oldTab, EditorTab newTab) {
    state = state.copyWith(
      tabs: state.tabs.map((t) => t == oldTab ? newTab : t).toList(),
    );
    // Note: markCurrentTabDirty should probably be called explicitly if the content changes,
    // not necessarily just on tab state update if it's metadata.
  }

  // New: Update language key for a CodeEditorTab
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
    if (currentTab.isDirty == true) return; // Only update if not already dirty

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
    if (index < 0 || index >= current.tabs.length) return; // Ensure index is valid

    final closedTab = current.tabs[index];
    closedTab.plugin.deactivateTab(closedTab, ref);
    closedTab.dispose(); // Dispose the tab's resources

    state = _manager.closeTab(state, index);

    if (state.currentTab != null) {
      state.currentTab!.plugin.activateTab(state.currentTab!, ref);
    }
  }

  void reorderTabs(int oldIndex, int newIndex) {
    state = _manager.reorderTabs(state, oldIndex, newIndex);
  }

  Future<void> changeDirectory(DocumentFile directory) async {
    //await _manager.persistDirectory(state);
    state = state.copyWith(currentDirectory: directory);
  }

  Future<void> loadSession() async {
    try {
      final loadedState = await _manager.loadSession();
      state = loadedState;
      // Activate the current tab only if it exists after loading
      if (state.currentTab != null) {
        _handlePluginLifecycle(null, state.currentTab);
      }
    } catch (e) {
      print('Error loading session: $e');
      // If session load fails, ensure no tab is active
      _handlePluginLifecycle(state.currentTab, null);
    }
  }

  Future<void> saveTab(int index) async {
    final current = state;
    if (index < 0 || index >= current.tabs.length) return;

    final targetTab = current.tabs[index]; // Use a distinct variable name

    try {
      final newTab = await _manager.saveTabFile(targetTab);

      // Create new immutable state
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