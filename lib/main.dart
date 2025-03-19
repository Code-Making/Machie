import 'package:crypto/crypto.dart';
import 'dart:core';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
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

void main() => runApp(
  ProviderScope(
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: const EditorScreen(),
    ),
  ),
);

// --------------------
//   Providers
// --------------------
final fileHandlerProvider = Provider<AndroidFileHandler>((ref) => AndroidFileHandler());

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
  });});
  
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

final tabManagerProvider = StateNotifierProvider<TabManager, TabState>((ref) => TabManager());

// --------------------
//        States
// --------------------
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

// --------------------
//  States notifiers
// --------------------
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

// --------------------
//    Editor Screen
// --------------------
class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key});

override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabState = ref.watch(tabManagerProvider);
    final currentDir = ref.watch(currentDirectoryProvider);
    final scaffoldKey = GlobalKey<ScaffoldState>();
    
    return Scaffold(
      key: scaffoldKey,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => scaffoldKey.currentState?.openDrawer(),
        ),
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
      drawer: _buildDirectoryDrawer(ref, currentDir),
      body: Column(
        children: [
          _buildTabBar(ref, tabState),
          Expanded(
            child: tabState.currentTab != null
                ? _buildEditor(tabState.currentTab!)
                : const Center(child: Text('Open a file to start')),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectoryDrawer(WidgetRef ref, String? currentDir) {
    return Drawer(
      child: Column(
        children: [
          AppBar(
            title: const Text('File Explorer'),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          Expanded(
            child: currentDir == null
                ? const Center(child: Text('No folder open'))
                : _DirectoryView(
                    uri: currentDir,
                    onOpenFile: (uri) {
                      Navigator.of(context).pop();
                      _openFileTab(ref, uri);
                    },
                    isRoot: true,
                  ),
          ),
        ],
      ),
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
      fontSize: 12,
                      fontFamily: 'JetBrainsMono',
      codeTheme: CodeHighlightTheme(
        theme: atomOneDarkTheme,
        languages: _getLanguageMode(tab.uri),
      ),
    ),
    wordWrap: tab.wordWrap,
  );
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

  Future<void> _openFile(WidgetRef ref) async {
    final handler = ref.read(fileHandlerProvider);
    final uri = await handler.openFile();
    if (uri != null) _openFileTab(ref, uri);
  }

Future<void> _openFolder(WidgetRef ref) async {
  final handler = ref.read(fileHandlerProvider);
  final uri = await handler.openFolder();
  if (uri != null) {
    ref.read(rootUriProvider.notifier).state = uri;
    ref.read(currentDirectoryProvider.notifier).state = uri;
  }
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
      loading: () => isRoot 
          ? const Center(child: CircularProgressIndicator())
          : _DirectoryLoadingTile(depth: depth),
      error: (error, _) => ListTile(
        leading: const Icon(Icons.error, color: Colors.red),
        title: const Text('Error loading directory'),
      ),
      data: (contents) => Column(
        children: contents.map((item) => _DirectoryItem(
          item: item,
          onOpenFile: onOpenFile,
          depth: depth,
          isRoot: isRoot,
        )).toList(),
      ),
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
      leading: Icon(isRoot ? Icons.folder_open : Icons.folder, 
        color: Colors.yellow),
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
         padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isActive ? Colors.blueGrey[800] : Colors.grey[900],
            border: Border(right: BorderSide(color: Colors.grey[700]!)),
            ),
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
      
      Future<List<Map<String, dynamic>>?> listDirectory(String uri, {bool isRoot = false}) async {
        try {
          final result = await _channel.invokeMethod<List<dynamic>>(
            'listDirectory',
            {'uri': uri, 'isRoot': isRoot}
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
            {'uri': uri}
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
            {'uri': uri, 'content': content}
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
//   Helper Functions
// --------------------

String _getFolderName(String uri) {
  final parsed = Uri.parse(uri);
  return parsed.pathSegments.last.split('/').last;
}