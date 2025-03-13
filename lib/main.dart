import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:external_path/external_path.dart';
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

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});
  String? _currentFilePath;
  String? _originalFileHash;
  
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late CodeLineEditingController _controller;
  final FocusNode _keyboardFocusNode = FocusNode();
  final CodeScrollController _scrollController = CodeScrollController();
  String? _currentFilePath;
  final List<CodeLineEditingValue> _history = [];
  int _historyIndex = -1;

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController(
      codeLines: CodeLines.fromText('// Start coding...\n'),
    );
  }

    Future<void> _openFile() async {
    final status = await Permission.storage.request();
    if (!status.isGranted) return;

    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final content = await File(file.path!).readAsString();
    
    setState(() {
      _currentFilePath = file.path;
      _originalFileHash = _calculateHash(content);
    });

    _controller.value = CodeLineEditingValue(codeLines: CodeLines.fromText(content));
  }

  Future<void> _saveFile() async {
    final status = await Permission.storage.request();
    if (!status.isGranted) return;

    if (_currentFilePath == null) {
      return _saveAs();
    }

    final currentContent = _controller.text;
    final currentHash = _calculateHash(currentContent);
    
    try {
      final existingFile = File(_currentFilePath!);
      final exists = await existingFile.exists();
      
      if (exists) {
        final diskContent = await existingFile.readAsString();
        final diskHash = _calculateHash(diskContent);
        
        if (diskHash != _originalFileHash) {
          final choice = await showDialog<FileConflictChoice>(
            context: context,
            builder: (context) => _buildFileConflictDialog(),
          );
          
          switch (choice) {
            case FileConflictChoice.overwrite:
              break;
            case FileConflictChoice.saveAs:
              return _saveAs();
            case FileConflictChoice.cancel:
            default:
              return;
          }
        }
      }

      await existingFile.writeAsString(currentContent);
      setState(() => _originalFileHash = currentHash);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully saved to $_currentFilePath'))
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: ${e.toString()}'))
      );
    }
  }

  Future<void> _saveAs() async {
    final downloadsDir = await ExternalPath.getExternalStoragePublicDirectory(
      ExternalPath.DIRECTORY_DOWNLOADS
    );
    
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save As',
      initialDirectory: downloadsDir,
      fileName: _currentFilePath?.split('/').last ?? 'new_file.dart',
    );
    
    if (path == null) return;
    
    final file = File(path);
    await file.writeAsString(_controller.text);
    
    setState(() {
      _currentFilePath = path;
      _originalFileHash = _calculateHash(_controller.text);
    });
  }

  String _calculateHash(String content) {
    return md5.convert(utf8.encode(content)).toString();
  }

  Widget _buildFileConflictDialog() {
    return AlertDialog(
      title: const Text('File Modified'),
      content: const Text('This file has been modified by another application. '
          'How would you like to proceed?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, FileConflictChoice.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, FileConflictChoice.saveAs),
          child: const Text('Save As'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, FileConflictChoice.overwrite),
          child: const Text('Overwrite'),
        ),
      ],
    );
  }

  void _undo() {
    if (_controller.canUndo) {
      _controller.undo();
    }
  }

  void _redo() {
    if (_controller.canRedo) {
      _controller.redo();
    }
  }

  void _handleKeyEvent(RawKeyEvent event) {
  if (event is! RawKeyDownEvent) return;
  
  final selection = _controller.selection;
  final isShiftPressed = event.isShiftPressed;

  void handleMove(AxisDirection direction) {
    if (isShiftPressed) {
      _controller.extendSelection(direction);
    } else {
      _controller.moveCursor(direction);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentFilePath ?? 'Untitled'),
        actions: [
          IconButton(icon: const Icon(Icons.file_open), onPressed: _openFile),
          IconButton(icon: const Icon(Icons.save), onPressed: _saveFile),
          IconButton(icon: const Icon(Icons.undo), onPressed: _undo),
          IconButton(icon: const Icon(Icons.redo), onPressed: _redo),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RawKeyboardListener(
              focusNode: _keyboardFocusNode,
              onKey: _handleKeyEvent,
              child: CodeEditor(
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
            ),
          ),
          _buildBottomToolbar(),
        ],
      ),
    );
  }

  Widget _buildBottomToolbar() {
  return ValueListenableBuilder<CodeLineEditingValue>(
    valueListenable: _controller,
    builder: (context, value, child) {
      final hasSelection = value.selection != const CodeLineSelection.zero();
      return Container(
        color: Colors.grey[900],
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.content_copy),
              onPressed: hasSelection ? () async {
                await Clipboard.setData(ClipboardData(
                  text: _controller.selectedText
                ));
              } : null,
              tooltip: 'Copy',
            ),
              IconButton(
                icon: const Icon(Icons.content_cut),
                onPressed: hasSelection ? () => _controller.cut() : null,
                tooltip: 'Cut',
              ),
              IconButton(
                icon: const Icon(Icons.content_paste),
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data != null && data.text != null) {
                 _controller.replaceSelection(data.text!);
                  }
                },
                tooltip: 'Paste',
              ),
            IconButton(
              icon: const Icon(Icons.arrow_upward),
              onPressed: hasSelection ? () => _controller.moveSelectionLinesUp() : null,
              tooltip: 'Move Up',
            ),
            IconButton(
              icon: const Icon(Icons.arrow_downward),
              onPressed: hasSelection ? () => _controller.moveSelectionLinesDown() : null,
              tooltip: 'Move Down',
            ),
          ],
        ),
      );
    },
  );
}

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }
}

enum FileConflictChoice { cancel, overwrite, saveAs }