import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/json.dart';
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
    _controller.addListener(_saveHistory);
  }

  void _saveHistory() {
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(_controller.value);
    _historyIndex++;
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
    if (_currentFilePath == null) {
      final path = await getApplicationDocumentsDirectory();
      final newPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save File',
        fileName: 'untitled.json',
      );
      if (newPath != null) _currentFilePath = newPath;
    }

    if (_currentFilePath != null) {
      await File(_currentFilePath!).writeAsString(_controller.text);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to $_currentFilePath')),
      );
    }
  }

  void _undo() {
    if (_historyIndex > 0) {
      setState(() {
        _historyIndex--;
        _controller.value = _history[_historyIndex];
      });
    }
  }

  void _redo() {
    if (_historyIndex < _history.length - 1) {
      setState(() {
        _historyIndex++;
        _controller.value = _history[_historyIndex];
      });
    }
  }

  void _handleKeyEvent(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return;
    
    final selection = _controller.selection;
    final basePosition = selection.base;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _controller.moveCursor(AxisDirection.left);
        break;
      case LogicalKeyboardKey.arrowRight:
        _controller.moveCursor(AxisDirection.right);
        break;
      case LogicalKeyboardKey.arrowUp:
        _controller.moveCursor(AxisDirection.up);
        break;
      case LogicalKeyboardKey.arrowDown:
        _controller.moveCursor(AxisDirection.down);
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
                    languages: {'json': CodeHighlightThemeMode(mode: langJson)},
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
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                icon: const Icon(Icons.content_copy),
                onPressed: hasSelection ? () => _controller.copy() : null,
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
                    _controller.insert(data.text!);
                  }
                },
                tooltip: 'Paste',
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