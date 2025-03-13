import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:re_editor/re_editor.dart';

void main() => runApp(const CodeEditorApp());

class CodeEditorApp extends StatelessWidget {
  const CodeEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: EditorScreen(),
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
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController(
      codeLines: CodeLines.fromText('// Start coding...\n'),
    );
    _controller.addListener(_saveState);
  }

  void _saveState() {
    _undoStack.add(_controller.text);
    _redoStack.clear();
  }

  Future<void> _newFile() async {
    setState(() {
      _currentFilePath = null;
      _controller = CodeLineEditingController(codeLines: CodeLines.empty);
    });
  }

  Future<void> _openFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      setState(() {
        _currentFilePath = file.path;
        _controller = CodeLineEditingController(codeLines: CodeLines.fromText(content));
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
    if (_undoStack.isNotEmpty) {
      _redoStack.add(_controller.text);
      _controller.value = CodeLineEditingValue(
        codeLines: CodeLines.fromText(_undoStack.removeLast()),
      );
    }
  }

  void _redo() {
    if (_redoStack.isNotEmpty) {
      _undoStack.add(_controller.text);
      _controller.value = CodeLineEditingValue(
        codeLines: CodeLines.fromText(_redoStack.removeLast()),
      );
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
            child: CodeEditor(
              controller: _controller,
              style: const CodeEditorStyle(
                fontSize: 14,
                fontFamily: 'monospace',
              ),
            ),
          ),
          if (_currentFilePath != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text('File: $_currentFilePath'),
            ),
        ],
      ),
    );
  }
}