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
  
  String? _currentFilePath;
  String? _originalFileHash;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController(
      codeLines: CodeLines.fromText('// Start coding...\n'),
    );
  }

  Future<void> _openFile() async {
    setState(() => _isLoading = true);
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final content = await File(file.path!).readAsString();
      
      setState(() {
        _currentFilePath = file.path;
        _originalFileHash = _calculateHash(content);
      });

      _controller.value = CodeLineEditingValue(
        codeLines: CodeLines.fromText(content)
      );
    } catch (e) {
      _showError('Open failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveFile({bool forceDialog = false}) async {
    try {
      String? savePath = _currentFilePath;
      final currentContent = _controller.text;
      
      if (forceDialog || savePath == null) {
        savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save File',
          fileName: _currentFilePath?.split('/').last,
        );
        if (savePath == null) return;
      }

      if (await File(savePath).exists() && !forceDialog) {
        final diskContent = await File(savePath).readAsString();
        if (_calculateHash(diskContent) != _originalFileHash) {
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
          if (choice != true) return;
        }
      }

      await File(savePath).writeAsString(currentContent);
      setState(() {
        _currentFilePath = savePath;
        _originalFileHash = _calculateHash(currentContent);
      });
      _showSuccess('Saved successfully');
    } catch (e) {
      _showError('Save failed: $e');
    }
  }

  String _calculateHash(String content) {
    return md5.convert(utf8.encode(content)).toString();
  }

  Widget _buildBottomToolbar() {
    return ValueListenableBuilder<CodeLineEditingValue>(
      valueListenable: _controller,
      builder: (context, value, child) {
        final hasSelection = value.selection != const CodeLineSelection.zero();
        return Container(
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
                  if (data?.text != null) {
                    _controller.replaceSelection(data!.text!);
                  }
                },
                tooltip: 'Paste',
              ),
              IconButton(
                icon: const Icon(Icons.arrow_upward),
                onPressed: hasSelection ? _controller.moveSelectionLinesUp : null,
                tooltip: 'Move Up',
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward),
                onPressed: hasSelection ? _controller.moveSelectionLinesDown : null,
                tooltip: 'Move Down',
              ),
            ],
          ),
        );
      },
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