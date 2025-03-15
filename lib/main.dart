import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'dart:io';
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
import 'package:re_highlight/languages/plaintext.dart';



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


  Future<void> _openFile() async {
    final uri = await _fileHandler.openFile();
    if (uri != null) {
      _openFileTab(uri);
    }
  }

  Future<void> _openFolder() async {
    final uri = await _fileHandler.openFolder();
    if (uri != null) {
      _loadDirectoryContents(uri, isRoot: true);
    }
  }

  Future<void> _loadDirectoryContents(String uri, {bool isRoot = false}) async {
    final contents = await _fileHandler.listDirectory(uri, isRoot: isRoot);
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
    // Check if file is already open in a tab
    for (int i = 0; i < _tabs.length; i++) {
      if (_tabs[i].uri == uri) {
        setState(() {
          _currentTabIndex = i;
        });
        _showSuccess('Switched to existing tab');
        return;
      }
    }

    final content = await _fileHandler.readFile(uri);
    if (content == null) {
      _showError('Failed to read file');
      return;
    }

    final isEmpty = content.isEmpty;
    _originalFileHash = _calculateHash(content);
    final controller = CodeLineEditingController(
      codeLines: isEmpty ? CodeLines.fromText('') : CodeLines.fromText(content),
    );

    setState(() {
      _tabs.add(EditorTab(
        uri: uri,
        controller: controller,
        isDirty: isEmpty,
      ));
      _currentTabIndex = _tabs.length - 1;
    });

    _showSuccess(isEmpty 
        ? 'Opened empty file' 
        : 'Successfully opened file (${content.length} chars)');
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
  
  Widget _buildDirectoryTree(List<Map<String, dynamic>> contents) {
  return ListView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: contents.length,
    itemBuilder: (context, index) {
      final item = contents[index];
      if (item['type'] == 'dir') {
        return _DirectoryExpansionTile(
          uri: item['uri'],
          name: item['name'],
          fileHandler: _fileHandler,
          onFileTap: (uri) => _openFileTab(uri),
        );
      }
      return ListTile(
        leading: const Icon(Icons.insert_drive_file),
        title: Text(item['name']),
        onTap: () {
          _openFileTab(item['uri']);
          Navigator.pop(context);
        },
      );
    },
  );
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
            : _getFormattedPath(_tabs[_currentTabIndex].uri)),
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
            title: Text(_currentDirUri!=null ? _getFileName(_currentDirUri!):"Explorer"),
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
              : _buildDirectoryTree(_directoryContents),
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
                  onLongPress: () {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(_getFormattedPath(tab.uri)),
      actions: [
        TextButton(
          child: const Text('Close'),
          onPressed: () {
            _closeTab(index);
            Navigator.pop(context);
          },
        ),
        TextButton(
          child: const Text('Close Others'),
          onPressed: () {
            _closeOtherTabs(index);
            Navigator.pop(context);
          },
        ),
      ],
    ),
  );
},
                  child: Container(
                    decoration: BoxDecoration(
                      color: _currentTabIndex == index
                          ? Colors.grey[800]
                          : Colors.grey[900],
                    border: Border(
                      right: BorderSide(color: Colors.grey[700]!),
                      bottom: _currentTabIndex == index
                          ? BorderSide(color: Colors.blueAccent, width: 2)
                          : BorderSide.none,
                          ),                    
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => _closeTab(index),
                        ),
                        Text(
                          _getFileName(tab.uri),
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
                      fontFamily: 'FiraMono',
                      codeTheme: CodeHighlightTheme(
                      languages: _getLanguageMode(tab.uri),         
                      theme: atomOneDarkTheme,
                      indicatorBuilder: (context, editingController, chunkController, notifier) {
                            return Row(
                              children: [
                                DefaultCodeLineNumber(
                                  controller: editingController,
                                  notifier: notifier,
                                ),
                                DefaultCodeChunkIndicator(
                                  width: 20,
                                  controller: chunkController,
                                  notifier: notifier,
                                ),
                              ],
                            );
                          },
                      ),
                    ),
                  )).toList(),
                ),
        ),
      ],
    );
  }
  void _closeOtherTabs(int keepIndex) {
  setState(() {
    _tabs.removeWhere((tab) => _tabs.indexOf(tab) != keepIndex);
    _currentTabIndex = 0;
  });
}

String _getFormattedPath(String uri){
    final parsed = Uri.parse(uri);
  if (parsed.pathSegments.isNotEmpty) {
    // Handle content URIs and normal file paths
    return parsed.pathSegments.last.split(':').last;
  }
  // Fallback for unusual URI formats
  return uri.split('/').lastWhere((part) => part.isNotEmpty, orElse: () => 'untitled');
}

String _getFileName(String uri) {
  final parsed = Uri.parse(uri);
  if (parsed.pathSegments.isNotEmpty) {
    // Handle content URIs and normal file paths
    return parsed.pathSegments.last.split('/').last;
  }
  // Fallback for unusual URI formats
  return uri.split('/').lastWhere((part) => part.isNotEmpty, orElse: () => 'untitled');
}
}

class _DirectoryExpansionTile extends StatefulWidget {
  final String uri;
  final String name;
  final AndroidFileHandler fileHandler;
  final Function(String) onFileTap;

  const _DirectoryExpansionTile({
    required this.uri,
    required this.name,
    required this.fileHandler,
    required this.onFileTap,
  });

  @override
  State<_DirectoryExpansionTile> createState() => _DirectoryExpansionTileState();
}

// Update the _DirectoryExpansionTileState class
class _DirectoryExpansionTileState extends State<_DirectoryExpansionTile> {
  bool _isExpanded = false;
  List<Map<String, dynamic>> _children = [];
  bool _isLoading = false;

  Widget _buildChildItems(List<Map<String, dynamic>> contents) {
    
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: contents.length,
      itemBuilder: (context, index) {
        final item = contents[index];
        if (item['type'] == 'dir') {
          return _DirectoryExpansionTile(
            uri: item['uri'],  // Pass the SUBFOLDER's URI here
            name: item['name'],
            fileHandler: widget.fileHandler,
            onFileTap: widget.onFileTap,
          );
        }
        return ListTile(
          leading: const Icon(Icons.insert_drive_file),
          title: Text(item['name']),
          onTap: () => widget.onFileTap(item['uri']),
        );
      },
    );
  }

  Future<void> _loadChildren() async {
    setState(() => _isLoading = true);
    try {
        // In _loadChildren()
      debugPrint('Loading children for: ${widget.uri}');
      // Use the current directory's URI to load its contents
      final contents = await widget.fileHandler.listDirectory(widget.uri);
      if (contents != null) {
        setState(() => _children = contents);
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: Icon(_isExpanded ? Icons.folder_open : Icons.folder),
      title: Text(widget.name),
      trailing: _isLoading 
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onExpansionChanged: (expanded) async {
        setState(() => _isExpanded = expanded);
        if (expanded && _children.isEmpty) {
          await _loadChildren();
        }
      },
      children: [
        if (_children.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: _buildChildItems(_children),
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

// Add this extension-to-language mapper in your _EditorScreenState class
// Update the language mapping logic
Map<String, CodeHighlightThemeMode> _getLanguageMode(String uri) {
  final extension = uri.split('.').last.toLowerCase();
  
  // Explicitly handle each case with proper typing
  switch (extension) {
    case 'dart':
      return {'dart': CodeHighlightThemeMode(mode: langDart)};
    case 'js':
    case 'jsx':
      return {'javascript': CodeHighlightThemeMode(mode: langJavascript)};
    case 'py':
      return {'python': CodeHighlightThemeMode(mode: langPython)};
    case 'java':
      return {'java': CodeHighlightThemeMode(mode: langJava)};
    case 'cpp':
    case 'cc':
    case 'h':
      return {'cpp': CodeHighlightThemeMode(mode: langCpp)};
    case 'css':
      return {'css': CodeHighlightThemeMode(mode: langCss)};
    case 'kt':
      return {'kt': CodeHighlightThemeMode(mode: langKotlin)};
    case 'json':
      return {'json': CodeHighlightThemeMode(mode: langJson)};
    case 'yaml':
    case 'yml':
      return {'yaml': CodeHighlightThemeMode(mode: langYaml)};
    case 'md':
      return {'markdown': CodeHighlightThemeMode(mode: langMarkdown)};
    default:
      return {'plaintext': CodeHighlightThemeMode(mode: langPlaintext)};
  }
}