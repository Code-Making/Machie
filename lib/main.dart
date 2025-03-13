import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:flutter_slider_drawer/flutter_slider_drawer.dart';

void main() => runApp(const CodeEditorApp());

class CodeEditorApp extends StatelessWidget {
  const CodeEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: const EditorScreen(),
    );
  }
}

class EditorTab {
  final String uri;
  final CodeLineEditingController controller;
  bool isDirty;

  EditorTab({
    required this.uri,
    required this.controller,
    this.isDirty = false,
  });
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final _fileHandler = AndroidFileHandler();
  final List<EditorTab> _tabs = [];
  int _currentTabIndex = 0;
  String? _currentDirUri;
  List<Map<String, dynamic>> _directoryContents = [];
  final GlobalKey<SliderDrawerState> _drawerKey = GlobalKey<SliderDrawerState>();

  Future<void> _openFile() async {
    final uri = await _fileHandler.openFile();
    if (uri != null) {
      _openFileTab(uri);
    }
  }

  Future<void> _openFolder() async {
    final uri = await _fileHandler.openFolder();
    if (uri != null) {
      _loadDirectoryContents(uri);
    }
  }

Future<void> _openFileTab(String uri) async {
    if (_tabs.any((tab) => tab.uri == uri)) {
      setState(() => _currentTabIndex = _tabs.indexWhere((tab) => tab.uri == uri));
      return;
    }

    final content = await _fileHandler.readFile(uri);
    if (content != null) {
      final controller = CodeLineEditingController(
        codeLines: CodeLines.fromText(content),
      )..addListener(() => setState(() => _tabs[_currentTabIndex].isDirty = true));

      setState(() {
        _tabs.add(EditorTab(uri: uri, controller: controller));
        _currentTabIndex = _tabs.length - 1;
      });
    }
  }

  Future<void> _loadDirectoryContents(String uri) async {
    final contents = await _fileHandler.listDirectory(uri);
    if (contents != null) {
      setState(() {
        _currentDirUri = uri;
        _directoryContents = contents.where((item) => 
          item['type'] == 'dir' || 
          item['name'].endsWith('.dart') || 
          item['name'].endsWith('.txt')
        ).toList();
      });
    }
  }

  Future<void> _saveFile() async {
    final tab = _tabs[_currentTabIndex];
    final success = await _fileHandler.writeFile(
      tab.uri,
      tab.controller.text,
    );
    
    if (success) {
      setState(() => tab.isDirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File saved successfully')),
      );
    }
  }

  void _closeTab(int index) {
    setState(() {
      _tabs.removeAt(index);
      if (_currentTabIndex >= index && _currentTabIndex > 0) {
        _currentTabIndex--;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SliderDrawer(
      key: _drawerKey,
      sliderOpenSize: 300,
      slider: _buildFileExplorer(),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => _drawerKey.currentState?.toggle(),
          ),
          title: Text(_tabs.isEmpty 
              ? 'No File Open' 
              : _tabs[_currentTabIndex].uri.split('/').last),
          actions: [
            IconButton(
              icon: const Icon(Icons.folder_open),
              onPressed: _openFolder,
              tooltip: 'Open Folder',
            ),
            IconButton(
              icon: const Icon(Icons.file_open),
              onPressed: _openFile,
              tooltip: 'Open File',
            ),
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _tabs.isNotEmpty ? _saveFile : null,
              tooltip: 'Save File',
            ),
          ],
        ),
        body: Column(
          children: [
            // Tab Bar
            if (_tabs.isNotEmpty)
              Container(
                height: 40,
                color: Colors.grey[850],
                child: Row(
                  children: [
                    ..._tabs.asMap().entries.map((entry) {
                      final index = entry.key;
                      final tab = entry.value;
                      return Container(
                        decoration: BoxDecoration(
                          color: _currentTabIndex == index 
                              ? Colors.grey[800] 
                              : Colors.grey[900],
                          border: Border(
                            right: BorderSide(color: Colors.grey[700]!),
                          ),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.close, size: 18),
                              onPressed: () => _closeTab(index),
                            ),
                            Text(
                              tab.uri.split('/').last,
                              style: TextStyle(
                                color: tab.isDirty ? Colors.orange : null,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            // Editor
            Expanded(
              child: _tabs.isEmpty
                  ? const Center(child: Text('Open a file to start editing'))
                  : CodeEditor(
                      controller: _tabs[_currentTabIndex].controller,
                      style: CodeEditorStyle(
                        fontSize: 14,
                        fontFamily: 'FiraCode',
                        codeTheme: CodeHighlightTheme(
                          languages: {'dart': CodeHighlightThemeMode(mode: langDart)},
                          theme: atomOneDarkTheme,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileExplorer() {
    return Container(
      color: Colors.grey[900],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                const Text('File Explorer', style: TextStyle(fontSize: 18)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _currentDirUri != null 
                      ? () => _loadParentDirectory()
                      : null,
                ),
              ],
            ),
          ),
          Expanded(
            child: _currentDirUri == null
                ? const Center(child: Text('No folder open'))
                : ListView.builder(
                    itemCount: _directoryContents.length,
                    itemBuilder: (context, index) {
                      final item = _directoryContents[index];
                      return ListTile(
                        leading: Icon(item['type'] == 'dir' 
                            ? Icons.folder 
                            : Icons.insert_drive_file),
                        title: Text(item['name']),
                        onTap: () {
                          if (item['type'] == 'dir') {
                            _loadDirectoryContents(item['uri']);
                          } else {
                            _openFileTab(item['uri']);
                            _drawerKey.currentState!.closeDrawer();
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadParentDirectory() async {
    if (_currentDirUri == null) return;
    final parentUri = Directory(_currentDirUri!).parent.path;
    await _loadDirectoryContents(parentUri);
  }
}

class AndroidFileHandler {
  static const _channel = MethodChannel('com.example/file_handler');

  Future<String?> openFile() async {
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

  Future<List<Map<String, dynamic>>?> listDirectory(String uri) async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'listDirectory',
        {'uri': uri}
      );
      return result?.map((e) => Map<String, dynamic>.from(e)).toList();
    } on PlatformException catch (e) {
      print("Error listing directory: ${e.message}");
      return null;
    }
  }

  Future<String?> readFile(String uri) async {
    try {
      return await _channel.invokeMethod<String>('readFile', {'uri': uri});
    } on PlatformException catch (e) {
      print("Error reading file: ${e.message}");
      return null;
    }
  }

  Future<bool> writeFile(String uri, String content) async {
    try {
      return await _channel.invokeMethod<bool>(
        'writeFile',
        {'uri': uri, 'content': content}
      ) ?? false;
    } on PlatformException catch (e) {
      print("Error writing file: ${e.message}");
      return false;
    }
  }
}