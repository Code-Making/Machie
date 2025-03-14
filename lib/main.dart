import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:permission_handler/permission_handler.dart';

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
    String? _originalFileHash; // Add this line

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  List<Map<String, dynamic>> _directoryContents = [];
  bool _isSidebarVisible = true;
  final double _sidebarWidth = 300;
  double _sidebarPosition = 0;
  
    final FocusNode _keyboardFocusNode = FocusNode();



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
    
    // Allow empty files but handle them differently
    final isEmpty = content?.isEmpty ?? true;
    _originalFileHash = _calculateHash(content!);
    final controller = CodeLineEditingController(
      codeLines: isEmpty ? CodeLines.fromText('') : CodeLines.fromText(content!),
    );

    setState(() {
      _tabs.add(EditorTab(
        uri: uri,
        controller: controller,
        isDirty: isEmpty // Mark empty files as dirty initially
      ));
      _currentTabIndex = _tabs.length - 1;
    });

    _showSuccess(isEmpty 
        ? 'Opened empty file' 
        : 'Successfully opened file (${content!.length} chars)');

  } on Exception catch (e) {
    _showError('Failed to open file: ${e.toString()}');
  }
}


  Future<void> _saveFile() async {
  if (_tabs.isEmpty || _currentTabIndex >= _tabs.length) return;

  final tab = _tabs[_currentTabIndex];
  try {
    // Check external modifications
    final currentContent = await _fileHandler.readFile(tab.uri);
    final currentHash = _calculateHash(currentContent ?? '');
    
    if (currentHash != _originalFileHash) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('File Modified'),
          content: const Text('This file has been modified externally. Overwrite?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Overwrite'),
            ),
          ],
        ),
      );
      
      if (choice != true) return;
    }

    // Perform save
    final success = await _fileHandler.writeFile(tab.uri, tab.controller.text);
    
    if (success) {
      // Update checksum after successful save
      final newContent = await _fileHandler.readFile(tab.uri);
      setState(() {
        tab.isDirty = false;
        _originalFileHash = _calculateHash(newContent ?? '');
      });
      _showSuccess('File saved successfully');
    } else {
      _showError('Failed to save file');
    }
  } catch (e) {
    _showError('Save error: ${e.toString()}');
  }
}

String _calculateHash(String content) {
  return md5.convert(utf8.encode(content)).toString();
}

Future<bool> _checkFileModified(String uri) async {
  try {
    final currentContent = await _fileHandler.readFile(uri);
    return _calculateHash(currentContent ?? '') != _originalFileHash;
  } catch (e) {
    _showError('Modification check failed: ${e.toString()}');
    return false;
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
  
    void _handleKeyEvent(RawKeyEvent event) {
        if (_tabs.isEmpty || _currentTabIndex >= _tabs.length) return;

    final tab = _tabs[_currentTabIndex];
    if (event is! RawKeyDownEvent) return;

  final selection = tab.controller.selection;
  final isShiftPressed = event.isShiftPressed;

  void handleMove(AxisDirection direction) {
    if (isShiftPressed) {
      tab.controller.extendSelection(direction);
    } else {
      tab.controller.moveCursor(direction);
    }
  }

  switch (event.logicalKey) {
    case LogicalKeyboardKey.arrowLeft:
      handleMove(AxisDirection.left);
      break;
    case LogicalKeyboardKey.arrowRight:
      handleMove(AxisDirection.right);
      break;
    case LogicalKeyboardKey.arrowUp:
      handleMove(AxisDirection.up);
      break;
    case LogicalKeyboardKey.arrowDown:
      handleMove(AxisDirection.down);
      break;
  }
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
        RawKeyboardListener(
              focusNode: _keyboardFocusNode,
              onKey: _handleKeyEvent,
              child: 
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
        ),
      ],
    );
  }
}

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