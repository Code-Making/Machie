import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

// 1. Define Providers
final fileHandlerProvider = Provider<AndroidFileHandler>((ref) => AndroidFileHandler());

final currentDirectoryProvider = StateProvider<String?>((ref) => null);

final directoryContentsProvider = FutureProvider.autoDispose
.family<List<Map<String, dynamic>>, String?>((ref, uri) async {
  final handler = ref.read(fileHandlerProvider);
  return await handler.listDirectory(uri ?? '', isRoot: uri == null);
});

final tabManagerProvider = StateNotifierProvider<TabManager, TabState>((ref) => TabManager());

// 2. State Classes
class TabState {
  final List<EditorTab> tabs;
  final int currentIndex;

  TabState({this.tabs = const [], this.currentIndex = 0});
  
  EditorTab? get currentTab => tabs.isNotEmpty ? tabs[currentIndex] : null;
}

class EditorTab {
  final String uri;
  final CodeLineEditingController controller;
  bool isDirty;
  bool wordWrap;

  EditorTab({
    required this.uri,
    required this.controller,
    this.isDirty = false,
    this.wordWrap = false,
  });
}

// 3. State Notifier
class TabManager extends StateNotifier<TabState> {
  TabManager() : super(TabState());

  void addTab(EditorTab tab) {
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

  void closeTab(int index) {
    final newTabs = List<EditorTab>.from(state.tabs)..removeAt(index);
    state = TabState(
      tabs: newTabs,
      currentIndex: state.currentIndex >= index && state.currentIndex > 0 
          ? state.currentIndex - 1 
          : state.currentIndex,
    );
  }
}

// 4. Editor Screen
class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabState = ref.watch(tabManagerProvider);
    final currentDir = ref.watch(currentDirectoryProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(tabState.currentTab?.uri ?? 'Code Editor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: () => _openFolder(ref),
          ),
          IconButton(
            icon: const Icon(Icons.file_open),
            onPressed: () => _openFile(ref),
          ),
        ],
      ),
      body: Row(
        children: [
          _buildDirectoryTree(ref, currentDir),
          Expanded(
            child: Column(
              children: [
                _buildTabBar(ref, tabState),
                Expanded(
                  child: tabState.currentTab != null
                      ? _buildEditor(tabState.currentTab!)
                      : const Center(child: Text('Open a file to start')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectoryTree(WidgetRef ref, String? currentDir) {
    return SizedBox(
      width: 300,
      child: currentDir == null 
          ? const Center(child: Text('No folder open'))
          : _DirectoryView(uri: currentDir),
    );
  }

  Widget _buildTabBar(WidgetRef ref, TabState state) {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: state.tabs.length,
        itemBuilder: (context, index) => Tab(
          tab: state.tabs[index],
          isActive: index == state.currentIndex,
          onClose: () => ref.read(tabManagerProvider.notifier).closeTab(index),
          onTap: () => ref.read(tabManagerProvider.notifier).switchTab(index),
        ),
      ),
    );
  }

  Widget _buildEditor(EditorTab tab) {
    return CodeEditor(
      controller: tab.controller,
      style: CodeEditorStyle(
        fontSize: 14,
        codeTheme: CodeHighlightTheme(theme: atomOneDarkTheme),
      wordWrap: tab.wordWrap,
    );
  }

  Future<void> _openFile(WidgetRef ref) async {
    final handler = ref.read(fileHandlerProvider);
    final uri = await handler.openFile();
    if (uri != null) _openFileTab(ref, uri);
  }

  Future<void> _openFolder(WidgetRef ref) async {
    final handler = ref.read(fileHandlerProvider);
    final uri = await handler.openFolder();
    if (uri != null) ref.read(currentDirectoryProvider.notifier).state = uri;
  }

  Future<void> _openFileTab(WidgetRef ref, String uri) async {
    final handler = ref.read(fileHandlerProvider);
    final content = await handler.readFile(uri);
    
    if (content != null) {
      final controller = CodeLineEditingController(
        codeLines: CodeLines.fromText(content),
      );
      
      ref.read(tabManagerProvider.notifier).addTab(EditorTab(
        uri: uri,
        controller: controller,
      ));
    }
  }
}

// 5. Directory Tree Components
class _DirectoryView extends ConsumerWidget {
  final String uri;

  const _DirectoryView({required this.uri});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentsAsync = ref.watch(directoryContentsProvider(uri));
    
    return contentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (contents) => ListView.builder(
        itemCount: contents.length,
        itemBuilder: (context, index) => _DirectoryItem(
          item: contents[index],
          onOpenFile: (uri) => _openFileTab(ref, uri),
        ),
      ),
    );
  }
}

class _DirectoryItem extends StatelessWidget {
  final Map<String, dynamic> item;
  final Function(String) onOpenFile;

  const _DirectoryItem({required this.item, required this.onOpenFile});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(item['type'] == 'dir' ? Icons.folder : Icons.insert_drive_file),
      title: Text(item['name']),
      onTap: () => item['type'] == 'dir'
          ? context.read(currentDirectoryProvider.notifier).state = item['uri']
          : onOpenFile(item['uri']),
    );
  }
}

// 6. Tab Widget
class Tab extends StatelessWidget {
  final EditorTab tab;
  final bool isActive;
  final VoidCallback onClose;
  final VoidCallback onTap;

  const Tab({
    required this.tab,
    required this.isActive,
    required this.onClose,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isActive ? Colors.blueGrey[800] : Colors.grey[900],
          border: Border(right: BorderSide(color: Colors.grey[700]!)),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onClose,
            ),
            Text(_getFileName(tab.uri)),
          ],
        ),
      ),
    );
  }

  String _getFileName(String uri) => uri.split('/').last;
}

// Keep AndroidFileHandler class from original code unchanged