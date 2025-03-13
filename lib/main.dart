import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
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
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      setState(() {
        _currentFilePath = file.path;
        _controller.value = CodeLineEditingValue(codeLines: CodeLines.fromText(content));
      });
    }
  }

  Future<void> _saveFile() async {
  try {
    String? savePath = _currentFilePath;
    
    if (savePath == null) {
      final String fileName = _currentFilePath?.split('/').last ?? 'untitled.dart';
      final initialDir = await getApplicationDocumentsDirectory();
      
      final newPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save File',
        fileName: fileName,
        initialDirectory: initialDir.path,
      );
      
      if (newPath == null) return; // User cancelled
      savePath = newPath;
    }

    final file = File(savePath);
    await file.writeAsString(_controller.text);
    
    setState(() => _currentFilePath = savePath);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved to ${file.path}'),
        duration: const Duration(seconds: 2),
      )
    );
    
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Save failed: ${e.toString()}'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      )
    );
  }
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