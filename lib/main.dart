import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
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

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late CodeLineEditingController _controller;
  final CodeScrollController _scrollController = CodeScrollController();
  final GlobalKey<ScaffoldMessengerState> _scaffoldKey = GlobalKey();
  final List<String> _logs = [];
  bool _showConsole = false;
  
  String? _currentFilePath;
  String? _originalFileHash;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final directory = await getTemporaryDirectory();
    directory.delete(recursive: true);
    _controller = CodeLineEditingController(
      codeLines: CodeLines.fromText('// Start coding...\n'),
    );
    _addLog('Application started');
  }

  Future<void> _openFile() async {
    setState(() => _isLoading = true);
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) {
        _addLog('File open canceled by user');
        return;
      }

      final file = result.files.first;
      _addLog('Opening file: ${file.path}');
      final content = await File(file.path!).readAsString();
      
      setState(() {
        _currentFilePath = file.path;
        _originalFileHash = _calculateHash(content);
      });

      _controller.value = CodeLineEditingValue(
        codeLines: CodeLines.fromText(content)
      );
      _addLog('Successfully opened file');
    } catch (e) {
      _handleError('Open failed', e);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveFile({bool forceDialog = false}) async {
    try {
      String? savePath = _currentFilePath;
      final currentContent = _controller.text;
      _addLog('Initiating save process...');

      if (forceDialog || savePath == null) {
        _addLog('Showing save dialog');
        savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save File',
          fileName: _currentFilePath?.split('/').last,
        );
        if (savePath == null) {
          _addLog('Save canceled by user');
          return;
        }
      }

      _addLog('Saving to: $savePath');
      final file = File(savePath);
      
      if (await file.exists() && !forceDialog) {
        _addLog('Checking file modifications...');
        final diskContent = await file.readAsString();
        if (_calculateHash(diskContent) != _originalFileHash) {
          _addLog('File modified externally, showing dialog');
          final choice = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('File Modified'),
              content: const Text('This file has been modified elsewhere. Overwrite?'),
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
          if (choice != true) {
            _addLog('User canceled overwrite');
            return;
          }
        }
      }

      _addLog('Writing file content...');
      await file.writeAsString(currentContent);
      _addLog('Content written successfully');
      
      setState(() {
        _currentFilePath = savePath;
        _originalFileHash = _calculateHash(currentContent);
      });
      _showSuccess('Saved successfully');
      _addLog('File saved successfully');
    } catch (e) {
      _handleError('Save failed', e);
    }
  }

  String _calculateHash(String content) {
    return md5.convert(utf8.encode(content)).toString();
  }

  void _addLog(String message) {
    final timestamp = DateTime.now().toIso8601String();
    setState(() {
      _logs.add('[$timestamp] $message');
    });
  }

  void _handleError(String context, dynamic error) {
    final message = '$context: ${error.toString()}';
    _addLog('ERROR: $message');
    _showError(message);
  }

  Widget _buildBottomToolbar() {
    return Column(
      children: [
        Container(
          color: Colors.grey[900],
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.undo),
                onPressed: _controller.canUndo ? _controller.undo : null,
                tooltip: 'Undo',
              ),
              IconButton(
                icon: const Icon(Icons.redo),
                onPressed: _controller.canRedo ? _controller.redo : null,
                tooltip: 'Redo',
              ),
              IconButton(
                icon: const Icon(Icons.bug_report),
                onPressed: () => setState(() => _showConsole = !_showConsole),
                tooltip: 'Toggle Console',
                color: _showConsole ? Colors.orange : null,
              ),
              // ... other toolbar buttons
            ],
          ),
        ),
        if (_showConsole) _buildConsole(),
      ],
    );
  }

  Widget _buildConsole() {
    return Container(
      height: 150,
      color: Colors.black.withOpacity(0.8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Console:', style: TextStyle(color: Colors.white)),
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white),
                  onPressed: () => setState(() => _logs.clear()),
                  tooltip: 'Clear logs',
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _logs.length,
              reverse: true,
              itemBuilder: (context, index) {
                final log = _logs[_logs.length - 1 - index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    log,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    _scaffoldKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 2),
      )
    );
  }

  void _showSuccess(String message) {
    _scaffoldKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentFilePath?.split('/').last ?? 'Untitled'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_open),
            onPressed: _openFile,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () => _saveFile(),
          ),
          IconButton(
            icon: const Icon(Icons.save_as),
            onPressed: () => _saveFile(forceDialog: true),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                CodeEditor(
                  controller: _controller,
                  scrollController: _scrollController,
                  chunkAnalyzer: DefaultCodeChunkAnalyzer(),
                  style: CodeEditorStyle(
                    fontSize: 14,
                    fontFamily: 'FiraCode',
                    codeTheme: CodeHighlightTheme(
                      languages: {'dart': CodeHighlightThemeMode(mode: langDart)},
                      theme: atomOneDarkTheme,
                    ),
                  ),
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
                        )
                      ],
                    );
                  },
                ),
                if (_isLoading) const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
          _buildBottomToolbar(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}