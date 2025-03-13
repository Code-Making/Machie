import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

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
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  List<Map<String, dynamic>> _directoryContents = [];
  bool _isSidebarVisible = true;
  final double _sidebarWidth = 300;
  double _sidebarPosition = 0;


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

  Future<void> _loadDirectoryContents(String uri) async {
    final contents = await _fileHandler.listDirectory(uri);
    if (contents != null) {
      setState(() {
        _currentDirUri = uri;
        _directoryContents = contents;
      });
    }
  }
  
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[800],
        duration: const Duration(seconds: 3),
      )
    );
  }
  
  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green[800],
        duration: const Duration(seconds: 2),
      )
    );
  }

Future<void> _openFileTab(String uri) async {
    try {
        final content = await _fileHandler.readFile(uri);
        if (content == null) {
            _showError('Failed to read file. Check permissions.');
            return;
        }
        
        // Check if file is already open
        final existingIndex = _tabs.indexWhere((tab) => tab.uri == uri);
        if (existingIndex != -1) {
            setState(() => _currentTabIndex = existingIndex);
            return;
        }

        final controller = CodeLineEditingController(
            codeLines: CodeLines.fromText(content),
        )..addListener(() => setState(() {
                _tabs[_currentTabIndex].isDirty = true;
            }));

        setState(() {
            _tabs.add(EditorTab(uri: uri, controller: controller));
            _currentTabIndex = _tabs.length - 1;
        });
        
        _showSuccess('Opened: ${uri.split('/').last}');
    } catch (e) {
        _showError('Failed to open file: ${e.toString()}');
    }
}
  
  Future<void> _saveFile() async {
    if (_tabs.isEmpty || _currentTabIndex >= _tabs.length) return;

    final tab = _tabs[_currentTabIndex];
    try {
      final success = await _fileHandler.writeFile(tab.uri, tab.controller.text);
      
      if (success) {
        setState(() => tab.isDirty = false);
        _showSuccess('File saved successfully');
      } else {
        _showError('Failed to save file');
      }
    } catch (e) {
      _showError('Error saving file: ${e.toString()}');
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
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
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
      drawer: _buildDrawer(),
      body: _buildEditorArea(),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          AppBar(
            title: const Text('Explorer'),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          Expanded(
            child: _currentDirUri == null
                ? const Center(child: Text('Open a folder to browse'))
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
                            Navigator.pop(context);
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

    Widget _buildEditorArea() {
    return Column(
      children: [
        if (_tabs.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _tabs.length,
              itemBuilder: (context, index) {
                final tab = _tabs[index];
                return GestureDetector(
                  onTap: () => setState(() => _currentTabIndex = index),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _currentTabIndex == index
                          ? Colors.grey[800]
                          : Colors.grey[900],
                      border: Border(right: BorderSide(color: Colors.grey[700]!)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => _closeTab(index),
                        ),
                        Text(
                          tab.uri.split('/').last,
                          style: TextStyle(
                            color: tab.isDirty ? Colors.orange : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        Expanded(
          child: _tabs.isEmpty
              ? const Center(child: Text('Open a file to start editing'))
              : IndexedStack(
                  index: _currentTabIndex,
                  children: _tabs.map((tab) => CodeEditor(
                    controller: tab.controller,
                    style: CodeEditorStyle(
                      fontSize: 14,
                      fontFamily: 'FiraCode',
                      codeTheme: CodeHighlightTheme(
                        languages: {'dart': CodeHighlightThemeMode(mode: langDart)},
                        theme: atomOneDarkTheme,
                      ),
                    ),
                  )).toList(),
                ),
        ),
      ],
    );
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
      final bytes = await File(uri).readAsBytes();
      return utf8.decode(bytes);
    } catch (e) {
      print("Error reading file: $e");
      return null;
    }
  }

  Future<bool> writeFile(String uri, String content) async {
    try {
      await File(uri).writeAsString(content);
      return true;
    } catch (e) {
      print("Error writing file: $e");
      return false;
    }
  }
}