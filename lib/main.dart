import 'package:crypto/crypto.dart';
import 'dart:core';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'package:collection/collection.dart';

import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';
import 'package:saf_util/saf_util_method_channel.dart';
import 'package:saf_util/saf_util_platform_interface.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/latex.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/plaintext.dart';
import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// --------------------
//     Main
// --------------------
final printStream = StreamController<String>.broadcast();

ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFFF44336), // Red-500
    brightness: Brightness.dark,
  ).copyWith(
    background: const Color(0xFF2F2F2F),
    surface: const Color(0xFF2B2B29),
  ),
  // Custom AppBar styling (smaller height & title)
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF2B2B29), // Matches surface color
    elevation: 1, // Slight shadow
    scrolledUnderElevation: 1, // Shadow when scrolling
    centerTitle: true, // Optional: Center the title
    titleTextStyle: TextStyle(
      fontSize: 14, // Smaller title
      //fontWeight: FontWeight.w600,
    ),
    toolbarHeight: 56, // Less tall than default (default is 64 in M3)
  ),
  // Custom TabBar styling (matches AppBar background)
  tabBarTheme: TabBarTheme(
    indicator: UnderlineTabIndicator(
      borderSide: BorderSide(
        color: Color(0xFFF44336), // Matches seedColor
        width: 2.0,
      ),
    ),
    unselectedLabelColor: Colors.grey[400], // Unselected tab text
    //dividerColor: Colors.transparent, // Removes top divider
    //overlayColor: MaterialStateProperty.all(Colors.transparent), // Disables ripple
    // Optional: Adjust tab height & padding
    indicatorSize: TabBarIndicatorSize.tab,
    labelPadding: EdgeInsets.symmetric(horizontal: 12.0),
  ),
  // Custom ElevatedButton styling (slightly lighter than background)
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF3A3A3A),
    ),
  ),
);

void main() {
  runZonedGuarded(
    () {
      runApp(
        ProviderScope(
          child: LifecycleHandler(
            child: MaterialApp(
              theme: darkTheme,
              home: AppStartupWidget(
                onLoaded: (context) => const EditorScreen(),
              ),
              routes: {
                '/settings': (_) => const SettingsScreen(),
                '/command-settings': (_) => const CommandSettingsScreen(),
              },
            ),
          ),
        ),
      );
    },
    (error, stack) {
      printStream.add('[ERROR] $error\n$stack');
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, message) {
        final formatted = '[${DateTime.now()}] $message';
        parent.print(zone, formatted);
        printStream.add(formatted);
      },
    ),
  );
}

// --------------------
//   Providers
// --------------------

final sharedPreferencesProvider = FutureProvider<SharedPreferences>((
  ref,
) async {
  return await SharedPreferences.getInstance();
});

final fileHandlerProvider = Provider<FileHandler>((ref) {
  return SAFFileHandler();
});

final pluginRegistryProvider = Provider<Set<EditorPlugin>>(
  (_) => {CodeEditorPlugin()},
);

final activePluginsProvider =
    StateNotifierProvider<PluginManager, Set<EditorPlugin>>((ref) {
      return PluginManager(ref.read(pluginRegistryProvider));
    });

final rootUriProvider = StateProvider<DocumentFile?>((_) => null);

final directoryContentsProvider = FutureProvider.autoDispose
    .family<List<DocumentFile>, String?>((ref, uri) async {
      final handler = ref.read(fileHandlerProvider);
      final targetUri = uri ?? await handler.getPersistedRootUri();
      return targetUri != null ? handler.listDirectory(targetUri) : [];
    });

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

final bracketHighlightProvider =
    NotifierProvider<BracketHighlightNotifier, BracketHighlightState>(
      BracketHighlightNotifier.new,
    );

final logProvider = StateNotifierProvider<LogNotifier, List<String>>((ref) {
  // Capture the print stream when provider initializes
  final logNotifier = LogNotifier();
  final subscription = printStream.stream.listen(logNotifier.add);
  ref.onDispose(() => subscription.cancel());
  return logNotifier;
});

final commandProvider = StateNotifierProvider<CommandNotifier, CommandState>((
  ref,
) {
  return CommandNotifier(ref: ref, plugins: ref.watch(activePluginsProvider));
});

final appBarCommandsProvider = Provider<List<Command>>((ref) {
  final state = ref.watch(commandProvider);
  final notifier = ref.read(commandProvider.notifier);
  final currentPlugin = ref.watch(sessionProvider.select((s) => s.currentTab?.plugin.runtimeType.toString()));


  return [
    ...state.appBarOrder,
    ...state.pluginToolbarOrder.where(
      (id) => notifier.getCommand(id)?.defaultPosition == CommandPosition.both,
    ),
  ].map((id) => notifier.getCommand(id))
  .where((cmd) => _shouldShowCommand(cmd!, currentPlugin))
  .whereType<Command>()
  .toList();
});


final pluginToolbarCommandsProvider = Provider<List<Command>>((ref) {
  final state = ref.watch(commandProvider);
  final notifier = ref.read(commandProvider.notifier);
  final currentPlugin = ref.watch(sessionProvider.select((s) => s.currentTab?.plugin.runtimeType.toString()));

  return [
    ...state.pluginToolbarOrder,
    ...state.appBarOrder.where(
      (id) => notifier.getCommand(id)?.defaultPosition == CommandPosition.both,
    ),
  ].map((id) => notifier.getCommand(id))
  .whereType<Command>()
  .where((cmd) => _shouldShowCommand(cmd!, currentPlugin))
  .toList();
});

bool _shouldShowCommand(Command cmd, String? currentPlugin) {
  // Always show core commands
  if (cmd.sourcePlugin == 'Core') return true;
  // Show plugin-specific commands only when their plugin is active
  return cmd.sourcePlugin == currentPlugin;
}

final canUndoProvider = StateProvider<bool>((ref) => false);
final canRedoProvider = StateProvider<bool>((ref) => false);
final markProvider = StateProvider<CodeLinePosition?>((ref) => null);


final tabBarScrollProvider = Provider<ScrollController>((ref) {
  return ScrollController();
});

final bottomToolbarScrollProvider = Provider<ScrollController>((ref) {
  return ScrollController();
});

// --------------------
//         Logs
// --------------------

class LogNotifier extends StateNotifier<List<String>> {
  LogNotifier() : super([]);

  void add(String message) {
    state = [...state, '${DateTime.now().toIso8601String()}: $message'];
    if (state.length > 200) {
      state = state.sublist(state.length - 100); // Keep last 100 entries
    }
  }

  void clearLogs() {
    state = [];
  }
}

class DebugLogView extends ConsumerWidget {
  const DebugLogView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(logProvider);

    return AlertDialog(
      title: const Text('Debug Logs'),
      content: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: logs.length,
              itemBuilder: (context, index) => Text(logs[index]),
            ),
          ),
          Row(
            children: [
              TextButton(
                onPressed: () => ref.read(logProvider.notifier).clearLogs(),
                child: const Text('Clear'),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// --------------------
//        Startup
// --------------------
final appStartupProvider = FutureProvider<void>((ref) async {
  await appStartup(ref);
});

Future<void> appStartup(Ref ref) async {
  try {
    final prefs = await ref.read(sharedPreferencesProvider.future);

    ref.read(logProvider.notifier);
    await ref.read(settingsProvider.notifier).loadSettings();
    await ref.read(sessionProvider.notifier).initialize();
  } catch (e, st) {
    print('App startup error: $e\n$st');
    rethrow;
  }
}

class AppStartupWidget extends ConsumerWidget {
  final WidgetBuilder onLoaded;

  const AppStartupWidget({super.key, required this.onLoaded});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startupState = ref.watch(appStartupProvider);

    return startupState.when(
      loading: () => const AppStartupLoadingWidget(),
      error:
          (error, stack) => AppStartupErrorWidget(
            error: error,
            onRetry: () => ref.invalidate(appStartupProvider),
          ),
      data: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(sessionProvider.notifier).loadSession();
        });
        return onLoaded(context);
      },
    );
  }
}

class AppStartupLoadingWidget extends StatelessWidget {
  const AppStartupLoadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Initializing application...'),
          ],
        ),
      ),
    );
  }
}

class AppStartupErrorWidget extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const AppStartupErrorWidget({
    super.key,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 50),
            const SizedBox(height: 20),
            Text('Initialization failed: $error', textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

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

// --------------------
//      Tab Bar
// --------------------
class TabBarView extends ConsumerWidget {
  const TabBarView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrollController = ref.watch(tabBarScrollProvider);
    final tabs = ref.watch(sessionProvider.select((state) => state.tabs));

    return Container(
      color: Colors.grey[900],
      height: 40,
      child: CodeEditorTapRegion(
        child: ReorderableListView(
          key: const PageStorageKey<String>('tabBarScrollPosition'),
          scrollController: scrollController,
          scrollDirection: Axis.horizontal,
          onReorder:
              (oldIndex, newIndex) => ref
                  .read(sessionProvider.notifier)
                  .reorderTabs(oldIndex, newIndex),
          buildDefaultDragHandles: false,
          children: [
            for (final tab in tabs)
              ReorderableDelayedDragStartListener(
                key: ValueKey(tab.file),
                index: tabs.indexOf(tab),
                child: FileTab(tab: tab, index: tabs.indexOf(tab)),
              ),
          ],
        ),
      ),
    );
  }
}

class FileTab extends ConsumerWidget {
  final EditorTab tab;
  final int index;

  const FileTab({super.key, required this.tab, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = ref.watch(
      sessionProvider.select((s) => s.currentTabIndex == index),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 200),
      child: Material(
        color: isActive ? Colors.blueGrey[800] : Colors.grey[900],
        child: InkWell(
          onTap: () => ref.read(sessionProvider.notifier).switchTab(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed:
                      () => ref.read(sessionProvider.notifier).closeTab(index),
                ),
                Expanded(
                  child: Text(
                    tab.file.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tab.isDirty ? Colors.orange : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getFileName(String uri) =>
      Uri.parse(uri).pathSegments.last.split('/').last;
}

// --------------------
//    Editor Screen
// --------------------

class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUri = ref.watch(
      sessionProvider.select((s) => s.currentTab?.file.uri), // Use sessionProvider
    );
    final currentName = ref.read(
      sessionProvider.select((s) => s.currentTab?.file.name), // Use sessionProvider
    );
    final currentDir = ref.watch(
      sessionProvider.select((s) => s.currentDirectory),
    );
    final currentPlugin = ref.watch(
      sessionProvider.select((s) => s.currentTab?.plugin),
    );

    final scaffoldKey = GlobalKey<ScaffoldState>(); // Add key here

    return Scaffold(
      key: scaffoldKey, // Assign key to Scaffold
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          currentPlugin is CodeEditorPlugin
              ? CodeEditorTapRegion(child: const AppBarCommands())
              : const AppBarCommands(),
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed:
                () => showDialog(
                  context: context,
                  builder: (_) => const DebugLogView(),
                ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
        title: Text(currentName != null ? currentName : 'Code Editor'),
      ),
      drawer: FileExplorerDrawer(currentDir: currentDir),
      body: Column(
        children: [
          const TabBarView(),
          Expanded(
            child:
                currentUri != null
                    ? EditorContentSwitcher()
                    : const Center(child: Text('Open file')),
          ),
          if (currentPlugin != null) currentPlugin.buildToolbar(ref),
        ],
      ),
    );
  }
}

// --------------------
//   Plugin Registry
// --------------------

class PluginManager extends StateNotifier<Set<EditorPlugin>> {
  PluginManager(Set<EditorPlugin> plugins) : super(plugins);

  void registerPlugin(EditorPlugin plugin) => state = {...state, plugin};
  void unregisterPlugin(EditorPlugin plugin) =>
      state = state.where((p) => p != plugin).toSet();
}

// --------------------
//   Editor Plugin
// --------------------

abstract class EditorPlugin {
  // Metadata
  String get name;
  Widget get icon;
  List<Command> getCommands();

  // File type support
  bool supportsFile(DocumentFile file);

  // Tab management
  Future<EditorTab> createTab(DocumentFile file, String content);
  Widget buildEditor(EditorTab tab, WidgetRef ref);

  void activateTab(EditorTab tab, NotifierProviderRef<SessionState> ref);
  void deactivateTab(EditorTab tab, NotifierProviderRef<SessionState> ref);

  PluginSettings? get settings;
  Widget buildSettingsUI(PluginSettings settings);

  Widget buildToolbar(WidgetRef ref) {
    return const SizedBox.shrink(); // Default empty implementation
  }

  // New: Method for deserializing tabs
  Future<EditorTab> createTabFromSerialization(Map<String, dynamic> tabJson, FileHandler fileHandler);

  // Optional lifecycle hooks
  Future<void> dispose() async {}
}

// --------------------
//  Code Editor Plugin
// --------------------

class CodeEditorPlugin implements EditorPlugin {
  @override
  String get name => 'Code Editor';

  @override
  Widget get icon => const Icon(Icons.code);

  @override
  final PluginSettings? settings = CodeEditorSettings();

  @override
  Widget buildSettingsUI(PluginSettings settings) {
    final editorSettings = settings as CodeEditorSettings;
    return CodeEditorSettingsUI(settings: editorSettings);
  }
  /*
  @override
  Future<void> initializeTab(EditorTab tab, String? content) async {
    if (tab is CodeEditorTab) {
      tab.controller.codeLines = CodeLines.fromText(content ?? '');
    }
  }*/

  @override
  Future<void> dispose() async {
    // Cleanup logic here
    print("dispose code editor");
  }

  @override
  bool supportsFile(DocumentFile file) {
    final ext = file.name.split('.').last.toLowerCase();
    return _languageExtToNameMap.containsKey(ext); // Use the new map
  }

  @override
  Future<EditorTab> createTab(DocumentFile file, String content) async {
    final controller = CodeLineEditingController(
      spanBuilder: _buildHighlightingSpan,
      codeLines: CodeLines.fromText(content ?? ''),
    );
    final inferredLanguageKey = _inferLanguageKey(file.uri); // Infer language key
    return CodeEditorTab(
      file: file,
      plugin: this,
      controller: controller,
      commentFormatter: _getCommentFormatter(file.uri),
      languageKey: inferredLanguageKey, // Store inferred key
    );
  }

  // New: Implementation for deserializing CodeEditorTab
  @override
  Future<EditorTab> createTabFromSerialization(Map<String, dynamic> tabJson, FileHandler fileHandler) async {
    final fileUri = tabJson['fileUri'] as String;
    final loadedLanguageKey = tabJson['languageKey'] as String?;
    final isDirtyOnLoad = tabJson['isDirty'] as bool? ?? false; // Load dirty state

    final file = await fileHandler.getFileMetadata(fileUri);
    if (file == null) {
      throw Exception('File not found for tab URI: $fileUri');
    }

    final content = await fileHandler.readFile(fileUri);
    final controller = CodeLineEditingController(
      spanBuilder: _buildHighlightingSpan,
      codeLines: CodeLines.fromText(content ?? ''),
    );

    return CodeEditorTab(
      file: file,
      plugin: this,
      controller: controller,
      commentFormatter: _getCommentFormatter(file.uri),
      languageKey: loadedLanguageKey ?? _inferLanguageKey(file.uri), // Use loaded or infer
      isDirty: isDirtyOnLoad,
    );
  }


  @override
  void activateTab(EditorTab tab, NotifierProviderRef<SessionState> ref) {
    if (tab is! CodeEditorTab) return;

    // Explicit state updates for mark/highlight can still be useful here.
    ref.read(markProvider.notifier).state = null; // Clear mark when tab changes
    ref.read(bracketHighlightProvider.notifier).state = BracketHighlightState(); // Clear highlights
  }

  @override
  void deactivateTab(EditorTab tab, NotifierProviderRef<SessionState> ref) {
    if (tab is! CodeEditorTab) return;
    ref.read(markProvider.notifier).state = null; // Clear mark when tab is deactivated
    ref.read(bracketHighlightProvider.notifier).state = BracketHighlightState(); // Clear highlights
  }

  @override
  Widget buildEditor(EditorTab tab, WidgetRef ref) {
    final codeTab = tab as CodeEditorTab;
    final settings = ref.watch(
      settingsProvider.select(
            (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
      ),
    );

    // Pass the language key from the tab state to CodeEditorMachine
    return CodeEditorMachine(
      key: ValueKey(codeTab.file.uri), // Key remains tied to the file URI
      controller: codeTab.controller,
      commentFormatter: codeTab.commentFormatter,
      indicatorBuilder: (
          context,
          editingController,
          chunkController,
          notifier,
          ) {
        return _CustomEditorIndicator(
          controller: editingController,
          chunkController: chunkController,
          notifier: notifier,
        );
      },
      style: CodeEditorStyle(
        fontSize: settings?.fontSize ?? 12,
        fontFamily: settings?.fontFamily ?? 'JetBrainsMono',
        // The language mode will be determined inside CodeEditorMachine's build method
        // by watching the sessionProvider.
      ),
      wordWrap: settings?.wordWrap ?? false,
    );
  }

  TextSpan _buildHighlightingSpan({
    required BuildContext context,
    required int index,
    required CodeLine codeLine,
    required TextSpan textSpan,
    required TextStyle style,
  }) {
    final currentTab =
        ProviderScope.containerOf(context).read(sessionProvider).currentTab
            as CodeEditorTab;
    final highlightState = ProviderScope.containerOf(
      context,
    ).read(bracketHighlightProvider);

    final spans = <TextSpan>[];
    int currentPosition = 0;
    final highlightPositions =
        highlightState.bracketPositions
            .where((pos) => pos.index == index)
            .map((pos) => pos.offset)
            .toSet();
    //print(highlightState.bracketPositions.toString());
    void processSpan(TextSpan span) {
      final text = span.text ?? '';
      final spanStyle = span.style ?? style;
      List<int> highlightIndices = [];

      // Find highlight positions within this span
      for (var i = 0; i < text.length; i++) {
        if (highlightPositions.contains(currentPosition + i)) {
          highlightIndices.add(i);
        }
      }

      // Split span into non-highlight and highlight segments
      int lastSplit = 0;
      for (final highlightIndex in highlightIndices) {
        if (highlightIndex > lastSplit) {
          spans.add(
            TextSpan(
              text: text.substring(lastSplit, highlightIndex),
              style: spanStyle,
            ),
          );
        }
        spans.add(
          TextSpan(
            text: text[highlightIndex],
            style: spanStyle.copyWith(
              backgroundColor: Colors.yellow.withOpacity(0.3),
              fontWeight: FontWeight.bold,
            ),
          ),
        );
        lastSplit = highlightIndex + 1;
      }

      // Add remaining text
      if (lastSplit < text.length) {
        spans.add(TextSpan(text: text.substring(lastSplit), style: spanStyle));
      }

      currentPosition += text.length;

      // Process child spans
      if (span.children != null) {
        for (final child in span.children!) {
          if (child is TextSpan) {
            processSpan(child);
          }
        }
      }
    }

    processSpan(textSpan);
    return TextSpan(
      children: spans.isNotEmpty ? spans : [textSpan],
      style: style,
    );
  }

  CodeCommentFormatter _getCommentFormatter(String uri) {
    final extension = uri.split('.').last.toLowerCase();
    switch (extension) {
      case 'dart':
        return DefaultCodeCommentFormatter(
          singleLinePrefix: '//',
          multiLinePrefix: '/*',
          multiLineSuffix: '*/',
        );
      case 'tex':
        return DefaultCodeCommentFormatter(
          singleLinePrefix: '%',
        );
      default:
        return DefaultCodeCommentFormatter(
          singleLinePrefix: '//',
          multiLinePrefix: '/*',
          multiLineSuffix: '*/',
        );
    }
  }

  @override
  List<Command> getCommands() => [
    _createCommand( // Moved this command to the top level for clarity
      id: 'save',
      label: 'Save',
      icon: Icons.save,
      defaultPosition: CommandPosition.appBar, // Default position in AppBar
      execute: (ref, _) {
        final session = ref.read(sessionProvider);
        final currentIndex = session.currentTabIndex;
        if (currentIndex != -1) {
          ref.read(sessionProvider.notifier).saveTab(currentIndex);
        }
      },
    ),
    _createCommand(
      id: 'copy',
      label: 'Copy',
      icon: Icons.content_copy,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.copy(), // Null check
    ),
    _createCommand(
      id: 'cut',
      label: 'Cut',
      icon: Icons.content_cut,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.cut(), // Null check
    ),
    _createCommand(
      id: 'paste',
      label: 'Paste',
      icon: Icons.content_paste,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.paste(), // Null check
    ),
    _createCommand(
      id: 'indent',
      label: 'Indent',
      icon: Icons.format_indent_increase,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.applyIndent(), // Null check
    ),
    _createCommand(
      id: 'outdent',
      label: 'Outdent',
      icon: Icons.format_indent_decrease,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.applyOutdent(), // Null check
    ),
    _createCommand(
      id: 'toggle_comment',
      label: 'Toggle Comment',
      icon: Icons.comment,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: _toggleComments,
    ),
    _createCommand(
      id: 'reformat',
      label: 'Reformat',
      icon: Icons.format_align_left,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: _reformatDocument,
    ),
    _createCommand(
      id: 'select_brackets',
      label: 'Select Brackets',
      icon: Icons.code,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: _selectBetweenBrackets,
    ),
    _createCommand(
      id: 'extend_selection',
      label: 'Extend Selection',
      icon: Icons.horizontal_rule,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: _extendSelection,
    ),
    _createCommand(
      id: 'select_all',
      label: 'Select All',
      icon: Icons.select_all,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.selectAll(), // Null check
    ),
    _createCommand(
      id: 'move_line_up',
      label: 'Move Line Up',
      icon: Icons.arrow_upward,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.moveSelectionLinesUp(), // Null check
    ),
    _createCommand(
      id: 'move_line_down',
      label: 'Move Line Down',
      icon: Icons.arrow_downward,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.moveSelectionLinesDown(), // Null check
    ),
    _createCommand(
      id: 'set_mark',
      label: 'Set Mark',
      icon: Icons.bookmark_add,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: _setMarkPosition,
    ),
    _createCommand(
      id: 'select_to_mark',
      label: 'Select to Mark',
      icon: Icons.bookmark_added,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: _selectToMark,
      canExecute: (ref, ctrl) => ref.watch(markProvider) != null,
    ),
    _createCommand(
      id: 'undo',
      label: 'Undo',
      icon: Icons.undo,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.undo(), // Null check
      canExecute: (ref, ctrl) => ref.watch(canUndoProvider),
    ),
    _createCommand(
      id: 'redo',
      label: 'Redo',
      icon: Icons.redo,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.redo(), // Null check
      canExecute: (ref, ctrl) => ref.watch(canRedoProvider),
    ),
    _createCommand(
      id: 'show_cursor',
      label: 'Show Cursor',
      icon: Icons.center_focus_strong,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => ctrl?.makeCursorVisible(), // Null check
    ),
    // New Command: Switch Language
    _createCommand(
      id: 'switch_language',
      label: 'Switch Language',
      icon: Icons.language,
      defaultPosition: CommandPosition.pluginToolbar,
      execute: (ref, ctrl) => _showLanguageSelectionDialog(ref),
      canExecute: (ref, ctrl) => _getTab(ref) is CodeEditorTab, // Only for code editor tabs
    ),
  ];

  Command _createCommand({
    required String id,
    required String label,
    required IconData icon,
    required CommandPosition defaultPosition, // Added parameter
    required FutureOr<void> Function(WidgetRef, CodeLineEditingController?)
    execute,
    bool Function(WidgetRef, CodeLineEditingController?)? canExecute,
  }) {
    return BaseCommand(
      id: id,
      label: label,
      icon: Icon(icon, size: 20),
      defaultPosition: defaultPosition, // Pass the parameter
      sourcePlugin: this.runtimeType.toString(),
      execute: (ref) async {
        final ctrl = _getController(ref);
        await execute(ref, ctrl);
      },
      canExecute: (ref) {
        final ctrl = _getController(ref);
        return canExecute?.call(ref, ctrl) ?? true;
      },
    );
  }

  CodeLineEditingController? _getController(WidgetRef ref) {
    final tab = ref.read(sessionProvider).currentTab; // Use read instead of watch here to avoid unnecessary rebuilds if only getting controller
    return tab is CodeEditorTab ? tab.controller : null;
  }

  // Use watch for _getTab if its return value might trigger a rebuild based on tab changes,
  // but for command execution, _getController usually gets a *current* controller.
  CodeEditorTab? _getTab(WidgetRef ref) {
    final tab = ref.watch(sessionProvider).currentTab;
    return tab is CodeEditorTab ? tab : null;
  }

  // Command implementations
  Future<void> _toggleComments(
    WidgetRef ref,
    CodeLineEditingController? ctrl,
  ) async {
    if (ctrl == null) return; // Add null check
    final tab = _getTab(ref)!;
    final formatted = tab.commentFormatter.format(
      ctrl.value,
      ctrl.options.indent,
      true,
    );
    ctrl.runRevocableOp(() => ctrl.value = formatted);
  }

  Future<void> _reformatDocument(
    WidgetRef ref,
    CodeLineEditingController? ctrl,
  ) async {
    if (ctrl == null) return; // Add null check
    try {
      final formattedValue = _formatCodeValue(ctrl.value);

      ctrl.runRevocableOp(() {
        ctrl.value = formattedValue.copyWith(
          selection: const CodeLineSelection.zero(),
          composing: TextRange.empty,
        );
      });

      print('Document reformatted');
    } catch (e) {
      print('Formatting failed: ${e.toString()}');
    }
  }

  CodeLineEditingValue _formatCodeValue(CodeLineEditingValue value) {
    final buffer = StringBuffer();
    int indentLevel = 0;
    final indent = '  '; // 2 spaces

    // Convert CodeLines to a list for iteration
    final codeLines = value.codeLines.toList();

    for (final line in codeLines) {
      final trimmed = line.text.trim();

      // Handle indentation decreases
      if (trimmed.startsWith('}') ||
          trimmed.startsWith(']') ||
          trimmed.startsWith(')')) {
        indentLevel = indentLevel > 0 ? indentLevel - 1 : 0;
      }

      // Write indentation
      buffer.write(indent * indentLevel);

      // Write line content
      buffer.writeln(trimmed);

      // Handle indentation increases
      if (trimmed.endsWith('{') ||
          trimmed.endsWith('[') ||
          trimmed.endsWith('(')) {
        indentLevel++;
      }
    }

    return CodeLineEditingValue(
      codeLines: CodeLines.fromText(buffer.toString().trim()),
      selection: value.selection,
      composing: value.composing,
    );
  }

  Future<void> _selectBetweenBrackets(
    WidgetRef ref,
    CodeLineEditingController? ctrl,
  ) async {
    if (ctrl == null) return; // Add null check
    final controller = ctrl;
    final selection = controller.selection;

    if (!selection.isCollapsed) {
      print('Selection already active');
      return;
    }

    try {
      final position = selection.base;
      final brackets = {'(': ')', '[': ']', '{': '}'};
      CodeLinePosition? start;
      CodeLinePosition? end;

      // Check both left and right of cursor
      for (int offset = 0; offset <= 1; offset++) {
        final index = position.offset - offset;
        if (index >= 0 &&
            index < controller.codeLines[position.index].text.length) {
          final char = controller.codeLines[position.index].text[index];
          if (brackets.keys.contains(char) || brackets.values.contains(char)) {
            final match = _findMatchingBracket(
              controller.codeLines,
              CodeLinePosition(index: position.index, offset: index),
              brackets,
            );
            if (match != null) {
              start = CodeLinePosition(index: position.index, offset: index);
              end = match;
              break;
            }
          }
        }
      }

      if (start == null || end == null) {
        print('No matching bracket found');
        return;
      }

      // Order positions correctly
      final orderedStart = _comparePositions(start, end) < 0 ? start : end;
      final orderedEnd = _comparePositions(start, end) < 0 ? end : start;

      controller.selection = CodeLineSelection(
        baseIndex: orderedStart.index,
        baseOffset: orderedStart.offset,
        extentIndex: orderedEnd.index,
        extentOffset: orderedEnd.offset + 1, // Include the bracket itself
      );
      _extendSelection(ref, ctrl);
      //_showSuccess('Selected between brackets');
    } catch (e) {
      //_showError('Selection failed: ${e.toString()}');
    }
  }

  CodeLinePosition? _findMatchingBracket(
    CodeLines codeLines,
    CodeLinePosition position,
    Map<String, String> brackets,
  ) {
    final line = codeLines[position.index].text;
    final char = line[position.offset];

    // Determine if we're looking at an opening or closing bracket
    final isOpen = brackets.keys.contains(char);
    final target =
        isOpen
            ? brackets[char]
            : brackets.keys.firstWhere(
              (k) => brackets[k] == char,
              orElse: () => '',
            );

    if (target?.isEmpty ?? true) return null;

    int stack = 1;
    int index = position.index;
    int offset = position.offset;
    final direction = isOpen ? 1 : -1;

    while (index >= 0 && index < codeLines.length) {
      final currentLine = codeLines[index].text;

      while (offset >= 0 && offset < currentLine.length) {
        // Skip the original position
        if (index == position.index && offset == position.offset) {
          offset += direction;
          continue;
        }

        final currentChar = currentLine[offset];

        if (currentChar == char) {
          stack += 1;
        } else if (currentChar == target) {
          stack -= 1;
        }

        if (stack == 0) {
          return CodeLinePosition(index: index, offset: offset);
        }

        offset += direction;
      }

      // Move to next/previous line
      index += direction;
      offset = direction > 0 ? 0 : (codeLines[index].text.length - 1);
    }

    return null; // No matching bracket found
  }

  Future<void> _extendSelection(
    WidgetRef ref,
    CodeLineEditingController? ctrl,
  ) async {
    if (ctrl == null) return; // Add null check
    final controller = ctrl;
    final selection = controller.selection;

    final newBaseOffset = 0;
    final baseLineLength =
        controller.codeLines[selection.baseIndex].text.length;
    final extentLineLength =
        controller.codeLines[selection.extentIndex].text.length;
    final newExtentOffset = extentLineLength;

    controller.selection = CodeLineSelection(
      baseIndex: selection.baseIndex,
      baseOffset: newBaseOffset,
      extentIndex: selection.extentIndex,
      extentOffset: newExtentOffset,
    );
  }

  Future<void> _setMarkPosition(
    WidgetRef ref,
    CodeLineEditingController? ctrl,
  ) async {
    if (ctrl == null) return; // Add null check
    ref.read(markProvider.notifier).state = ctrl.selection.base;
  }

  Future<void> _selectToMark(
    WidgetRef ref,
    CodeLineEditingController? ctrl,
  ) async {
    if (ctrl == null) return; // Add null check
    final mark = ref.read(markProvider);
    if (mark == null) {
      print('No mark set! Set a mark first');
      return;
    }

    try {
      final currentPosition = ctrl.selection.base;
      final start =
          _comparePositions(mark!, currentPosition) < 0
              ? mark!
              : currentPosition;
      final end =
          _comparePositions(mark!, currentPosition) < 0
              ? currentPosition
              : mark!;

      ctrl.selection = CodeLineSelection(
        baseIndex: start.index,
        baseOffset: start.offset,
        extentIndex: end.index,
        extentOffset: end.offset,
      );

      //_showSuccess('Selected from line ${start.index + 1} to ${end.index + 1}');
    } catch (e) {
      print('Selection error: ${e.toString()}');
    }
  }

  int _comparePositions(CodeLinePosition a, CodeLinePosition b) {
    if (a.index < b.index) return -1;
    if (a.index > b.index) return 1;
    return a.offset.compareTo(b.offset);
  }

  @override
  Widget buildToolbar(WidgetRef ref) {
    // The commands are retrieved and displayed in BottomToolbar
    return CodeEditorTapRegion(child: BottomToolbar());
  }

  // --- New Language Highlighting Logic ---

  // Changed to static final because `langDart` etc. are not const.
  static final Map<String, dynamic> _languageNameToModeMap = {
    'dart': langDart,
    'python': langPython,
    'javascript': langJavascript,
    'typescript': langTypescript,
    'java': langJava,
    'cpp': langCpp,
    'latex': langLatex,
    'css': langCss,
    'json': langJson,
    'yaml': langYaml,
    'markdown': langMarkdown,
    'kotlin': langKotlin,
    'bash': langBash,
    'xml': langXml,
    'plaintext': langPlaintext,
  };

  static const Map<String, String> _languageExtToNameMap = {
    'dart': 'dart',
    'js': 'javascript',
    'jsx': 'javascript',
    'mjs': 'javascript',
    'npmrc': 'javascript',
    'ts': 'typescript',
    'py': 'python',
    'java': 'java',
    'cpp': 'cpp',
    'cc': 'cpp',
    'h': 'cpp',
    'css': 'css',
    'kt': 'kotlin',
    'json': 'json',
    'htm': 'xml',
    'html': 'xml',
    'yaml': 'yaml',
    'yml': 'yaml',
    'md': 'markdown',
    'sh': 'bash',
    'tex': 'latex',
    'gitignore': 'plaintext',
    'txt': 'plaintext',
    // Add more mappings as needed. Default will be plaintext.
  };

  String _inferLanguageKey(String uri) {
    final ext = uri.split('.').last.toLowerCase();
    return _languageExtToNameMap[ext] ?? 'plaintext';
  }

  static Map<String, CodeHighlightThemeMode> getHighlightThemeMode(String? langKey) {
    final effectiveLangKey = langKey ?? 'plaintext'; // Fallback to plaintext if null
    final mode = _languageNameToModeMap[effectiveLangKey];
    if (mode != null) {
      return {effectiveLangKey: CodeHighlightThemeMode(mode: mode)};
    }
    // If a specific key is requested but not found, default to plaintext
    return {'plaintext': CodeHighlightThemeMode(mode: langPlaintext)};
  }

  Future<void> _showLanguageSelectionDialog(WidgetRef ref) async {
    final BuildContext? context = ref.context; // Get context from ref

    if (context == null) {
      print('Cannot show dialog, context is null.');
      return;
    }

    final selectedLanguageKey = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Select Language'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _languageNameToModeMap.keys.length,
              itemBuilder: (context, index) {
                final langKey = _languageNameToModeMap.keys.elementAt(index);
                return ListTile(
                  title: Text(_formatLanguageName(langKey)),
                  onTap: () => Navigator.pop(ctx, langKey),
                );
              },
            ),
          ),
        );
      },
    );

    if (selectedLanguageKey != null) {
      final sessionNotifier = ref.read(sessionProvider.notifier);
      final currentTabIndex = ref.read(sessionProvider).currentTabIndex;
      sessionNotifier.updateTabLanguageKey(currentTabIndex, selectedLanguageKey);
    }
  }

  String _formatLanguageName(String key) {
    // Simple formatting for display, e.g., 'cpp' -> 'C++', 'javascript' -> 'JavaScript'
    if (key == 'cpp') return 'C++';
    if (key == 'javascript') return 'JavaScript';
    if (key == 'typescript') return 'TypeScript';
    if (key == 'markdown') return 'Markdown';
    if (key == 'kotlin') return 'Kotlin';
    return key[0].toUpperCase() + key.substring(1);
  }
}

class CodeEditorMachine extends ConsumerStatefulWidget {
  final CodeLineEditingController controller;
  final CodeEditorStyle? style;
  final CodeCommentFormatter? commentFormatter;
  final CodeIndicatorBuilder? indicatorBuilder;
  final bool? wordWrap;
  // REMOVED: final String? languageKey; // No longer passed as prop, will be watched internally

  const CodeEditorMachine({
    super.key,
    required this.controller,
    this.style,
    this.commentFormatter,
    this.indicatorBuilder,
    this.wordWrap,
    // REMOVED: this.languageKey,
  });

  @override
  ConsumerState<CodeEditorMachine> createState() => _CodeEditorMachineState();
}

class _CodeEditorMachineState extends ConsumerState<CodeEditorMachine> {
  late final FocusNode _focusNode;
  late final Map<LogicalKeyboardKey, AxisDirection> _arrowKeyDirections;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);

    _arrowKeyDirections = {
      LogicalKeyboardKey.arrowUp: AxisDirection.up,
      LogicalKeyboardKey.arrowDown: AxisDirection.down,
      LogicalKeyboardKey.arrowLeft: AxisDirection.left,
      LogicalKeyboardKey.arrowRight: AxisDirection.right,
    };

    _addControllerListeners(widget.controller);
    _updateAllStatesFromController();
  }

  @override
  void didUpdateWidget(CodeEditorMachine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _removeControllerListeners(oldWidget.controller);
      _addControllerListeners(widget.controller);
      _updateAllStatesFromController();
    }
    // No explicit handling for languageKey here;
    // the `ref.watch` in `build` will handle it.
  }

  @override
  void dispose() {
    _removeControllerListeners(widget.controller);
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _updateAllStatesFromController() {
    ref.read(canUndoProvider.notifier).state = widget.controller.canUndo;
    ref.read(canRedoProvider.notifier).state = widget.controller.canRedo;
    ref.read(bracketHighlightProvider.notifier).handleBracketHighlight();
  }

  void _handleControllerChange() {
    ref.read(sessionProvider.notifier).markCurrentTabDirty();
    _updateAllStatesFromController();
  }

  void _addControllerListeners(CodeLineEditingController controller) {
    controller.addListener(_handleControllerChange);
  }

  void _removeControllerListeners(CodeLineEditingController controller) {
    controller.removeListener(_handleControllerChange);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return KeyEventResult.ignored;

    final direction = _arrowKeyDirections[event.logicalKey];
    final shiftPressed = event.isShiftPressed;

    if (direction != null) {
      if (shiftPressed) {
        widget.controller.extendSelection(direction);
      } else {
        widget.controller.moveCursor(direction);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handleFocusChange(){
    if (_focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 300), () {
          widget.controller.makeCursorVisible();
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // WATCH the current tab's languageKey here!
    final currentLanguageKey = ref.watch(sessionProvider.select(
      (s) => (s.currentTab is CodeEditorTab) ? (s.currentTab as CodeEditorTab).languageKey : null,
    ));

    return Focus(
      autofocus: false,
      canRequestFocus: true,
      onFocusChange: (bool focus) => _handleFocusChange(),
      onKey: (n, e) => _handleKeyEvent(n, e),
      child: CodeEditor(
        controller: widget.controller,
        style: widget.style?.copyWith(
          codeTheme: CodeHighlightTheme(
            theme: atomOneDarkTheme,
            // Use the watched language key to get the theme mode
            languages: CodeEditorPlugin.getHighlightThemeMode(currentLanguageKey),
          ),
        ),
        commentFormatter: widget.commentFormatter,
        indicatorBuilder: widget.indicatorBuilder,
        wordWrap: widget.wordWrap,
        focusNode: _focusNode,
      ),
    );
  }
}


// --------------------
//  Bracket Highlight State
// --------------------

class BracketHighlightState {
  final Set<CodeLinePosition> bracketPositions;
  final CodeLinePosition? matchingBracketPosition;
  final Set<int> highlightedLines;

  BracketHighlightState({
    this.bracketPositions = const {},
    this.matchingBracketPosition,
    this.highlightedLines = const {},
  });
}

class BracketHighlightNotifier extends Notifier<BracketHighlightState> {
  @override
  BracketHighlightState build() {
    return BracketHighlightState();
  }

  void handleBracketHighlight() {
    final currentTab = ref.read(sessionProvider).currentTab as CodeEditorTab;
    final controller = currentTab.controller;
    final selection = controller.selection;
    if (!selection.isCollapsed) {
      state = BracketHighlightState();
      return;
    }
    final position = selection.base;
    final brackets = {'(': ')', '[': ']', '{': '}'};
    final line = controller.codeLines[position.index].text;

    Set<CodeLinePosition> newPositions = {};
    CodeLinePosition? matchPosition;
    Set<int> newHighlightedLines = {};

    final index = position.offset;
    if (index >= 0 && index < line.length) {
      final char = line[index];
      if (brackets.keys.contains(char) || brackets.values.contains(char)) {
        matchPosition = _findMatchingBracket(
          controller.codeLines,
          position,
          brackets,
        );
        if (matchPosition != null) {
          newPositions.add(position);
          newPositions.add(matchPosition);
          newHighlightedLines.add(position.index);
          newHighlightedLines.add(matchPosition.index);
        }
      }
    }
    //print("highlighting for realsies "+newPositions.toString());

    state = BracketHighlightState(
      bracketPositions: newPositions,
      matchingBracketPosition: matchPosition,
      highlightedLines: newHighlightedLines,
    );
  }

  CodeLinePosition? _findMatchingBracket(
    CodeLines codeLines,
    CodeLinePosition position,
    Map<String, String> brackets,
  ) {
    final line = codeLines[position.index].text;
    final char = line[position.offset];

    // Determine if we're looking at an opening or closing bracket
    final isOpen = brackets.keys.contains(char);
    final target =
        isOpen
            ? brackets[char]
            : brackets.keys.firstWhere(
              (k) => brackets[k] == char,
              orElse: () => '',
            );

    if (target?.isEmpty ?? true) return null;

    int stack = 1;
    int index = position.index;
    int offset = position.offset;
    final direction = isOpen ? 1 : -1;

    while (index >= 0 && index < codeLines.length) {
      final currentLine = codeLines[index].text;

      while (offset >= 0 && offset < currentLine.length) {
        // Skip the original position
        if (index == position.index && offset == position.offset) {
          offset += direction;
          continue;
        }

        final currentChar = currentLine[offset];

        if (currentChar == char) {
          stack += 1;
        } else if (currentChar == target) {
          stack -= 1;
        }

        if (stack == 0) {
          return CodeLinePosition(index: index, offset: offset);
        }

        offset += direction;
      }

      // Move to next/previous line
      index += direction;
      offset = direction > 0 ? 0 : (codeLines[index].text.length - 1);
    }

    return null; // No matching bracket found
  }
}

// --------------------
//  Custom Line Number Widget
// --------------------

class _CustomEditorIndicator extends ConsumerWidget {
  final CodeLineEditingController controller;
  final CodeChunkController chunkController;
  final CodeIndicatorValueNotifier notifier;

  const _CustomEditorIndicator({
    required this.controller,
    required this.chunkController,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highlightState = ref.watch(bracketHighlightProvider);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // Absorb taps
      child: Row(
        children: [
          _CustomLineNumberWidget(
            controller: controller,
            notifier: notifier,
            highlightedLines: highlightState.highlightedLines,
          ),
          DefaultCodeChunkIndicator(
            width: 20,
            controller: chunkController,
            notifier: notifier,
          ),
        ],
      ),
    );
  }
}

class _CustomLineNumberWidget extends ConsumerWidget {
  final CodeLineEditingController controller;
  final CodeIndicatorValueNotifier notifier;
  final Set<int> highlightedLines;

  const _CustomLineNumberWidget({
    required this.controller,
    required this.notifier,
    required this.highlightedLines,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ValueListenableBuilder<CodeIndicatorValue?>(
      valueListenable: notifier,
      builder: (context, value, child) {
        return DefaultCodeLineNumber(
          controller: controller,
          notifier: notifier,
          textStyle: TextStyle(
            color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
            fontSize: 12,
          ),
          focusedTextStyle: TextStyle(
            color: theme.colorScheme.secondary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
          customLineIndex2Text: (index) {
            final lineNumber = (index + 1).toString();
            return highlightedLines.contains(index)
                ? '➤$lineNumber'
                : lineNumber;
          },
        );
      },
    );
  }
}

// --------------------
//  Code Editor Settings
// --------------------
class CodeEditorSettings extends PluginSettings {
  bool wordWrap;
  double fontSize;
  String fontFamily;

  CodeEditorSettings({
    this.wordWrap = false,
    this.fontSize = 14,
    this.fontFamily = 'JetBrainsMono',
  });

  @override
  Map<String, dynamic> toJson() => {
    'wordWrap': wordWrap,
    'fontSize': fontSize,
    'fontFamily': fontFamily,
  };

  @override
  void fromJson(Map<String, dynamic> json) {
    wordWrap = json['wordWrap'] ?? false;
    fontSize = json['fontSize']?.toDouble() ?? 14;
    fontFamily = json['fontFamily'] ?? 'JetBrainsMono';
  }

  CodeEditorSettings copyWith({
    bool? wordWrap,
    double? fontSize,
    String? fontFamily,
  }) {
    return CodeEditorSettings(
      wordWrap: wordWrap ?? this.wordWrap,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }
}

class CodeEditorSettingsUI extends ConsumerStatefulWidget {
  final CodeEditorSettings settings;

  const CodeEditorSettingsUI({super.key, required this.settings});

  @override
  ConsumerState<CodeEditorSettingsUI> createState() =>
      _CodeEditorSettingsUIState();
}

class _CodeEditorSettingsUIState extends ConsumerState<CodeEditorSettingsUI> {
  late CodeEditorSettings _currentSettings;

  @override
  void initState() {
    super.initState();
    _currentSettings = widget.settings;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Word Wrap'),
          value: _currentSettings.wordWrap,
          onChanged:
              (value) =>
                  _updateSettings(_currentSettings.copyWith(wordWrap: value)),
        ),
        Slider(
          value: _currentSettings.fontSize,
          min: 8,
          max: 24,
          divisions: 16,
          label: 'Font Size: ${_currentSettings.fontSize.round()}',
          onChanged:
              (value) =>
                  _updateSettings(_currentSettings.copyWith(fontSize: value)),
        ),
        DropdownButtonFormField<String>(
          value: _currentSettings.fontFamily,
          items: const [
            DropdownMenuItem(
              value: 'JetBrainsMono',
              child: Text('JetBrains Mono'),
            ),
            DropdownMenuItem(value: 'FiraCode', child: Text('Fira Code')),
            // DropdownMenuItem(value: 'SourceSans3', child: Text('Source Sans')),
            DropdownMenuItem(value: 'RobotoMono', child: Text('Roboto Mono')),
          ],
          onChanged:
              (value) =>
                  _updateSettings(_currentSettings.copyWith(fontFamily: value)),
        ),
      ],
    );
  }

  // In _CodeEditorSettingsUIState
  void _updateSettings(CodeEditorSettings newSettings) {
    setState(() => _currentSettings = newSettings);
    ref.read(settingsProvider.notifier).updatePluginSettings(newSettings);
  }
}

// --------------------
//   Settings Screen
// --------------------

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _buildPluginSettingsList(context, ref),
    );
  }

  Widget _buildPluginSettingsList(BuildContext context, WidgetRef ref) {
    final plugins = ref.watch(activePluginsProvider);
    final settings = ref.watch(settingsProvider);

    return ListView(
      children: [
        // Add a tile for command settings
        ListTile(
          leading: const Icon(Icons.keyboard),
          title: const Text('Command Customization'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.pushNamed(context, '/command-settings'),
        ),
        // Existing plugin settings
        ...plugins
            .where((p) => p.settings != null)
            .map(
              (plugin) => _PluginSettingsCard(
                plugin: plugin,
                settings: settings.pluginSettings[plugin.settings.runtimeType]!,
              ),
            ),
      ],
    );
  }
}

class _PluginSettingsCard extends ConsumerWidget {
  final EditorPlugin plugin;
  final PluginSettings settings;

  const _PluginSettingsCard({required this.plugin, required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                plugin.icon,
                const SizedBox(width: 12),
                Text(
                  plugin.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSettingsWithErrorHandling(),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsWithErrorHandling() {
    try {
      return plugin.buildSettingsUI(settings);
    } catch (e) {
      return Text('Error loading settings: ${e.toString()}');
    }
  }
}

// --------------------
//   Editor Content
// --------------------

class EditorContentSwitcher extends ConsumerWidget {
  const EditorContentSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUri = ref.watch(
      sessionProvider.select((s) => s.currentTab?.file.uri),
    );

    return KeyedSubtree(
      key: ValueKey(currentUri),
      child: _EditorContentProxy(),
    );
  }
}

class _EditorContentProxy extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.read(sessionProvider).currentTab;
    return tab != null ? tab.plugin.buildEditor(tab, ref) : const SizedBox();
  }
}

class FileTypeIcon extends ConsumerWidget {
  final DocumentFile file;

  const FileTypeIcon({super.key, required this.file});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plugins = ref.watch(activePluginsProvider);
    final plugin = plugins.firstWhereOrNull((p) => p.supportsFile(file));

    return plugin?.icon ?? const Icon(Icons.insert_drive_file);
  }
}

// --------------------
//   Directory view
// --------------------

class _DirectoryView extends ConsumerWidget {
  final DocumentFile directory;
  final Function(DocumentFile) onOpenFile;
  final int depth;

  const _DirectoryView({
    required this.directory,
    required this.onOpenFile,
    this.depth = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentsAsync = ref.watch(directoryContentsProvider(directory.uri));

    return contentsAsync.when(
      loading: () => _buildLoadingState(),
      error: (error, _) => _buildErrorState(),
      data: (contents) => _buildDirectoryList(contents),
    );
  }

  Widget _buildDirectoryList(List<DocumentFile> contents) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      itemCount: contents.length,
      itemBuilder:
          (context, index) => _DirectoryItem(
            item: contents[index],
            onOpenFile: onOpenFile,
            depth: depth,
          ),
    );
  }

  Widget _buildLoadingState() {
    return ListView(
      shrinkWrap: true,
      children: [_DirectoryLoadingTile(depth: depth)],
    );
  }

  Widget _buildErrorState() {
    return ListView(
      shrinkWrap: true,
      children: const [
        ListTile(
          leading: Icon(Icons.error, color: Colors.red),
          title: Text('Error loading directory'),
        ),
      ],
    );
  }
}

class _DirectoryItem extends StatelessWidget {
  final DocumentFile item;
  final Function(DocumentFile) onOpenFile;
  final int depth;

  const _DirectoryItem({
    required this.item,
    required this.onOpenFile,
    required this.depth,
  });

  @override
  Widget build(BuildContext context) {
    if (item.isDirectory) {
      return _DirectoryExpansionTile(
        file: item,
        depth: depth,
        onOpenFile: onOpenFile,
      );
    }
    return _FileItem(file: item, depth: depth, onTap: () => onOpenFile(item));
  }
}

class _DirectoryExpansionTile extends ConsumerStatefulWidget {
  final DocumentFile file;
  final int depth;
  final Function(DocumentFile) onOpenFile;

  const _DirectoryExpansionTile({
    required this.file,
    required this.depth,
    required this.onOpenFile,
  });

  @override
  ConsumerState<_DirectoryExpansionTile> createState() =>
      _DirectoryExpansionTileState();
}

class _DirectoryExpansionTileState
    extends ConsumerState<_DirectoryExpansionTile> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: Icon(
        _isExpanded ? Icons.folder_open : Icons.folder,
        color: Colors.yellow,
      ),
      title: Text(widget.file.name),
      childrenPadding: EdgeInsets.only(left: (widget.depth + 1) * 16.0),
      onExpansionChanged: (expanded) => setState(() => _isExpanded = expanded),
      children: [
        _DirectoryView(
          directory: widget.file,
          onOpenFile: widget.onOpenFile,
          depth: widget.depth + 1,
        ),
      ],
    );
  }
}

class _FileItem extends StatelessWidget {
  final DocumentFile file;
  final int depth;
  final VoidCallback onTap;

  const _FileItem({
    required this.file,
    required this.depth,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.only(left: (depth + 1) * 16.0),
      leading: const Icon(Icons.insert_drive_file),
      title: Text(file.name),
      onTap: onTap,
    );
  }
}

class _DirectoryLoadingTile extends StatelessWidget {
  final int depth;

  const _DirectoryLoadingTile({required this.depth});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: (depth + 1) * 16.0),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

// --------------------
//      Tab Widget
// --------------------

// --------------------
//    File Explorer
// --------------------

class UnsupportedFileType implements Exception {
  final String uri;
  UnsupportedFileType(this.uri);

  @override
  String toString() => 'Unsupported file type: $uri';
}

class PluginSelectionDialog extends StatelessWidget {
  final List<EditorPlugin> plugins;

  const PluginSelectionDialog({super.key, required this.plugins});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Open With'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: plugins.map((plugin) {
            return ListTile(
              leading: _getPluginIcon(plugin),
              title: Text(_getPluginName(plugin)),
              onTap: () => Navigator.pop(context, plugin),
            );
          }).toList(),
        ),
      ),
    );
  }

  String _getPluginName(EditorPlugin plugin) {
    // Implement logic to get plugin display name
    return plugin.runtimeType.toString().replaceAll('Plugin', '');
  }

  Widget _getPluginIcon(EditorPlugin plugin) {
    // Implement logic to get plugin icon
    return plugin.icon ?? const Icon(Icons.extension); // Default icon
  }
}

class FileExplorerDrawer extends ConsumerWidget {
  final DocumentFile? currentDir;

  const FileExplorerDrawer({super.key, this.currentDir});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Drawer(
      child: Column(
        children: [
          // Header with title and close
          AppBar(
            title: const Text('File Explorer'),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),

          // File operations header
          _FileOperationsHeader(),

          // Directory tree
          Expanded(
            child:
                currentDir == null
                    ? const Center(child: Text('No folder open'))
                    : _DirectoryView(
                      directory: currentDir!,
                      // Update the onOpenFile callback in FileExplorerDrawer's build method
                        onOpenFile: (file) async {
                          final plugins = ref.read(pluginRegistryProvider);
                          final supportedPlugins = plugins.where((p) => p.supportsFile(file)).toList();
                        
                          if (supportedPlugins.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('No available plugins support ${file.name}')),
                            );
                            return;
                          }
                        
                          if (supportedPlugins.length == 1) {
                            ref.read(sessionProvider.notifier).openFile(file, plugin:supportedPlugins.first);
                          } else {
                            final selectedPlugin = await showDialog<EditorPlugin>(
                              context: context,
                              builder: (context) => PluginSelectionDialog(plugins: supportedPlugins),
                            );
                            if (selectedPlugin != null) {
                              ref.read(sessionProvider.notifier).openFile(file, plugin: selectedPlugin);
                            }
                          }
                          Navigator.pop(context);
                        },
                    ),
          ),

          // Footer for additional operations
          _FileOperationsFooter(),
        ],
      ),
    );
  }
}

class _FileOperationsHeader extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ButtonBar(
        alignment: MainAxisAlignment.center,
        children: [
          FilledButton.icon(
            icon: const Icon(Icons.folder_open),
            label: const Text('Open Folder'),
            onPressed: () async {
              final pickedDir =
                  await ref.read(fileHandlerProvider).pickDirectory();
              if (pickedDir != null) {
                ref.read(rootUriProvider.notifier).state = pickedDir;
                ref.read(sessionProvider.notifier).changeDirectory(pickedDir);
                Navigator.pop(context);
              }
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.file_open),
            label: const Text('Open File'),
            onPressed: () async {
              final pickedFile = await ref.read(fileHandlerProvider).pickFile();
              if (pickedFile != null) {
                ref.read(sessionProvider.notifier).openFile(pickedFile);
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _FileOperationsFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(8.0),
      child: ButtonBar(
        children: [
          /* Add other operations here like:
          TextButton(
            child: Text('New Folder'),
            onPressed: () {},
          ),
          TextButton(
            child: Text('Upload File'),
            onPressed: () {},
          ),*/
        ],
      ),
    );
  }
}

// --------------------
//   Settings Core
// --------------------
abstract class PluginSettings {
  Map<String, dynamic> toJson();
  void fromJson(Map<String, dynamic> json);
}

class AppSettings {
  final Map<Type, PluginSettings> pluginSettings;

  AppSettings({required this.pluginSettings});

  AppSettings copyWith({Map<Type, PluginSettings>? pluginSettings}) {
    return AppSettings(pluginSettings: pluginSettings ?? this.pluginSettings);
  }
}

// --------------------
//  Settings Providers
// --------------------
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((
  ref,
) {
  final plugins = ref.watch(activePluginsProvider);
  return SettingsNotifier(plugins: plugins);
});

class SettingsNotifier extends StateNotifier<AppSettings> {
  final Set<EditorPlugin> _plugins;

  SettingsNotifier({required Set<EditorPlugin> plugins})
    : _plugins = plugins,
      super(AppSettings(pluginSettings: _getDefaultSettings(plugins))) {
    loadSettings();
  }

  static Map<Type, PluginSettings> _getDefaultSettings(
    Set<EditorPlugin> plugins,
  ) {
    return {
      for (final plugin in plugins)
        if (plugin.settings != null)
          plugin.settings.runtimeType: plugin.settings!,
    };
  }

  void updatePluginSettings(PluginSettings newSettings) {
    final updatedSettings = Map<Type, PluginSettings>.from(state.pluginSettings)
      ..[newSettings.runtimeType] = newSettings;

    state = state.copyWith(pluginSettings: updatedSettings);
    _saveSettings();
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsMap = state.pluginSettings.map(
        (type, settings) => MapEntry(type.toString(), settings.toJson()),
      );
      await prefs.setString('app_settings', jsonEncode(settingsMap));
    } catch (e) {
      print('Error saving settings: $e');
    }
  }

  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString('app_settings');

      if (settingsJson != null) {
        final decoded = jsonDecode(settingsJson) as Map<String, dynamic>;
        final newSettings = Map<Type, PluginSettings>.from(
          state.pluginSettings,
        );

        for (final entry in decoded.entries) {
          try {
            final plugin = _plugins.firstWhere(
              (p) => p.settings.runtimeType.toString() == entry.key,
            );
            plugin.settings!.fromJson(entry.value);
            newSettings[plugin.settings.runtimeType] = plugin.settings!;
          } catch (e) {
            print('Error loading settings for $entry: $e');
          }
        }

        state = state.copyWith(pluginSettings: newSettings);
      }
    } catch (e) {
      print('Error loading settings: $e');
    }
  }
}

// --------------------
//     File Handling
// --------------------

abstract class DocumentFile {
  String get uri;
  String get name;
  bool get isDirectory;
  int get size;
  DateTime get modifiedDate;
  String get mimeType;
}

abstract class FileHandler {
  Future<DocumentFile?> pickDirectory();
  Future<List<DocumentFile>> listDirectory(String? uri);
  Future<DocumentFile?> pickFile();
  Future<List<DocumentFile>> pickFiles();

  Future<String> readFile(String uri);
  Future<DocumentFile> writeFile(DocumentFile file, String content);
  Future<DocumentFile> createFile(String parentUri, String fileName);
  Future<void> deleteFile(String uri);

  Future<void> persistRootUri(String? uri);
  Future<String?> getPersistedRootUri();

  Future<String?> getMimeType(String uri);
  Future<DocumentFile?> getFileMetadata(String uri);
}

// --------------------
//  SAF Implementation
// --------------------
class CustomSAFDocumentFile implements DocumentFile {
  //  final CustomSAFDocumentFile _file;
  final SafDocumentFile _safFile;

  CustomSAFDocumentFile(this._safFile); // Accept SafDocumentFile

  @override
  String get uri => _safFile.uri;

  @override
  String get name => _safFile.name;

  @override
  bool get isDirectory => _safFile.isDir; // Match SAF package's property name

  @override
  int get size => _safFile.length; // SAF uses 'length' for size

  @override
  DateTime get modifiedDate =>
      DateTime.fromMillisecondsSinceEpoch(_safFile.lastModified);

  @override
  String get mimeType {
    if (_safFile.isDir) return 'inode/directory';
    final ext = name.split('.').lastOrNull?.toLowerCase();
    return _mimeTypes[ext] ?? 'application/octet-stream';
  }

  static const _mimeTypes = {
    'txt': 'text/plain',
    'dart': 'text/x-dart',
    'js': 'text/javascript',
    // ... add more MIME types
  };
}

class SAFFileHandler implements FileHandler {
  final SafUtil _safUtil = SafUtil();
  final SafStream _safStream = SafStream();
  static const _prefsKey = 'saf_root_uri';

  SAFFileHandler();

  @override
  Future<DocumentFile?> pickDirectory() async {
    final dir = await _safUtil.pickDirectory(persistablePermission: true, writePermission: true,);
    return dir != null ? CustomSAFDocumentFile(dir) : null;
  }

  /* @override
  Future<List<DocumentFile>> listDirectory(String? uri) async {
    try {
      final contents = await _safUtil.list(uri ?? '');

      contents.sort((a, b) {
        if (a.isDir != b.isDir) {
          return a.isDir ? -1 : 1;
        }

        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      return contents.map((f) => CustomSAFDocumentFile(f)).toList();
    } catch (e) {
      print('Error listing directory: $e');
      return [];
    }
  }*/

  @override
  Future<List<DocumentFile>> listDirectory(String? uri) async {
    try {
      if (uri == null) return [];
      final files = await _safUtil.list(uri);
      files.sort((a, b) {
        if (a.isDir != b.isDir) {
          return a.isDir ? -1 : 1;
        }

        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return files.map((f) => CustomSAFDocumentFile(f)).toList();
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        await persistRootUri(null);
        return [];
      }
      rethrow;
    }
  }

  @override
  Future<String> readFile(String uri) async {
    final bytes = await _safStream.readFileBytes(uri);
    return utf8.decode(bytes);
  }

  @override
  Future<DocumentFile> writeFile(DocumentFile file, String content) async {
    // Write file using SAF
    final treeAndFile = splitTreeAndFileUri(file);
    print(treeAndFile);
    final result = await _safStream.writeFileBytes(
      treeAndFile.treeUri, // Parent directory URI
      file.name, // Original file name
      file.mimeType,
      Uint8List.fromList(utf8.encode(content)),
      overwrite: true,
    );

    // Get updated document metadata
    final newFile = await _safUtil.documentFileFromUri(
      result.uri.toString(),
      false,
    );

    return CustomSAFDocumentFile(newFile!);
  }

  @override
  Future<DocumentFile> createFile(String parentUri, String fileName) async {
    final file = await _safUtil.child(parentUri, [fileName]);
    if (file == null) {
      final created = await _safUtil.mkdirp(parentUri, [fileName]);
      return CustomSAFDocumentFile(created!);
    }
    return CustomSAFDocumentFile(file);
  }

  @override
  Future<void> deleteFile(String uri) async {
    await _safUtil.delete(uri, false);
  }

  @override
  Future<void> persistRootUri(String? uri) async {
    if (true) return;
    if (uri != null) {
      // Take persistable permissions
      await _safUtil.pickDirectory(
        initialUri: uri,
        persistablePermission: true,
        writePermission: true,
      );
    }
  }

  @override
  Future<String?> getPersistedRootUri() async {
    final prefs = await SharedPreferences.getInstance();
    final uri = prefs.getString(_prefsKey);
    if (uri == null) return null;

    // Verify we still have access
    final file = await _safUtil.documentFileFromUri(uri, true);
    return file?.uri;
  }

  @override
  Future<String?> getMimeType(String uri) async {
    final file = await _safUtil.documentFileFromUri(uri, false);
    return file != null ? CustomSAFDocumentFile(file).mimeType : null;
  }

  @override
  Future<DocumentFile?> getFileMetadata(String uri) async {
    final file = await _safUtil.documentFileFromUri(uri, false);
    return file != null ? CustomSAFDocumentFile(file) : null;
  }

  @override
  Future<DocumentFile?> pickFile() async {
    final file = await _safUtil.pickFile();
    return file != null ? CustomSAFDocumentFile(file) : null;
  }


  ({String treeUri/*, String fileUri, String relativePath*/}) splitTreeAndFileUri(DocumentFile docFile) {
  // Extract the Tree URI (everything before '/document/')
  final fullUri = docFile.uri;
  final documentIndex = fullUri.lastIndexOf('%2F');
  if (documentIndex == -1) {
    throw ArgumentError("Invalid URI format: '/document/' not found.");
  }

  final treeUri = fullUri.substring(0, documentIndex);
  /*// Extract the File URI (everything after '/document/')
  final fileUri = fullUri.substring(documentIndex + '/document/'.length);
  
  // Extract the relative path (remove the repeated tree part if needed)
  final treePath = treeUri.substring(treeUri.indexOf('/tree/') + '/tree/'.length);
  String relativePath = fileUri;
  
  // If the fileUri starts with the same path as the treeUri, remove it
  if (fileUri.startsWith(treePath)) {
    relativePath = fileUri.substring(treePath.length);
  }*/
  
  return (treeUri: treeUri);
}

  @override
  Future<List<DocumentFile>> pickFiles() async {
    final files = await _safUtil.pickFiles();
    return files?.map((f) => CustomSAFDocumentFile(f)).toList() ?? [];
  }
}

// --------------------
//   Command System
// --------------------

abstract class Command {
  final String id;
  final String label;
  final Widget icon;
  final CommandPosition defaultPosition;
  final String sourcePlugin;

  const Command({
    required this.id,
    required this.label,
    required this.icon,
    required this.defaultPosition,
    required this.sourcePlugin,
  });

  Future<void> execute(WidgetRef ref);
  bool canExecute(WidgetRef ref);
}

class BaseCommand extends Command {
  final Future<void> Function(WidgetRef) _execute;
  final bool Function(WidgetRef) _canExecute;

  const BaseCommand({
    required super.id,
    required super.label,
    required super.icon,
    required super.defaultPosition,
    required super.sourcePlugin,
    required Future<void> Function(WidgetRef) execute,
    required bool Function(WidgetRef) canExecute,
  }) : _execute = execute,
       _canExecute = canExecute;

  @override
  Future<void> execute(WidgetRef ref) => _execute(ref);

  @override
  bool canExecute(WidgetRef ref) => _canExecute(ref);
}

enum CommandPosition { appBar, pluginToolbar, both, hidden }

class CommandState {
  final List<String> appBarOrder;
  final List<String> pluginToolbarOrder;
  final List<String> hiddenOrder;
  final Map<String, Set<String>> commandSources;

  const CommandState({
    this.appBarOrder = const [],
    this.pluginToolbarOrder = const [],
    this.hiddenOrder = const [],
    this.commandSources = const {},
  });

  CommandState copyWith({
    List<String>? appBarOrder,
    List<String>? pluginToolbarOrder,
    List<String>? hiddenOrder,
    Map<String, Set<String>>? commandSources,
  }) {
    return CommandState(
      appBarOrder: appBarOrder ?? this.appBarOrder,
      pluginToolbarOrder: pluginToolbarOrder ?? this.pluginToolbarOrder,
      hiddenOrder: hiddenOrder ?? this.hiddenOrder,
      commandSources: commandSources ?? this.commandSources,
    );
  }

  List<String> getOrderForPosition(CommandPosition position) {
    switch (position) {
      case CommandPosition.appBar:
        return appBarOrder;
      case CommandPosition.pluginToolbar:
        return pluginToolbarOrder;
      case CommandPosition.hidden:
        return hiddenOrder;
      default:
        return [];
    }
  }
}

class CommandNotifier extends StateNotifier<CommandState> {
  final Ref ref;
  final List<Command> _coreCommands;
  final Map<String, Command> _allCommands = {};
  final Map<String, Set<String>> _commandSources = {};

  Command? getCommand(String id) => _allCommands[id];

  CommandNotifier({required this.ref, required Set<EditorPlugin> plugins})
    : _coreCommands = _buildCoreCommands(ref),
      super(const CommandState()) {
    _initializeCommands(plugins);
  }

  List<Command> getVisibleCommands(CommandPosition position) {
    final commands = switch (position) {
      CommandPosition.appBar => [
        ...state.appBarOrder,
        ...state.pluginToolbarOrder.where(
          (id) => _allCommands[id]?.defaultPosition == CommandPosition.both,
        ),
      ],
      CommandPosition.pluginToolbar => [
        ...state.pluginToolbarOrder,
        ...state.appBarOrder.where(
          (id) => _allCommands[id]?.defaultPosition == CommandPosition.both,
        ),
      ],
      _ => [],
    };

    return commands.map((id) => _allCommands[id]).whereType<Command>().toList();
  }

  static List<Command> _buildCoreCommands(Ref ref) => [
    /* BaseCommand(
      id: 'save',
      label: 'Save',
      icon: const Icon(Icons.save),
      defaultPosition: CommandPosition.appBar,
      sourcePlugin: 'Core',
      execute: (ref) => ref.read(sessionProvider.notifier).saveSession(),
      canExecute: (ref) => ref.watch(sessionProvider
          .select((s) => s.currentTab?.isDirty ?? false)),
    ),*/
  ];

  void updateOrder(CommandPosition position, List<String> newOrder) {
    switch (position) {
      case CommandPosition.appBar:
        state = state.copyWith(appBarOrder: newOrder);
        break;
      case CommandPosition.pluginToolbar:
        state = state.copyWith(pluginToolbarOrder: newOrder);
        break;
      case CommandPosition.hidden:
        state = state.copyWith(hiddenOrder: newOrder);
        break;
      case CommandPosition.both:
        // Handle both position if needed
        break;
    }
    _saveToPrefs();
  }

  void _initializeCommands(Set<EditorPlugin> plugins) async {
    // Merge commands from core and plugins
    final allCommands = [
      ..._coreCommands,
      ...plugins.expand((p) => p.getCommands()),
    ];

    for (final cmd in allCommands) {
      // Group by command ID
      if (_allCommands.containsKey(cmd.id)) {
        _commandSources[cmd.id]!.add(cmd.sourcePlugin);
      } else {
        _allCommands[cmd.id] = cmd;
        _commandSources[cmd.id] = {cmd.sourcePlugin};
      }
    }

    // Initial state setup
    state = CommandState(
      appBarOrder:
          _coreCommands
              .where((c) => c.defaultPosition == CommandPosition.appBar)
              .map((c) => c.id)
              .toList(),
      pluginToolbarOrder:
          _coreCommands
              .where((c) => c.defaultPosition == CommandPosition.pluginToolbar)
              .map((c) => c.id)
              .toList(),
      commandSources: _commandSources,
    );
    await _loadFromPrefs(
      plugins,
    ); // Load saved positions after merging commands
  }

  void updateCommandPosition(String commandId, CommandPosition newPosition) {
    List<String> newAppBar = List.from(state.appBarOrder);
    List<String> newPluginToolbar = List.from(state.pluginToolbarOrder);
    List<String> newHidden = List.from(state.hiddenOrder);

    newAppBar.remove(commandId);
    newPluginToolbar.remove(commandId);
    newHidden.remove(commandId);

    switch (newPosition) {
      case CommandPosition.appBar:
        newAppBar.add(commandId);
        break;
      case CommandPosition.pluginToolbar:
        newPluginToolbar.add(commandId);
        break;
      case CommandPosition.hidden:
        newHidden.add(commandId);
        break;
      case CommandPosition.both: // Handle both case
        newAppBar.add(commandId);
        newPluginToolbar.add(commandId);
        break;
    }

    state = state.copyWith(
      appBarOrder: newAppBar,
      pluginToolbarOrder: newPluginToolbar,
      hiddenOrder: newHidden,
    );
    _saveToPrefs();
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('command_app_bar', state.appBarOrder);
    await prefs.setStringList(
      'command_plugin_toolbar',
      state.pluginToolbarOrder,
    );
    await prefs.setStringList('command_hidden', state.hiddenOrder);
  }

  Future<void> _loadFromPrefs(Set<EditorPlugin> plugins) async {
    final prefs = await SharedPreferences.getInstance();
    final appBar = prefs.getStringList('command_app_bar') ?? [];
    final pluginToolbar = prefs.getStringList('command_plugin_toolbar') ?? [];
    final hidden = prefs.getStringList('command_hidden') ?? [];

    final allCommands =
        [
          ..._coreCommands,
          ...ref.read(activePluginsProvider).expand((p) => p.getCommands()),
        ].map((c) => c.id).toSet();

    // Merge saved positions with default positions for new commands
    state = state.copyWith(
      appBarOrder: _mergePosition(
        saved: appBar,
        defaultIds:
            allCommands
                .where(
                  (id) =>
                      _getCommand(id)?.defaultPosition ==
                      CommandPosition.appBar,
                )
                .toList(),
      ),
      pluginToolbarOrder: _mergePosition(
        saved: pluginToolbar,
        defaultIds:
            allCommands
                .where(
                  (id) =>
                      _getCommand(id)?.defaultPosition ==
                      CommandPosition.pluginToolbar,
                )
                .toList(),
      ),
      hiddenOrder: _mergePosition(
        saved: hidden,
        defaultIds:
            allCommands
                .where(
                  (id) =>
                      _getCommand(id)?.defaultPosition ==
                      CommandPosition.hidden,
                )
                .toList(),
      ),
    );
  }

  Command? _getCommand(String id) {
    return _allCommands[id];
  }

  List<String> _mergePosition({
    required List<String> saved,
    required List<String> defaultIds,
  }) {
    // 1. Start with saved commands that still exist
    final validSaved = saved.where((id) => _getCommand(id) != null).toList();

    // 2. Add default commands that weren't saved
    final newDefaults =
        defaultIds.where((id) => !validSaved.contains(id)).toList();

    // 3. Preserve saved order + append new defaults
    return [...validSaved, ...newDefaults];
  }
}

// --------------------
//   Toolbar Widgets
// --------------------

class AppBarCommands extends ConsumerWidget {
  const AppBarCommands({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commands = ref.watch(appBarCommandsProvider);

    return Row(
      children: commands.map((cmd) => CommandButton(command: cmd)).toList(),
    );
  }
}

class BottomToolbar extends ConsumerWidget {
  const BottomToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrollController = ref.watch(bottomToolbarScrollProvider);
    final commands = ref.watch(pluginToolbarCommandsProvider);

    return Container(
      height: 48,
      color: Colors.grey[900],
      child: ListView.builder(
        key: const PageStorageKey<String>('bottomToolbarScrollPosition'),
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        itemCount: commands.length,
        itemBuilder:
            (context, index) =>
                CommandButton(command: commands[index], showLabel: true),
      ),
    );
  }
}

class CommandButton extends ConsumerWidget {
  final Command command;
  final bool showLabel;

  const CommandButton({
    super.key,
    required this.command,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEnabled = command.canExecute(ref);

    return IconButton(
      icon: command.icon,
      onPressed: isEnabled ? () => command.execute(ref) : null,
      tooltip: showLabel ? null : command.label,
    );
  }
}

// --------------------
//   Settings UI
// --------------------

class CommandSettingsScreen extends ConsumerWidget {
  const CommandSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(commandProvider);
    final notifier = ref.read(commandProvider.notifier);
    print(
      'Current Command State: ${state.appBarOrder} | '
      '${state.pluginToolbarOrder} | ${state.hiddenOrder}',
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Command Customization')),
      body: ListView(
        shrinkWrap: true,
        children: [
          _buildSection(
            context,
            ref,
            'App Bar Commands',
            state.appBarOrder,
            CommandPosition.appBar,
          ),
          _buildSection(
            context,
            ref,
            'Plugin Toolbar Commands',
            state.pluginToolbarOrder,
            CommandPosition.pluginToolbar,
          ),
          _buildSection(
            context,
            ref,
            'Hidden Commands',
            state.hiddenOrder,
            CommandPosition.hidden,
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    WidgetRef ref,
    String title,
    List<String> commandIds,
    CommandPosition position,
  ) {
    final state = ref.watch(commandProvider);
    return ExpansionTile(
      title: Text(title),
      initiallyExpanded: true,
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: commandIds.length,
          itemBuilder:
              (ctx, index) => _buildCommandItem(
                context,
                ref,
                commandIds[index],
                state.commandSources[commandIds[index]]!,
              ),
          onReorder:
              (oldIndex, newIndex) =>
                  _handleReorder(ref, position, oldIndex, newIndex, commandIds),
        ),
      ],
    );
  }

  Widget _buildCommandItem(
    BuildContext context,
    WidgetRef ref,
    String commandId,
    Set<String> sources,
  ) {
    final notifier = ref.read(commandProvider.notifier);
    final command = notifier._allCommands[commandId]!;

    return ListTile(
      key: ValueKey(commandId),
      leading: command.icon,
      title: Text(command.label),
      subtitle: sources.length > 1 ? Text('From: ${sources.join(', ')}') : null,
      trailing: IconButton(
        icon: const Icon(Icons.more_vert),
        onPressed: () => _showPositionMenu(context, ref, command),
      ),
    );
  }

  void _handleReorder(
    WidgetRef ref,
    CommandPosition position,
    int oldIndex,
    int newIndex,
    List<String> currentOrder,
  ) {
    if (oldIndex < newIndex) newIndex--;
    final item = currentOrder.removeAt(oldIndex);
    currentOrder.insert(newIndex, item);

    ref.read(commandProvider.notifier).updateOrder(position, currentOrder);
  }

  void _showPositionMenu(BuildContext context, WidgetRef ref, Command command) {
    final notifier = ref.read(commandProvider.notifier);

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text('Position for ${command.label}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children:
                  CommandPosition.values
                      .map(
                        (pos) => ListTile(
                          title: Text(pos.toString().split('.').last),
                          onTap: () {
                            notifier.updateCommandPosition(command.id, pos);
                            Navigator.pop(ctx);
                          },
                        ),
                      )
                      .toList(),
            ),
          ),
    );
  }
}