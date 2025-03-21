import 'package:crypto/crypto.dart';
import 'dart:core';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:collection/collection.dart';

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
  
  final pluginRegistry = {CodeEditorPlugin()};

  runApp(
    ProviderScope(
      child: MaterialApp(
        theme: ThemeData.dark(), 
        home: const EditorScreen(),
        routes: {
          '/settings': (_) => const SettingsScreen(),
        },
      ),
    ),
  );
}

// --------------------
//   Providers
// --------------------
final reorderProvider = StateProvider<bool>((ref) => false);

final fileHandlerProvider = Provider<AndroidFileHandler>(
  (ref) => AndroidFileHandler(),
);

final currentDirectoryProvider = StateProvider<String?>((ref) => null);

final rootUriProvider = StateProvider<String?>((_) => null);

final directoryContentsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String?>((ref, uri) async {
      final handler = ref.read(fileHandlerProvider);
      final rootUri = ref.read(rootUriProvider);
      final isRoot = uri == rootUri;
      // Modify the directoryContentsProvider
      return (await handler.listDirectory(uri ?? '', isRoot: isRoot) ?? [])
        ..sort((a, b) {
          if (a['type'] == b['type']) {
            return a['name'].toLowerCase().compareTo(b['name'].toLowerCase());
          }
          return a['type'] == 'dir' ? -1 : 1;
        });
    });

final directoryChildrenProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, uri) async {
      final handler = ref.read(fileHandlerProvider);
      final isRoot = ref.read(rootUriProvider) == uri;
      final contents = await handler.listDirectory(uri, isRoot: isRoot) ?? [];
      contents.sort((a, b) {
        if (a['type'] == b['type']) {
          return a['name'].toLowerCase().compareTo(b['name'].toLowerCase());
        }
        return a['type'] == 'dir' ? -1 : 1;
      });
      return contents;
    });

final tabManagerProvider = StateNotifierProvider<TabManager, TabState>((ref) {
  return TabManager(
    fileHandler: ref.read(fileHandlerProvider),
    plugins: ref.read(activePluginsProvider),
  );
});
// --------------------
//        States
// --------------------
class TabState {
  final List<EditorTab> tabs;
  final int currentIndex;

  TabState({this.tabs = const [], this.currentIndex = 0});

  EditorTab? get currentTab => tabs.isNotEmpty ? tabs[currentIndex] : null;
  
    // Add equality checks
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TabState &&
          currentIndex == other.currentIndex &&
          const ListEquality().equals(tabs, other.tabs);

  @override
  int get hashCode => 
      Object.hash(currentIndex, const ListEquality().hash(tabs));
}

abstract class EditorTab {
  final String uri;
  final EditorPlugin plugin;
  bool isDirty;

  EditorTab({
    required this.uri,
    required this.plugin,
    this.isDirty = false,
  });

  void dispose();
}

class CodeEditorTab extends EditorTab {
  final CodeLineEditingController controller;

  CodeEditorTab({
    required super.uri,
    required this.controller,
    required super.plugin,
  });

  @override
  void dispose() => controller.dispose();
}

// --------------------
//  States notifiers
// --------------------

// --------------------
//    Editor Screen
// --------------------

class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(tabManagerProvider.select((s) => s.currentTab));
    final currentDir = ref.watch(currentDirectoryProvider);
    final scaffoldKey = GlobalKey<ScaffoldState>(); // Add key here

    return Scaffold(
      key: scaffoldKey, // Assign key to Scaffold
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => scaffoldKey.currentState?.openDrawer(),
        ),
          actions: [
    IconButton(
      icon: const Icon(Icons.settings),
      onPressed: () => Navigator.push(
        context, 
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      ),
      ),
  ],
       title: Text(
          currentTab != null 
              ? Uri.parse(currentTab!.uri).pathSegments.last.split(':').last
              : 'Code Editor'
          ),            
        ),
      drawer: FileExplorerDrawer(currentDir: currentDir),
      body: Column(
        children: [
          const TabBarView(),
          Expanded(
            child: currentTab != null
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

final pluginRegistryProvider = Provider<Set<EditorPlugin>>((_) => {
  CodeEditorPlugin(), // Default text editor
  // Add other plugins here
});

final activePluginsProvider = StateNotifierProvider<PluginManager, Set<EditorPlugin>>((ref) {
  return PluginManager(ref.read(pluginRegistryProvider));
});

class PluginManager extends StateNotifier<Set<EditorPlugin>> {
  PluginManager(Set<EditorPlugin> plugins) : super(plugins);

  void registerPlugin(EditorPlugin plugin) => state = {...state, plugin};
  void unregisterPlugin(EditorPlugin plugin) => state = state.where((p) => p != plugin).toSet();
}

// --------------------
//   Editor Plugin
// --------------------

abstract class EditorPlugin {
  // Metadata
  String get name;
  Widget get icon;

  // File type support
  bool supportsFile(String uri, {String? mimeType, Uint8List? bytes});
  
  // Tab management
  EditorTab createTab(String uri);
  Widget buildEditor(EditorTab tab);
  
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
  bool supportsFile(String uri, {String? mimeType, Uint8List? bytes}) {
    final ext = Uri.parse(uri).pathSegments.last.split('.').last.toLowerCase();
    return const {
      'dart', 'js', 'ts', 'py', 'java', 'kt', 'cpp', 'h', 'cs',
      'html', 'css', 'xml', 'json', 'yaml', 'md', 'txt'
    }.contains(ext);
  }

  @override
  EditorTab createTab(String uri) => CodeEditorTab(
    uri: uri,
    plugin: this,
    controller: CodeLineEditingController(),
  );

  @override
  Widget buildEditor(EditorTab tab) {
    final codeTab = tab as CodeEditorTab;
    return CodeEditor(
      controller: codeTab.controller,
      style: _editorStyleFor(codeTab.uri),
    );
  }

  // 4. Add missing style method
  CodeEditorStyle _editorStyleFor(String uri) {
    return CodeEditorStyle(
      fontSize: 12,
      fontFamily: 'JetBrainsMono',
      codeTheme: CodeHighlightTheme(
        theme: atomOneDarkTheme,
        languages: _getLanguageMode(uri),
      ),
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
          onChanged: (value) => _updateSettings(_currentSettings.copyWith(wordWrap: value)),
          ),
        Slider(
          value: _currentSettings.fontSize,
          min: 8,
          max: 24,
          divisions: 16,
          label: 'Font Size: ${_currentSettings.fontSize.round()}',
          onChanged: (value) => _updateSettings(_currentSettings.copyWith(fontSize: value)),
          ),
        DropdownButtonFormField<String>(
          value: _currentSettings.fontFamily,
          items: const [
            DropdownMenuItem(value: 'JetBrainsMono', child: Text('JetBrains Mono')),
            DropdownMenuItem(value: 'FiraCode', child: Text('Fira Code')),
            DropdownMenuItem(value: 'SourceCodePro', child: Text('Source Code Pro')),
          ],
          onChanged: (value) => _updateSettings(_currentSettings.copyWith(fontFamily: value)),
          ),
      ],
    );
  }

// In _CodeEditorSettingsUIState
void _updateSettings(CodeEditorSettings newSettings) {
  setState(() => _currentSettings = newSettings);
  ProviderScope.containerOf(context).read(settingsProvider.notifier)
    .updatePluginSettings(newSettings);
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
      body: plugins.isEmpty
          ? const Center(child: Text('No plugins available'))
          : ListView(
              children: plugins
                  .where((p) => p.settings != null)
                  .map((plugin) => _PluginSettingsCard(
                    plugin: plugin,
                    settings: settings.pluginSettings[plugin.settings.runtimeType]!,
                  ))
                  .toList(),
            ),
    );
  }
}

class PluginSettingsScreen extends ConsumerWidget {
  const PluginSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plugins = ref.watch(activePluginsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Plugins')),
      body: ListView.builder(
        itemCount: plugins.length,
        itemBuilder: (_, index) => ListTile(
          leading: plugins.elementAt(index).icon,
          title: Text(plugins.elementAt(index).name),
          trailing: Switch(
            value: true,
            onChanged: (v) => _togglePlugin(ref, plugins.elementAt(index), v),
          ),
        ),
      ),
    );
  }

  void _togglePlugin(WidgetRef ref, EditorPlugin plugin, bool enable) {
    final manager = ref.read(activePluginsProvider.notifier);
    enable ? manager.registerPlugin(plugin) : manager.unregisterPlugin(plugin);
  }
}

class _PluginSettingsCard extends ConsumerWidget {
  final EditorPlugin plugin;
  final PluginSettings settings;

  const _PluginSettingsCard({
    required this.plugin,
    required this.settings,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(plugin.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            plugin.buildSettingsUI(settings),
          ],
        ),
      ),
    );
  }
}

// --------------------
//   Editor Content
// --------------------
abstract class EditorContent extends Widget {
  const EditorContent({super.key});

  factory EditorContent.code({
    required CodeLineEditingController controller,
    required String uri,
  }) = CodeEditorContent;
}

class CodeEditorContent extends StatelessWidget implements EditorContent {
  final CodeLineEditingController controller;
  final String uri;

  const CodeEditorContent({
    super.key,
    required this.controller,
    required this.uri,
  });

  @override
  Widget build(BuildContext context) {
    return CodeEditor(
      controller: controller,
      style: CodeEditorStyle(
        fontSize: 12,
        fontFamily: 'JetBrainsMono',
        codeTheme: CodeHighlightTheme(
          theme: atomOneDarkTheme,
          languages: _getLanguageMode(uri),
        ),
      ),
      wordWrap: false,
    );
  }
}

class EditorContentSwitcher extends ConsumerWidget {
  final EditorTab tab;

  const EditorContentSwitcher({super.key, required this.tab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    try {
      return tab.plugin.buildEditor(tab);
    } catch (e) {
      return ErrorWidget.withDetails(
        message: 'Failed to load editor: ${e.toString()}',
        error: FlutterError(e.toString()),
       );
    }
  }
}

class FileTypeIcon extends ConsumerWidget {
  final String uri;

  const FileTypeIcon({super.key, required this.uri});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plugins = ref.watch(activePluginsProvider);
    final plugin = plugins.firstWhereOrNull(
      (p) => p.supportsFile(uri)
    );
    
    return plugin?.icon ?? const Icon(Icons.insert_drive_file);
  }
}

// --------------------
//   Directory view
// --------------------

class _DirectoryView extends ConsumerWidget {
  final String uri;
  final Function(String) onOpenFile;
  final int depth;
  final bool isRoot;

  const _DirectoryView({
    required this.uri,
    required this.onOpenFile,
    this.depth = 0,
    this.isRoot = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentsAsync = ref.watch(directoryChildrenProvider(uri));

    return contentsAsync.when(
      loading: () => _buildLoadingState(),
      error: (error, _) => _buildErrorState(),
      data: (contents) => _buildDirectoryList(contents),
    );
  }

  Widget _buildDirectoryList(List<Map<String, dynamic>> contents) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      itemCount: contents.length,
      itemBuilder: (context, index) => _DirectoryItem(
        item: contents[index],
        onOpenFile: onOpenFile,
        depth: depth,
        isRoot: isRoot,
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView(
      shrinkWrap: true,
      children: [
        _DirectoryLoadingTile(depth: depth),
      ],
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
  final Map<String, dynamic> item;
  final Function(String) onOpenFile;
  final int depth;
  final bool isRoot;

  const _DirectoryItem({
    required this.item,
    required this.onOpenFile,
    required this.depth,
    required this.isRoot,
  });

  @override
  Widget build(BuildContext context) {
    if (item['type'] == 'dir') {
      return _DirectoryExpansionTile(
        uri: item['uri'],
        name: item['name'],
        depth: depth,
        isRoot: isRoot,
        onOpenFile: onOpenFile,
      );
    }
    return _FileItem(
      uri: item['uri'],
      name: item['name'],
      depth: depth,
      onTap: () => onOpenFile(item['uri']),
    );
  }
}

class _DirectoryExpansionTile extends ConsumerWidget {
  final String uri;
  final String name;
  final int depth;
  final bool isRoot;
  final Function(String) onOpenFile;

  const _DirectoryExpansionTile({
    required this.uri,
    required this.name,
    required this.depth,
    required this.isRoot,
    required this.onOpenFile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ExpansionTile(
      leading: Icon(
        isRoot ? Icons.folder_open : Icons.folder,
        color: Colors.yellow,
      ),
      title: Text(name),
      childrenPadding: EdgeInsets.only(left: (depth + 1) * 16.0),
      children: [
        _DirectoryView(
          uri: uri,
          onOpenFile: onOpenFile,
          depth: depth + 1,
          isRoot: false,
        ),
      ],
    );
  }
}

class _FileItem extends StatelessWidget {
  final String uri;
  final String name;
  final int depth;
  final VoidCallback onTap;

  const _FileItem({
    required this.uri,
    required this.name,
    required this.depth,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.only(left: (depth + 1) * 16.0),
      leading: const Icon(Icons.insert_drive_file),
      title: Text(name),
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

class TabManager extends StateNotifier<TabState> {
    final AndroidFileHandler fileHandler;
    final Set<EditorPlugin> plugins;

  TabManager({
    required this.fileHandler,
    required this.plugins,
  }) : super(TabState());

  Future<void> openFile(String uri) async {
    final existingIndex = state.tabs.indexWhere((t) => t.uri == uri);
    if (existingIndex != -1) {
      state = TabState(tabs: state.tabs, currentIndex: existingIndex);
      return;
    }

    final content = await fileHandler.readFile(uri);

    for (final plugin in plugins) {
      if (plugin.supportsFile(uri)) {
        final tab = plugin.createTab(uri);
        await plugin.initializeTab(tab, content); // Delegate initialization
        return _addTab(tab);
      }
    }
    
    throw UnsupportedFileType(uri);
  }

  void _addTab(EditorTab tab) {
    state = TabState(
      tabs: [...state.tabs, tab],
      currentIndex: state.tabs.length,
    );
  }

  void switchTab(int index) {
    state = TabState(
      tabs: state.tabs,
      currentIndex: index.clamp(0, state.tabs.length - 1),
    );
  }
  


void reorderTabs(int oldIndex, int newIndex) {
    final newTabs = List<EditorTab>.from(state.tabs);
    final movedTab = newTabs.removeAt(oldIndex);
    newTabs.insert(newIndex, movedTab);

    // Preserve current tab if it still exists
    final currentUri = state.currentTab?.uri;
    final newCurrentIndex = currentUri != null 
        ? newTabs.indexWhere((t) => t.uri == currentUri)
        : state.currentIndex;

    state = TabState(
      tabs: newTabs,
      currentIndex: newCurrentIndex.clamp(0, newTabs.length - 1),
    );
  }

  void closeTab(int index) {
    state.tabs[index].dispose();
    final newTabs = List<EditorTab>.from(state.tabs)..removeAt(index);
    state = TabState(
      tabs: newTabs,
      currentIndex:
          state.currentIndex >= index && state.currentIndex > 0
              ? state.currentIndex - 1
              : state.currentIndex,
    );
  }
}

// --------------------
//      Tab Bar
// --------------------
class TabBarView extends ConsumerWidget {
  const TabBarView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.watch(tabManagerProvider.select((state) => state.tabs));
    
    return Container(
      color: Colors.grey[900],
      height: 40,
      child: ReorderableListView(
        scrollDirection: Axis.horizontal,
        onReorder: (oldIndex, newIndex) =>
            ref.read(tabManagerProvider.notifier).reorderTabs(oldIndex, newIndex),
        buildDefaultDragHandles: false,
        children: [
          for (final tab in tabs)
            ReorderableDelayedDragStartListener(
              key: ValueKey(tab.uri),
              index: tabs.indexOf(tab),
              child: FileTab(
                tab: tab, 
                index: tabs.indexOf(tab),
              ),
            )
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
      tabManagerProvider.select((state) => state.currentIndex == index)
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 200),
      child: Material(
        color: isActive ? Colors.blueGrey[800] : Colors.grey[900],
        child: InkWell(
          onTap: () => ref.read(tabManagerProvider.notifier).switchTab(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => ref.read(tabManagerProvider.notifier).closeTab(index),
                ),
                Expanded(
                  child: Text(
                    _getFileName(tab.uri),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tab.isDirty ? Colors.orange : Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getFileName(String uri) => Uri.parse(uri).pathSegments.last.split('/').last;
}

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
  final String? currentDir;
  
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
            child: currentDir == null
                ? const Center(child: Text('No folder open'))
                : _DirectoryView(
                    uri: currentDir!,
                    onOpenFile: (uri) {
                      Navigator.pop(context);
                      ref.read(tabManagerProvider.notifier).openFile(uri);
                    },
                    isRoot: true,
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
              final uri = await ref.read(fileHandlerProvider).openFolder();
              if (uri != null) {
                ref.read(rootUriProvider.notifier).state = uri;
                ref.read(currentDirectoryProvider.notifier).state = uri;
                Navigator.pop(context);
              }
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.file_open),
            label: const Text('Open File'),
            onPressed: () async {
              final uri = await ref.read(fileHandlerProvider).openFile();
              if (uri != null) {
                ref.read(tabManagerProvider.notifier).openFile(uri);
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
//     File Handlers
// --------------------

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

  AppSettings copyWith({
    Map<Type, PluginSettings>? pluginSettings,
  }) {
    return AppSettings(
      pluginSettings: pluginSettings ?? this.pluginSettings,
    );
  }
}

// --------------------
//  Settings Providers
// --------------------
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>(
  (ref) => SettingsNotifier(),
);

class SettingsNotifier extends StateNotifier<AppSettings> {
  final Set<EditorPlugin> _plugins;

  SettingsNotifier({required Set<EditorPlugin> plugins})
      : _plugins = plugins,
        super(AppSettings(
          pluginSettings: _getDefaultSettings(plugins),
        )) {
    loadSettings();
  }

  static Map<Type, PluginSettings> _getDefaultSettings(Set<EditorPlugin> plugins) {
    return {
      for (final plugin in plugins)
        if (plugin.settings != null)
          plugin.settings.runtimeType: plugin.settings!
    };
  }

  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString('app_settings');
      
      if (settingsJson != null) {
        final decoded = jsonDecode(settingsJson) as Map<String, dynamic>;
        final newSettings = Map<Type, PluginSettings>.from(state.pluginSettings);

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
//   Helper Functions
// --------------------

String _getFolderName(String uri) {
  final parsed = Uri.parse(uri);
  return parsed.pathSegments.last.split('/').last;
}