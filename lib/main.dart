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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/cpp.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  //final pluginRegistry = {CodeEditorPlugin()};

  runApp(
    ProviderScope(
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: AppStartupWidget(onLoaded: (context) => const EditorScreen()),
        routes: {'/settings': (_) => const SettingsScreen()},
      ),
    ),
  );
}

// --------------------
//   Providers
// --------------------

/*final fileHandlerProvider = Provider<AndroidFileHandler>(
  (ref) => AndroidFileHandler(),
);*/
// Add this provider
final sharedPreferencesProvider = FutureProvider<SharedPreferences>((
  ref,
) async {
  return await SharedPreferences.getInstance();
});

// Update fileHandlerProvider
final fileHandlerProvider = Provider<FileHandler>((ref) {
  return SAFFileHandler();
});

final pluginRegistryProvider = Provider<Set<EditorPlugin>>(
  (_) => {
    CodeEditorPlugin(), // Default text editor
  },
);

final activePluginsProvider =
    StateNotifierProvider<PluginManager, Set<EditorPlugin>>((ref) {
      return PluginManager(ref.read(pluginRegistryProvider));
    });

final rootUriProvider = StateProvider<DocumentFile?>((_) => null);

// Update directoryContentsProvider
final directoryContentsProvider = FutureProvider.autoDispose
    .family<List<DocumentFile>, String?>((ref, uri) async {
      final handler = ref.read(fileHandlerProvider);
      final targetUri = uri ?? await handler.getPersistedRootUri();
      return targetUri != null ? handler.listDirectory(targetUri) : [];
    });

// 1. Business Logic Layer
final sessionManagerProvider = Provider<SessionManager>((ref) {
  return SessionManager(
    fileHandler: ref.watch(fileHandlerProvider),
    plugins: ref.watch(activePluginsProvider),
    prefs: ref.watch(sharedPreferencesProvider).requireValue,
  );
});

final sessionProvider = StateNotifierProvider<SessionNotifier, SessionState>((ref) {
  return SessionNotifier(
    manager: ref.watch(sessionManagerProvider),
  );
});

// --------------------
//        Startup
// --------------------
final appStartupProvider = FutureProvider<void>((ref) async {
  await appStartup(ref);
});

Future<void> appStartup(Ref ref) async {
  try {
    // Initialize SharedPreferences first
    final prefs = await ref.read(sharedPreferencesProvider.future);

    // Then load settings
    await ref.read(settingsProvider.notifier).loadSettings();



    await ref.read(sessionProvider.notifier).loadSession();

    // Initialize other dependencies if needed
    //await ref.read(fileHandlerProvider).initialize();
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
        // Load session after startup
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
  
  Map<String, dynamic> toJson() => {
    'tabs': tabs.map((t) => _tabToJson(t)).toList(),
    'currentIndex': currentTabIndex,
    'directory': currentDirectory?.uri,
  };

  static Future<SessionState> fromJson(Map<String, dynamic> json, Set<EditorPlugin> plugins, FileHandler fileHandler) async {
  final directoryUri = json['directory'];
  DocumentFile? directory;
  
  if (directoryUri != null) {
    directory = await fileHandler.getFileMetadata(directoryUri);
  }

  return SessionState(
    tabs: await _tabsFromJson(json['tabs'], plugins, fileHandler),
    currentTabIndex: json['currentIndex'] ?? 0,
    currentDirectory: directory,
  );
}

  static Map<String, dynamic> _tabToJson(EditorTab tab) => {
    'fileUri': tab.file.uri,
    'pluginType': tab.plugin.runtimeType.toString(),
  };

  static Future<List<EditorTab>> _tabsFromJson(List<dynamic> json, Set<EditorPlugin> plugins, FileHandler fileHandler) async {
  final tabs = <EditorTab>[];
  for (final item in json) {
    final tab = await _tabFromJson(item, plugins, fileHandler);
    if (tab != null) tabs.add(tab);
  }
  return tabs;
}

static Future<EditorTab?> _tabFromJson(
  Map<String, dynamic> json, 
  Set<EditorPlugin> plugins, 
  FileHandler fileHandler
) async {
  try {
    final file = await fileHandler.getFileMetadata(json['fileUri']);
    if (file == null) return null; // Add null check
    
    final plugin = plugins.firstWhere(
      (p) => p.runtimeType.toString() == json['pluginType'],
    );
    return plugin.createTab(file);
  } catch (e) {
    return null;
  }
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
  })  : _fileHandler = fileHandler,
        _plugins = plugins,
        _prefs = prefs;

  Future<SessionState> openFile(SessionState current, DocumentFile file) async {
    final existingIndex = current.tabs.indexWhere((t) => t.file.uri == file.uri);
    if (existingIndex != -1) return current.copyWith(currentTabIndex: existingIndex);

    final content = await _fileHandler.readFile(file.uri);
    final plugin = _plugins.firstWhere((p) => p.supportsFile(file));
    final tab = plugin.createTab(file);
    await plugin.initializeTab(tab, content);

    return current.copyWith(
      tabs: [...current.tabs, tab],
      currentTabIndex: current.tabs.length,
    );
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
      // Add actual deserialization implementation
      return SessionState.fromJson(data); // Implement proper fromJson
    } catch (e) {
      print('Session load error: $e');
      return const SessionState();
    }
  }  
  
 Future<void> saveSession(SessionState state) async {
    try {
      final json = _serializeState(state);
      await _prefs.setString('session', jsonEncode(json));
    } catch (e) {
      print('Session save error: $e');
    }
  }
}


// --------------------
//  Session Notifier
// --------------------

class SessionNotifier extends StateNotifier<SessionState> {
  final SessionManager _manager;

  SessionNotifier({required SessionManager manager})
      : _manager = manager,
        super(const SessionState());

  Future<void> loadSession() async {
    state = await _manager.loadSession();
  }

  Future<void> openFile(DocumentFile file) async {
    state = await _manager.openFile(state, file);
  }

  void switchTab(int index) {
    state = state.copyWith(currentTabIndex: index);
  }

  void closeTab(int index) {
    state = _manager.closeTab(state, index);
  }

  void reorderTabs(int oldIndex, int newIndex) {
    state = _manager.reorderTabs(state, oldIndex, newIndex);
  }

  Future<void> changeDirectory(DocumentFile directory) async {
    await _manager.persistDirectory(state);
    state = state.copyWith(currentDirectory: directory);
  }

  Future<void> saveSession() async {
    await _manager.saveSession(state);
    state = state.copyWith(lastSaved: DateTime.now());
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

  void dispose();
}

class CodeEditorTab extends EditorTab {
  final CodeLineEditingController controller;

  CodeEditorTab({
    required super.file,
    required this.controller,
    required super.plugin,
  });

  @override
  void dispose() => controller.dispose();
}

// --------------------
//      Tab Bar
// --------------------
class TabBarView extends ConsumerWidget {
  const TabBarView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.watch(sessionProvider.select((state) => state.tabs));

    return Container(
      color: Colors.grey[900],
      height: 40,
      child: ReorderableListView(
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
    final currentTab = ref.watch(
      sessionProvider.select((s) => s.currentTab), // Use sessionProvider
    );
    final currentDir = ref.watch(
      sessionProvider.select((s) => s.currentDirectory),
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
          // In EditorScreen's AppBar
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
        title: Text(currentTab != null ? currentTab.file.name : 'Code Editor'),
      ),
      drawer: FileExplorerDrawer(currentDir: currentDir),
      body: Column(
        children: [
          const TabBarView(),
          Expanded(
            child:
                currentTab != null
                    ? EditorContentSwitcher(tab: currentTab)
                    : const Center(child: Text('Open file')),
          ),
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

  // File type support
  bool supportsFile(DocumentFile file);

  // Tab management
  EditorTab createTab(DocumentFile file);
  Widget buildEditor(EditorTab tab, WidgetRef ref);

  PluginSettings? get settings;
  Widget buildSettingsUI(PluginSettings settings);

  // Optional lifecycle hooks
  Future<void> initializeTab(EditorTab tab, String? content);
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

  @override
  Future<void> initializeTab(EditorTab tab, String? content) async {
    if (tab is CodeEditorTab) {
      tab.controller.codeLines = CodeLines.fromText(content ?? '');
    }
  }

  @override
  Future<void> dispose() async {
    // Cleanup logic here
  }

  @override
  bool supportsFile(DocumentFile file) {
    final ext = file.name.split('.').last.toLowerCase();
    return const {
      'dart',
      'js',
      'ts',
      'py',
      'java',
      'kt',
      'cpp',
      'h',
      'cs',
      'html',
      'css',
      'xml',
      'json',
      'yaml',
      'md',
      'txt',
    }.contains(ext);
  }

  @override
  EditorTab createTab(DocumentFile file) => CodeEditorTab(
    file: file,
    plugin: this,
    controller: CodeLineEditingController(),
  );

  @override
  Widget buildEditor(EditorTab tab, WidgetRef ref) {
    final codeTab = tab as CodeEditorTab;
    final settings = ref.watch(
      settingsProvider.select(
        (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
      ),
    );

    return CodeEditor(
      controller: codeTab.controller,
      style: CodeEditorStyle(
        fontSize: settings?.fontSize ?? 12,
        fontFamily: settings?.fontFamily ?? "JetBrainsMono",
        codeTheme: CodeHighlightTheme(
          theme: atomOneDarkTheme,
          languages: _getLanguageMode(codeTab.file.uri),
        ),
      ),
      wordWrap: settings?.wordWrap ?? false,
    );
  }

  Map<String, CodeHighlightThemeMode> _getLanguageMode(String uri) {
    final extension = uri.split('.').last.toLowerCase();
    return {'dart': CodeHighlightThemeMode(mode: langDart)};
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

class CodeEditorSettingsUI extends StatefulWidget {
  final CodeEditorSettings settings;

  const CodeEditorSettingsUI({super.key, required this.settings});

  @override
  State<CodeEditorSettingsUI> createState() => _CodeEditorSettingsUIState();
}

class _CodeEditorSettingsUIState extends State<CodeEditorSettingsUI> {
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
    ProviderScope.containerOf(
      context,
    ).read(settingsProvider.notifier).updatePluginSettings(newSettings);
  }
}

// --------------------
//   Settings Screen
// --------------------

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plugins = ref.watch(activePluginsProvider);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body:
          plugins.isEmpty
              ? const Center(child: Text('No plugins available'))
              : ListView(
                children:
                    plugins
                        .where((p) => p.settings != null)
                        .map(
                          (plugin) => _PluginSettingsCard(
                            plugin: plugin,
                            settings:
                                settings.pluginSettings[plugin
                                    .settings
                                    .runtimeType]!,
                          ),
                        )
                        .toList(),
              ),
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
  final EditorTab tab;

  const EditorContentSwitcher({super.key, required this.tab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    try {
      return tab.plugin.buildEditor(tab, ref);
    } catch (e) {
      return ErrorWidget.withDetails(
        message: 'Failed to load editor: ${e.toString()}',
        error: FlutterError(e.toString()),
      );
    }
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
                      onOpenFile: (file) {
                        Navigator.pop(context);
                        ref.read(sessionProvider.notifier).openFile(file);
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
//     File Handlers
// --------------------
/*
class AndroidFileHandler {
  static const _channel = MethodChannel('com.example/file_handler');

  Future<bool> _requestPermissions() async {
    if (await Permission.storage.request().isGranted) {
      return true;
    }
    return await Permission.manageExternalStorage.request().isGranted;
  }

  Future<String?> openFile() async {
    if (!await _requestPermissions()) {
      throw Exception('Storage permission denied');
    }
    try {
      return await _channel.invokeMethod<String>('openFile');
    } on PlatformException catch (e) {
      print("Error opening file: ${e.message}");
      return null;
    }
  }

  Future<String?> openFolder() async {
    try {
      return await _channel.invokeMethod<String>('openFolder');
    } on PlatformException catch (e) {
      print("Error opening folder: ${e.message}");
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> listDirectory(
    String uri, {
    bool isRoot = false,
  }) async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'listDirectory',
        {'uri': uri, 'isRoot': isRoot},
      );
      return result?.map((e) => Map<String, dynamic>.from(e)).toList();
    } on PlatformException catch (e) {
      print("Error listing directory: ${e.message}");
      return null;
    }
  }

  Future<String?> readFile(String uri) async {
    try {
      final response = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'readFile',
        {'uri': uri},
      );

      final error = response?['error'];
      final isEmpty = response?['isEmpty'] ?? false;
      final content = response?['content'] as String?;

      if (error != null) {
        throw Exception(error);
      }

      if (isEmpty) {
        print('File is empty but opened successfully');
        return '';
      }

      return content;
    } on PlatformException catch (e) {
      throw Exception('Platform error: ${e.message}');
    }
  }

  Future<bool> writeFile(String uri, String content) async {
    try {
      final response = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'writeFile',
        {'uri': uri, 'content': content},
      );

      if (response?['success'] == true) {
        return true;
      }

      throw Exception(response?['error'] ?? 'Unknown write error');
    } on PlatformException catch (e) {
      throw Exception('Platform error: ${e.message}');
    }
  }
}

Map<String, CodeHighlightThemeMode> _getLanguageMode(String uri) {
  final extension = uri.split('.').last.toLowerCase();
  // Add your language mappings here
  return {'dart': CodeHighlightThemeMode(mode: langDart)};
}
*/

// --------------------
//  Abstract Interfaces
// --------------------
abstract class DocumentFile {
  String get uri;
  String get name;
  bool get isDirectory;
  int get size;
  DateTime get modifiedDate;
  String? get mimeType;
}

abstract class FileHandler {
  // Directory operations
  Future<DocumentFile?> pickDirectory();
  Future<List<DocumentFile>> listDirectory(String? uri);
  Future<DocumentFile?> pickFile();
  Future<List<DocumentFile>> pickFiles();

  // File operations
  Future<String> readFile(String uri);
  Future<void> writeFile(String uri, String content);
  Future<DocumentFile> createFile(String parentUri, String fileName);
  Future<void> deleteFile(String uri);

  // URI persistence
  Future<void> persistRootUri(String? uri);
  Future<String?> getPersistedRootUri();

  // File metadata
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
  String? get mimeType {
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
    final dir = await _safUtil.pickDirectory();
    return dir != null ? CustomSAFDocumentFile(dir) : null;
  }

  @override
  Future<List<DocumentFile>> listDirectory(String? uri) async {
    try {
      final contents = await _safUtil.list(uri ?? '');

      // Add sorting logic here
      contents.sort((a, b) {
        // First sort by type (directories first)
        if (a.isDir != b.isDir) {
          return a.isDir ? -1 : 1;
        }

        // Then sort alphabetically case-insensitive
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      return contents.map((f) => CustomSAFDocumentFile(f)).toList();
    } catch (e) {
      print('Error listing directory: $e');
      return [];
    }
  }

  @override
  Future<String> readFile(String uri) async {
    final bytes = await _safStream.readFileBytes(uri);
    return utf8.decode(bytes);
  }

  @override
  Future<void> writeFile(String uri, String content) async {
    final parsed = Uri.parse(uri);
    final parent = parsed.resolve('.').toString();
    final name = parsed.pathSegments.last;

    await _safStream.writeFileBytes(
      parent,
      name,
      await getMimeType(uri) ?? 'text/plain',
      utf8.encode(content),
      overwrite: true,
    );
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, uri ?? '');
  }

  @override
  Future<String?> getPersistedRootUri() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKey);
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

  @override
  Future<List<DocumentFile>> pickFiles() async {
    final files = await _safUtil.pickFiles();
    return files?.map((f) => CustomSAFDocumentFile(f)).toList() ?? [];
  }
}
