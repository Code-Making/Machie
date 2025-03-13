import 'dart:io';
import 'package:flutter/material.dart';
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
  String? _currentFilePath;
  final List<CodeLineEditingValue> _history = [];
  int _historyIndex = -1;

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController(
      codeLines: CodeLines.fromText('// Start coding...\n{\n  // Code block\n}'),
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
        fileName: 'untitled.dart',
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
      body: CodeEditor(
        controller: _controller,
        style: CodeEditorStyle(
          fontSize: 14,
          fontFamily: 'FiraCode',
          codeTheme: CodeHighlightTheme(
            languages: {
              'dart': CodeHighlightThemeMode(mode: langDart)
            },
            theme: atomOneDarkTheme,
          ),
          chunkIndicatorStyle: const CodeChunkIndicatorStyle(
            color: Colors.blueGrey,
            hoverColor: Colors.blue,
          ),
        ),
        indicatorBuilder: (context, editingController, chunkController, notifier) {
          return Row(
            children: [
              DefaultCodeLineNumber(
                controller: editingController,
                notifier: notifier,
                textStyle: const TextStyle(color: Colors.grey),
              ),
              Container(
                width: 1,
                color: Colors.grey.withOpacity(0.5),
              ),
              DefaultCodeChunkIndicator(
                controller: chunkController,
                notifier: notifier,
                iconSize: 14,
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}